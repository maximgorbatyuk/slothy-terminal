import Foundation

/// Drives the OAuth authorization flow for a single provider.
///
/// Each provider (Codex, Claude, etc.) has its own concrete implementation
/// with provider-specific endpoints, client IDs, and token shapes.
protocol OAuthClient: Sendable {
  /// Payload returned by `startAuthorization` containing the URL to open
  /// and any state needed to complete the exchange.
  associatedtype StartPayload: Sendable

  /// Generates an authorization URL and associated PKCE/state values.
  func startAuthorization() async throws -> StartPayload

  /// Exchanges an authorization code + PKCE verifier for tokens.
  ///
  /// This is the primary exchange method for PKCE flows.
  func exchange(code: String, verifier: String) async throws -> OAuthToken

  /// Refreshes an expired token set.
  func refresh(token: OAuthToken) async throws -> OAuthToken
}
