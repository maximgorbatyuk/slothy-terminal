import Foundation

/// Persists authentication credentials per provider.
///
/// Implementations may use Keychain, in-memory storage (for tests),
/// or any other secure backend.
protocol TokenStore: Sendable {
  /// Loads the stored auth mode for the given provider, or nil if none.
  func load(provider: ProviderID) async throws -> AuthMode?

  /// Saves (or overwrites) the auth mode for the given provider.
  func save(provider: ProviderID, auth: AuthMode) async throws

  /// Removes stored credentials for the given provider.
  func remove(provider: ProviderID) async throws
}
