import Foundation
import OSLog

/// Adapts requests for the Anthropic Messages API.
///
/// Handles:
/// - `x-api-key` header for API key auth
/// - `Authorization: Bearer` for OAuth auth with automatic token refresh
/// - `anthropic-version` and `anthropic-beta` headers
/// - Thinking variant options (`budgetTokens`)
final class ClaudeAdapter: ProviderAdapter, @unchecked Sendable {
  let providerID: ProviderID = .anthropic

  private let tokenStore: any TokenStore
  private let refreshSkew: TimeInterval = 30

  init(tokenStore: any TokenStore) {
    self.tokenStore = tokenStore
  }

  func allowedModels(
    _ models: [ModelDescriptor],
    auth: AuthMode?
  ) -> [ModelDescriptor] {
    /// All Claude models are available regardless of auth mode.
    models
  }

  func defaultOptions(for model: ModelDescriptor) -> [String: JSONValue] {
    /// Empty by default — rely on variant mapping for thinking.
    [:]
  }

  func variantOptions(
    for model: ModelDescriptor,
    variant: ReasoningVariant
  ) -> [String: JSONValue] {
    switch variant {
    case .high:
      return [
        "thinking": .object([
          "type": .string("enabled"),
          "budgetTokens": .number(16_000),
        ])
      ]

    case .max:
      return [
        "thinking": .object([
          "type": .string("enabled"),
          "budgetTokens": .number(31_999),
        ])
      ]

    case .low, .medium, .none, .minimal, .xhigh:
      /// For adaptive models the mapper handles these;
      /// the adapter returns empty for unsupported variants.
      return [:]
    }
  }

  func prepare(
    request: PreparedRequest,
    context: RequestContext
  ) async throws -> PreparedRequest {
    var req = request
    var headers = req.headers

    let isOAuth: Bool
    if case .oauth = context.auth {
      isOAuth = true
    } else {
      isOAuth = false
    }

    /// Merge required beta headers, preserving any caller-provided values.
    /// OAuth requires the `oauth-2025-04-20` beta flag — without it the
    /// API rejects Bearer tokens with "OAuth authentication is currently
    /// not supported".
    let incoming = headers["anthropic-beta"]?
      .split(separator: ",")
      .map { $0.trimmingCharacters(in: .whitespaces) } ?? []
    var required = [
      "interleaved-thinking-2025-05-14",
      "fine-grained-tool-streaming-2025-05-14",
    ]
    if isOAuth {
      required.append(contentsOf: [
        "oauth-2025-04-20",
        "claude-code-20250219",
      ])
    }
    let merged = Array(Set(incoming + required))
    headers["anthropic-beta"] = merged.joined(separator: ",")

    guard let auth = context.auth else {
      /// No auth — still set required headers.
      headers["anthropic-version"] = "2023-06-01"
      req.headers = headers
      return req
    }

    switch auth {
    case .apiKey(let key):
      headers["x-api-key"] = key
      headers["anthropic-version"] = "2023-06-01"

    case .oauth(let token):
      let active = try await refreshIfNeeded(token)
      headers.removeValue(forKey: "x-api-key")
      headers["Authorization"] = "Bearer \(active.accessToken)"
      headers["anthropic-version"] = "2023-06-01"

      /// Identify as Claude CLI so the OAuth backend accepts our requests.
      headers["user-agent"] = "claude-cli/2.1.2 (external, cli)"

      /// Anthropic requires `?beta=true` on the messages endpoint
      /// when authenticating via OAuth.
      req.url = Self.appendBetaQuery(to: req.url)

      /// The OAuth endpoint expects MCP-style tool names (prefixed with
      /// `mcp_`). Rewrite tool definitions and `tool_use` blocks in the
      /// conversation history before sending.
      req.body = Self.prefixToolNames(in: req.body)
    }

    req.headers = headers
    return req
  }

  // MARK: - Tool name prefixing (OAuth)

  /// Prefix used by the OAuth endpoint for tool names.
  static let toolPrefix = "mcp_"

  /// Rewrites the JSON request body so that:
  /// - Every tool definition in `tools[].name` is prefixed with `mcp_`
  /// - Every `tool_use` block in `messages[].content[].name` is prefixed
  ///
  /// `tool_result` blocks are not modified (they reference tools by
  /// `tool_use_id`, not by name).
  ///
  /// Returns the original data unmodified if parsing fails.
  static func prefixToolNames(in body: Data) -> Data {
    guard var parsed = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
      return body
    }

    let prefix = toolPrefix

    /// Prefix tool definitions.
    if var tools = parsed["tools"] as? [[String: Any]] {
      for i in tools.indices {
        if let name = tools[i]["name"] as? String,
           !name.hasPrefix(prefix)
        {
          tools[i]["name"] = prefix + name
        }
      }
      parsed["tools"] = tools
    }

    /// Prefix `tool_use` blocks in message history.
    if var messages = parsed["messages"] as? [[String: Any]] {
      for i in messages.indices {
        if var content = messages[i]["content"] as? [[String: Any]] {
          for j in content.indices {
            if content[j]["type"] as? String == "tool_use",
               let name = content[j]["name"] as? String,
               !name.hasPrefix(prefix)
            {
              content[j]["name"] = prefix + name
            }
          }
          messages[i]["content"] = content
        }
      }
      parsed["messages"] = messages
    }

    return (try? JSONSerialization.data(withJSONObject: parsed)) ?? body
  }

  // MARK: - URL helpers

  /// Appends `beta=true` query parameter to the URL if not already present.
  private static func appendBetaQuery(to url: URL) -> URL {
    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      return url
    }

    let items = components.queryItems ?? []

    guard !items.contains(where: { $0.name == "beta" }) else {
      return url
    }

    components.queryItems = items + [URLQueryItem(name: "beta", value: "true")]
    return components.url ?? url
  }

  // MARK: - Private

  private func refreshIfNeeded(_ token: OAuthToken) async throws -> OAuthToken {
    guard token.expiresAt.timeIntervalSinceNow <= refreshSkew else {
      return token
    }

    Logger.agent.info("Claude OAuth token near expiry — refreshing")

    /// redirectURI is unused for refresh grant — only needed for authorization.
    let client = ClaudeOAuthClient(
      clientID: ClaudeOAuthClient.defaultClientID,
      redirectURI: "unused"
    )

    do {
      let refreshed = try await client.refresh(token: token)
      try await tokenStore.save(provider: .anthropic, auth: .oauth(refreshed))
      Logger.agent.info("Claude OAuth token refreshed successfully")
      return refreshed
    } catch {
      Logger.agent.error(
        "Claude OAuth token refresh failed: \(error.localizedDescription) — using expired token"
      )
      return token
    }
  }
}
