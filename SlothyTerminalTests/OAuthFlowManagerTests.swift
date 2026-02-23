import Foundation
import Testing

@testable import SlothyTerminalLib

@Suite("OAuthFlowManager")
@MainActor
struct OAuthFlowManagerTests {

  private func makeManager(
    tokenStore: MockTokenStore = MockTokenStore(),
    urlOpener: @escaping @Sendable (URL) -> Void = { _ in }
  ) -> OAuthFlowManager {
    OAuthFlowManager(
      tokenStore: tokenStore,
      callbackPort: 0,
      urlOpener: urlOpener
    )
  }

  // MARK: - supportsOAuth

  @Test("supportsOAuth returns true for OpenAI")
  func supportsOAuthOpenAI() {
    let manager = makeManager()

    #expect(manager.supportsOAuth(for: .openAI) == true)
  }

  @Test("supportsOAuth returns true for Anthropic")
  func supportsOAuthAnthropic() {
    let manager = makeManager()

    #expect(manager.supportsOAuth(for: .anthropic) == true)
  }

  @Test("supportsOAuth returns false for Z.AI")
  func supportsOAuthZAI() {
    let manager = makeManager()

    #expect(manager.supportsOAuth(for: .zai) == false)
  }

  // MARK: - startFlow for unsupported provider

  @Test("startFlow for unsupported provider stays idle")
  func startFlowUnsupportedProvider() {
    let manager = makeManager()
    manager.startFlow(for: .zai)

    #expect(manager.flowState[.zai] == nil)
  }

  @Test("startFlow for Anthropic sets authorizing state")
  func startFlowAnthropicSetsAuthorizing() {
    let manager = makeManager()
    manager.startFlow(for: .anthropic)

    #expect(manager.flowState[.anthropic] == .authorizing)
  }

  // MARK: - PKCE utilities (via CodexOAuthClient)

  @Test("PKCE verifier is valid base64url characters")
  func pkceVerifierCharacters() {
    let verifier = CodexOAuthClient.randomURLSafe(length: 64)

    #expect(verifier.count == 64)

    let validChars = CharacterSet.alphanumerics.union(
      CharacterSet(charactersIn: "-._~")
    )
    for scalar in verifier.unicodeScalars {
      #expect(validChars.contains(scalar))
    }
  }

  @Test("PKCE challenge is valid base64url (no padding)")
  func pkceChallengeFormat() {
    let verifier = CodexOAuthClient.randomURLSafe(length: 64)
    let challenge = CodexOAuthClient.pkceChallenge(verifier)

    /// Base64url should not contain +, /, or =
    #expect(!challenge.contains("+"))
    #expect(!challenge.contains("/"))
    #expect(!challenge.contains("="))
    #expect(!challenge.isEmpty)
  }

  @Test("Different verifiers produce different challenges")
  func pkceChallengeDeterministic() {
    let v1 = CodexOAuthClient.randomURLSafe(length: 64)
    let v2 = CodexOAuthClient.randomURLSafe(length: 64)
    let c1 = CodexOAuthClient.pkceChallenge(v1)
    let c2 = CodexOAuthClient.pkceChallenge(v2)

    #expect(c1 != c2)
  }

  @Test("Same verifier produces same challenge")
  func pkceChallengeSameInput() {
    let verifier = "test-verifier-string"
    let c1 = CodexOAuthClient.pkceChallenge(verifier)
    let c2 = CodexOAuthClient.pkceChallenge(verifier)

    #expect(c1 == c2)
  }

  // MARK: - Flow state initial values

  @Test("Initial flow state is empty")
  func initialFlowState() {
    let manager = makeManager()

    #expect(manager.flowState.isEmpty)
  }

  // MARK: - startFlow sets authorizing state

  @Test("startFlow for OpenAI sets authorizing state")
  func startFlowSetsAuthorizing() {
    let manager = makeManager()
    manager.startFlow(for: .openAI)

    #expect(manager.flowState[.openAI] == .authorizing)
  }

  // MARK: - Duplicate flow guard

  @Test("startFlow while authorizing does not reset state")
  func duplicateFlowGuard() {
    let manager = makeManager()
    manager.startFlow(for: .openAI)

    #expect(manager.flowState[.openAI] == .authorizing)

    /// Calling again should not change state.
    manager.startFlow(for: .openAI)

    #expect(manager.flowState[.openAI] == .authorizing)
  }

  // MARK: - Cancel flow

  @Test("cancelFlow resets state to idle")
  func cancelFlowResetsToIdle() {
    let manager = makeManager()
    manager.startFlow(for: .anthropic)

    #expect(manager.flowState[.anthropic] == .authorizing)

    manager.cancelFlow(for: .anthropic)

    #expect(manager.flowState[.anthropic] == .idle)
  }

  // MARK: - submitCode guard

  @Test("submitCode without awaitingCode state is no-op")
  func submitCodeWithoutAwaitingCodeIsNoOp() {
    let manager = makeManager()

    /// No flow started — submitCode should do nothing.
    manager.submitCode("test-code", for: .anthropic)

    #expect(manager.flowState[.anthropic] == nil)
  }
}
