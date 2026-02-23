import Foundation
import OSLog

/// Adapts requests for the OpenAI / Codex API.
///
/// Handles:
/// - `Authorization: Bearer` for both API key and OAuth
/// - `ChatGPT-Account-Id` header for OAuth subscription context
/// - URL rewrite from standard endpoints to `chatgpt.com/backend-api/codex/responses`
/// - Model filtering: OAuth mode restricts to Codex-compatible models
/// - Default `reasoningEffort` for GPT-5 family models
/// - Automatic OAuth token refresh via `CodexOAuthClient`
final class CodexAdapter: ProviderAdapter, @unchecked Sendable {
  let providerID: ProviderID = .openAI

  private let tokenStore: any TokenStore
  private let oauthClient: CodexOAuthClient
  private let codexEndpoint = URL(string: "https://chatgpt.com/backend-api/codex/responses")!
  private let refreshSkew: TimeInterval = 30

  private let oauthAllowedModels: Set<String> = [
    "gpt-5.1-codex",
    "gpt-5.1-codex-mini",
    "gpt-5.1-codex-max",
    "gpt-5.2",
    "gpt-5.2-codex",
    "gpt-5.3-codex",
  ]

  init(
    tokenStore: any TokenStore,
    oauthClient: CodexOAuthClient? = nil
  ) {
    self.tokenStore = tokenStore
    self.oauthClient = oauthClient ?? CodexOAuthClient(
      clientID: CodexOAuthClient.defaultClientID,
      redirectURI: "http://localhost:1455/auth/callback"
    )
  }

  func allowedModels(
    _ models: [ModelDescriptor],
    auth: AuthMode?
  ) -> [ModelDescriptor] {
    guard case .oauth = auth else {
      return models
    }

    /// OAuth mode restricts to Codex-compatible models.
    return models.filter { model in
      model.modelID.contains("codex") || oauthAllowedModels.contains(model.modelID)
    }
  }

  func defaultOptions(for model: ModelDescriptor) -> [String: JSONValue] {
    var options: [String: JSONValue] = ["store": .bool(false)]

    if model.modelID.contains("gpt-5"),
       !model.modelID.contains("gpt-5-pro")
    {
      options["reasoningEffort"] = .string("medium")
      options["reasoningSummary"] = .string("auto")
    }

    return options
  }

  func variantOptions(
    for model: ModelDescriptor,
    variant: ReasoningVariant
  ) -> [String: JSONValue] {
    guard model.modelID.contains("gpt-") else {
      return [:]
    }

    return ["reasoningEffort": .string(variant.rawValue)]
  }

  func prepare(
    request: PreparedRequest,
    context: RequestContext
  ) async throws -> PreparedRequest {
    var req = request
    var headers = req.headers

    /// Strip any existing auth headers — we set them explicitly.
    headers.removeValue(forKey: "Authorization")
    headers.removeValue(forKey: "authorization")

    guard let auth = context.auth else {
      req.headers = headers
      return req
    }

    switch auth {
    case .apiKey(let key):
      headers["Authorization"] = "Bearer \(key)"

    case .oauth(let token):
      let active = try await refreshIfNeeded(token)
      headers["Authorization"] = "Bearer \(active.accessToken)"

      if let account = active.accountID {
        headers["ChatGPT-Account-Id"] = account
      }

      /// Rewrite standard API endpoints to the Codex subscription endpoint
      /// and transform the body from Chat Completions to Responses API format.
      let path = req.url.path
      if path.contains("/v1/responses") || path.contains("/chat/completions") {
        req.url = codexEndpoint
        req.body = transformToResponsesBody(req.body)
      }
    }

    req.headers = headers
    return req
  }

  // MARK: - Body transformation

  /// Transforms a Chat Completions body into the Codex Responses API format.
  ///
  /// Key differences:
  /// - System message extracted → top-level `instructions`
  /// - `messages` → `input` array of typed items
  /// - Anthropic `tool_use` / `tool_result` → `function_call` / `function_call_output`
  /// - `tools` entries unwrapped from `{"type":"function","function":{…}}` to flat form
  /// - `reasoningEffort` / `reasoningSummary` → `reasoning` object
  private func transformToResponsesBody(_ body: Data) -> Data {
    guard var root = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
      Logger.agent.warning("[CodexAdapter] Failed to decode body for Responses transform")
      return body
    }

