import Foundation

/// Context passed to a provider adapter when preparing a request.
struct RequestContext: Sendable {
  let sessionID: String
  let model: ModelDescriptor
  let auth: AuthMode?
  let variant: ReasoningVariant?

  init(
    sessionID: String,
    model: ModelDescriptor,
    auth: AuthMode?,
    variant: ReasoningVariant?
  ) {
    self.sessionID = sessionID
    self.model = model
    self.auth = auth
    self.variant = variant
  }
}

/// An HTTP request ready for execution, after adapter preparation.
struct PreparedRequest: Sendable {
  var url: URL
  var method: String
  var headers: [String: String]
  var body: Data

  init(
    url: URL,
    method: String = "POST",
    headers: [String: String],
    body: Data
  ) {
    self.url = url
    self.method = method
    self.headers = headers
    self.body = body
  }
}

/// Adapts generic LLM requests for a specific provider.
///
/// Each provider (OpenAI, Anthropic, Z.AI) has its own adapter that handles
/// authentication headers, URL rewriting, model filtering, and default options.
protocol ProviderAdapter: Sendable {
  /// Which provider this adapter handles.
  var providerID: ProviderID { get }

  /// Filters models available for the current auth mode.
  /// E.g., Codex OAuth restricts to subscription-eligible models.
  func allowedModels(
    _ models: [ModelDescriptor],
    auth: AuthMode?
  ) -> [ModelDescriptor]

  /// Provider-level default options merged into every request.
  func defaultOptions(for model: ModelDescriptor) -> [String: JSONValue]

  /// Options applied when a specific reasoning variant is selected.
  func variantOptions(
    for model: ModelDescriptor,
    variant: ReasoningVariant
  ) -> [String: JSONValue]

  /// Applies auth headers, URL rewrites, and any provider-specific patches
  /// to a request before it is executed.
  func prepare(
    request: PreparedRequest,
    context: RequestContext
  ) async throws -> PreparedRequest
}
