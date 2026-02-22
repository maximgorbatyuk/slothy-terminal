import Foundation
import Testing

@testable import SlothyTerminalLib

/// Tests the TokenStore contract using MockTokenStore.
///
/// Actual Keychain calls require app entitlements not available in
/// `swift test`, so we verify the contract against the in-memory mock.
/// The real `KeychainTokenStore` follows the same interface.
@Suite("TokenStore")
struct KeychainTokenStoreTests {

  // MARK: - API Key

  @Test("Save and load API key")
  func saveAndLoadAPIKey() async throws {
    let store = MockTokenStore()

    let auth = AuthMode.apiKey("sk-test-key-123")
    try await store.save(provider: .anthropic, auth: auth)

    let loaded = try await store.load(provider: .anthropic)
    #expect(loaded == auth)
  }

  @Test("Load returns nil for missing provider")
  func loadMissing() async throws {
    let store = MockTokenStore()

    let loaded = try await store.load(provider: .openAI)
    #expect(loaded == nil)
  }

  // MARK: - OAuth Token

  @Test("Save and load OAuth token")
  func saveAndLoadOAuth() async throws {
    let store = MockTokenStore()

    let token = OAuthToken(
      accessToken: "access-abc",
      refreshToken: "refresh-xyz",
      expiresAt: Date().addingTimeInterval(3600),
      accountID: "acct-001"
    )
    let auth = AuthMode.oauth(token)
    try await store.save(provider: .openAI, auth: auth)

    let loaded = try await store.load(provider: .openAI)
    #expect(loaded == auth)
  }

  // MARK: - Overwrite

  @Test("Save overwrites existing value")
  func overwrite() async throws {
    let store = MockTokenStore()

    let first = AuthMode.apiKey("old-key")
    let second = AuthMode.apiKey("new-key")

    try await store.save(provider: .anthropic, auth: first)
    try await store.save(provider: .anthropic, auth: second)

    let loaded = try await store.load(provider: .anthropic)
    #expect(loaded == second)
  }

  // MARK: - Remove

  @Test("Remove deletes stored credentials")
  func remove() async throws {
    let store = MockTokenStore()

    try await store.save(provider: .zai, auth: .apiKey("key"))
    try await store.remove(provider: .zai)

    let loaded = try await store.load(provider: .zai)
    #expect(loaded == nil)
  }

  @Test("Remove non-existent provider does not throw")
  func removeNonExistent() async throws {
    let store = MockTokenStore()
    try await store.remove(provider: .zhipuAI)
  }

  // MARK: - Provider isolation

  @Test("Providers are isolated from each other")
  func providerIsolation() async throws {
    let store = MockTokenStore()

    try await store.save(provider: .anthropic, auth: .apiKey("anthropic-key"))
    try await store.save(provider: .openAI, auth: .apiKey("openai-key"))

    let anthropic = try await store.load(provider: .anthropic)
    let openAI = try await store.load(provider: .openAI)
    let zai = try await store.load(provider: .zai)

    #expect(anthropic == .apiKey("anthropic-key"))
    #expect(openAI == .apiKey("openai-key"))
    #expect(zai == nil)
  }

  // MARK: - Call counting

  @Test("Tracks call counts")
  func callCounting() async throws {
    let store = MockTokenStore()

    _ = try await store.load(provider: .anthropic)
    _ = try await store.load(provider: .openAI)
    try await store.save(provider: .anthropic, auth: .apiKey("k"))
    try await store.remove(provider: .anthropic)

    let loadCount = await store.loadCount
    let saveCount = await store.saveCount
    let removeCount = await store.removeCount

    #expect(loadCount == 2)
    #expect(saveCount == 1)
    #expect(removeCount == 1)
  }
}
