import Foundation

/// Adapts requests for the Z.AI / Zhipu GLM API.
///
/// Z.AI uses an OpenAI-compatible API surface, so auth is a simple
/// Bearer token. Thinking is enabled by default with no manual variants.
final class ZAIAdapter: ProviderAdapter, Sendable {
  let providerID: ProviderID

  /// Creates an adapter for either `.zai` or `.zhipuAI` provider IDs.
  init(providerID: ProviderID = .zai) {
    self.providerID = providerID
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

    guard let auth = context.auth else {
      req.headers = headers
      return req
    }

    switch auth {
    case .apiKey(let key):
      headers["Authorization"] = "Bearer \(key)"

    case .oauth(let token):
      headers["Authorization"] = "Bearer \(token.accessToken)"
    }

    req.headers = headers
    return req
  }
}
