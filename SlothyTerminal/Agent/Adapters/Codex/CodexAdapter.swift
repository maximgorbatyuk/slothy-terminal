import Foundation

/// Adapts requests for the OpenAI / Codex API.
///
/// Handles:
/// - `Authorization: Bearer` for both API key and OAuth
/// - `ChatGPT-Account-Id` header for OAuth subscription context
/// - URL rewrite from standard endpoints to `chatgpt.com/backend-api/codex/responses`
/// - Model filtering: OAuth mode restricts to Codex-compatible models
/// - Default `reasoningEffort` for GPT-5 family models
final class CodexAdapter: ProviderAdapter, @unchecked Sendable {
  let providerID: ProviderID = .openAI

  private let tokenStore: any TokenStore
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

  init(tokenStore: any TokenStore) {
    self.tokenStore = tokenStore
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

      /// Rewrite standard API endpoints to the Codex subscription endpoint.
      let path = req.url.path
      if path.contains("/v1/responses") || path.contains("/chat/completions") {
        req.url = codexEndpoint
      }
    }

    req.headers = headers
    return req
  }

  // MARK: - Private

  private func refreshIfNeeded(_ token: OAuthToken) async throws -> OAuthToken {
    guard token.expiresAt.timeIntervalSinceNow <= refreshSkew else {
      return token
    }

    /// Token refresh is not yet implemented — will be wired in Phase 9
    /// when the CodexOAuthClient is fully connected.
    return token
  }
}
