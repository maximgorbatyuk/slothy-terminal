import Foundation
@testable import SlothyTerminalLib

/// In-memory token store for test isolation.
///
/// Mirrors the `TokenStore` contract without touching the Keychain,
/// which requires entitlements unavailable in `swift test`.
actor MockTokenStore: TokenStore {
  private var storage: [ProviderID: AuthMode] = [:]

  /// Number of times `save` was called.
  private(set) var saveCount = 0

  /// Number of times `load` was called.
  private(set) var loadCount = 0

  /// Number of times `remove` was called.
  private(set) var removeCount = 0

  func load(provider: ProviderID) async throws -> AuthMode? {
    loadCount += 1
    return storage[provider]
  }

  func save(provider: ProviderID, auth: AuthMode) async throws {
    saveCount += 1
    storage[provider] = auth
  }

  func remove(provider: ProviderID) async throws {
    removeCount += 1
    storage.removeValue(forKey: provider)
  }

  // MARK: - Test helpers

  /// Resets all stored data and counters.
  func reset() {
    storage.removeAll()
    saveCount = 0
    loadCount = 0
    removeCount = 0
  }

  /// Returns the current storage snapshot for assertions.
  var allEntries: [ProviderID: AuthMode] {
    storage
  }
}
