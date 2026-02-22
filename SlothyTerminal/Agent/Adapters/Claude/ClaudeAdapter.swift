import Foundation

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

    /// Merge required beta headers, preserving any caller-provided values.
    let incoming = headers["anthropic-beta"]?
      .split(separator: ",")
      .map { $0.trimmingCharacters(in: .whitespaces) } ?? []
    let required = ["interleaved-thinking-2025-05-14"]
    let merged = Array(Set(incoming + required))
    headers["anthropic-beta"] = merged.joined(separator: ",")

    guard let auth = context.auth else {
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
    /// when the ClaudeOAuthClient is fully connected.
    /// For now, return the existing token and let the API reject if expired.
    return token
  }
}