    /// Extract system message → instructions.
    var instructions: String?
    if let messages = root["messages"] as? [[String: Any]] {
      var inputItems: [[String: Any]] = []

      for msg in messages {
        let role = msg["role"] as? String ?? ""

        if role == "system" {
          instructions = msg["content"] as? String
          continue
        }

        /// Convert each message into Responses API input items.
        let items = convertMessageToInputItems(msg)
        inputItems.append(contentsOf: items)
      }

      root.removeValue(forKey: "messages")
      root["input"] = inputItems
    }

    root["instructions"] = instructions ?? "You are a helpful coding assistant."

    /// Unwrap tool definitions from Chat Completions wrapper.
    if let tools = root["tools"] as? [[String: Any]] {
      root["tools"] = tools.map { unwrapToolDefinition($0) }
    }

    /// Transform reasoning options into a nested object.
    var reasoning: [String: Any] = [:]
    if let effort = root["reasoningEffort"] as? String {
      reasoning["effort"] = effort
      root.removeValue(forKey: "reasoningEffort")
    }
    if let summary = root["reasoningSummary"] as? String {
      reasoning["summary"] = summary
      root.removeValue(forKey: "reasoningSummary")
    }
    if !reasoning.isEmpty {
      root["reasoning"] = reasoning
    }

    guard let data = try? JSONSerialization.data(withJSONObject: root) else {
      Logger.agent.warning("[CodexAdapter] Failed to re-encode Responses body")
      return body
    }

    return data
  }

  /// Converts a single Anthropic-format message into Responses API input items.
  private func convertMessageToInputItems(
    _ msg: [String: Any]
  ) -> [[String: Any]] {
    let role = msg["role"] as? String ?? ""

    /// Plain text content (string).
    if let text = msg["content"] as? String {
      return [["type": "message", "role": role, "content": text]]
    }

    /// Array content — may contain text, tool_use, or tool_result blocks.
    guard let blocks = msg["content"] as? [[String: Any]] else {
      return [["type": "message", "role": role, "content": ""]]
    }

    var items: [[String: Any]] = []
    var textParts: [String] = []

    for block in blocks {
      let blockType = block["type"] as? String ?? ""

      switch blockType {
      case "text":
        if let text = block["text"] as? String {
          textParts.append(text)
        }

      case "tool_use":
        /// Flush accumulated text first.
        if !textParts.isEmpty {
          items.append([
            "type": "message",
            "role": role,
            "content": textParts.joined(),
          ])
          textParts = []
        }

        let callID = block["id"] as? String ?? ""
        let name = block["name"] as? String ?? ""
        let input = block["input"] ?? [String: Any]()

        /// Serialize input back to JSON string for function_call arguments.
        let argsString: String
        if let inputData = try? JSONSerialization.data(withJSONObject: input),
           let s = String(data: inputData, encoding: .utf8)
        {
          argsString = s
        } else {
          argsString = "{}"
        }

        items.append([
          "type": "function_call",
          "name": name,
          "call_id": callID,
          "arguments": argsString,
        ])

      case "tool_result":
        let callID = block["tool_use_id"] as? String ?? ""
        let content = block["content"] as? String ?? ""
        items.append([
          "type": "function_call_output",
          "call_id": callID,
          "output": content,
        ])

      default:
        break
      }
    }

    /// Flush remaining text.
    if !textParts.isEmpty {
      items.append([
        "type": "message",
        "role": role,
        "content": textParts.joined(),
      ])
    }

    return items
  }

  /// Unwraps Chat Completions tool format to Responses API format.
  ///
  /// Chat Completions: `{"type":"function","function":{"name":…,"description":…,"parameters":…}}`
  /// Responses API: `{"type":"function","name":…,"description":…,"parameters":…}`
  private func unwrapToolDefinition(_ tool: [String: Any]) -> [String: Any] {
    guard let fn = tool["function"] as? [String: Any] else {
      return tool
    }

    var result: [String: Any] = ["type": "function"]
    result["name"] = fn["name"]
    result["description"] = fn["description"]
    result["parameters"] = fn["parameters"]
    return result
  }

  // MARK: - Private

  private func refreshIfNeeded(_ token: OAuthToken) async throws -> OAuthToken {
    guard token.expiresAt.timeIntervalSinceNow <= refreshSkew else {
      return token
    }

    Logger.agent.info("Codex OAuth token expiring soon, refreshing…")
    let refreshed = try await oauthClient.refresh(token: token)
    try await tokenStore.save(provider: .openAI, auth: .oauth(refreshed))
    Logger.agent.info("Codex OAuth token refreshed successfully")
    return refreshed
  }
}
