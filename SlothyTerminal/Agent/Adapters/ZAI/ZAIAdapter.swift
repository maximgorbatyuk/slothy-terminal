import Foundation

/// Adapts requests for the Z.AI / Zhipu GLM API.
///
/// Z.AI uses an OpenAI-compatible API surface, so auth is a simple
/// Bearer token. Thinking is enabled by default with no manual variants.
///
/// Supports three endpoint regions (China, International, Coding Plan)
/// and falls back to `ZHIPU_API_KEY` / `ZAI_API_KEY` environment
/// variables when no Keychain credentials are available.
final class ZAIAdapter: ProviderAdapter, Sendable {
  let providerID: ProviderID

  /// The API endpoint URL to use for requests.
  private let endpointURL: URL

  /// Environment variable names checked (in order) as auth fallback.
  private static let envVarNames = ["ZAI_API_KEY", "ZHIPU_API_KEY"]

  /// Creates an adapter for either `.zai` or `.zhipuAI` provider IDs.
  ///
  /// - Parameters:
  ///   - providerID: The provider identifier.
  ///   - endpointURL: The chat completions endpoint. Defaults to the
  ///     China mainland endpoint (`open.bigmodel.cn`).
  init(
    providerID: ProviderID = .zai,
    endpointURL: URL = ZAIEndpoint.codingPlan.chatCompletionsURL
  ) {
    self.providerID = providerID
    self.endpointURL = endpointURL
  }

  func allowedModels(
    _ models: [ModelDescriptor],
    auth: AuthMode?
  ) -> [ModelDescriptor] {
    /// All Z.AI models are available regardless of auth mode.
    models
  }

  func defaultOptions(for model: ModelDescriptor) -> [String: JSONValue] {
    /// Enable thinking by default for Z.AI/GLM models.
    [
      "thinking": .object([
        "type": .string("enabled"),
        "clear_thinking": .bool(false),
      ])
    ]
  }

  func variantOptions(
    for model: ModelDescriptor,
    variant: ReasoningVariant
  ) -> [String: JSONValue] {
    /// Z.AI has no user-selectable reasoning variants.
    [:]
  }

  func prepare(
    request: PreparedRequest,
    context: RequestContext
  ) async throws -> PreparedRequest {
    var req = request
    var headers = req.headers

    /// Override the endpoint URL from RequestBuilder's default.
    req.url = endpointURL

    /// Resolve auth: Keychain → env vars.
    let resolvedAuth = context.auth ?? Self.authFromEnvironment()

    if let auth = resolvedAuth {
      switch auth {
      case .apiKey(let key):
        headers["Authorization"] = "Bearer \(key)"

      case .oauth(let token):
        headers["Authorization"] = "Bearer \(token.accessToken)"
      }
    }

    req.headers = headers
    return req
  }

  // MARK: - Environment variable fallback

  /// Checks `ZAI_API_KEY` and `ZHIPU_API_KEY` environment variables.
  ///
  /// Returns the first non-empty value found, or nil.
  static func authFromEnvironment() -> AuthMode? {
    for name in envVarNames {
      if let value = ProcessInfo.processInfo.environment[name],
         !value.isEmpty
      {
        return .apiKey(value)
      }
    }

    return nil
  }
}
