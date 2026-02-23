import Foundation
import OSLog

/// State of an OAuth authorization flow for a single provider.
enum OAuthFlowState: Sendable, Equatable {
  case idle
  case authorizing

  /// Browser opened — waiting for the user to paste the authorization code.
  ///
  /// Used for providers whose OAuth server does not support localhost
  /// redirect URIs (e.g. Anthropic). The browser redirects to a hosted
  /// page that displays the code for manual copy-paste.
  case awaitingCode

  case exchanging
  case succeeded
  case failed(String)
}

/// Error when the OAuth callback `state` parameter doesn't match
/// the value sent in the authorization request (CSRF protection).
enum OAuthFlowError: Error, LocalizedError {
  case stateMismatch

  var errorDescription: String? {
    "OAuth state parameter mismatch — possible CSRF attack"
  }
}

/// Orchestrates the OAuth PKCE authorization flow for providers that support it.
///
/// Two flow variants:
/// - **Localhost callback** (OpenAI/Codex): Starts `OAuthCallbackServer`,
///   browser redirects back to localhost, code captured automatically.
/// - **Hosted callback** (Anthropic): Uses Anthropic's hosted redirect URI
///   (`console.anthropic.com/oauth/code/callback`). The browser shows the
///   code on the page — user copies it and pastes into the app via
///   `submitCode(_:for:)`.
///
/// UI binds directly to `flowState` for real-time feedback.
@Observable
@MainActor
final class OAuthFlowManager {
  /// Current flow state per provider — UI binds to this.
  private(set) var flowState: [ProviderID: OAuthFlowState] = [:]

  private let tokenStore: any TokenStore
  private let urlOpener: @Sendable (URL) -> Void
  private let callbackPort: UInt16

  /// PKCE verifier stored between `startFlow` and `submitCode` for
  /// hosted-callback providers (Anthropic).
  private var pendingVerifier: [ProviderID: String] = [:]

  init(
    tokenStore: any TokenStore,
    callbackPort: UInt16 = 1455,
    urlOpener: @escaping @Sendable (URL) -> Void
  ) {
    self.tokenStore = tokenStore
    self.callbackPort = callbackPort
    self.urlOpener = urlOpener
  }

  /// Whether the given provider supports OAuth sign-in.
  func supportsOAuth(for provider: ProviderID) -> Bool {
    provider == .openAI || provider == .anthropic
  }

  /// Starts the OAuth PKCE flow for the given provider.
  ///
  /// Updates `flowState[provider]` through each phase. On success, tokens
  /// are saved to the token store and state auto-resets to `.idle` after 2 seconds.
  func startFlow(for provider: ProviderID) {
    guard supportsOAuth(for: provider) else {
      Logger.agent.warning("OAuth not supported for provider \(provider.rawValue)")
      return
    }

    guard flowState[provider] != .authorizing,
          flowState[provider] != .exchanging,
          flowState[provider] != .awaitingCode
    else {
      Logger.agent.info("OAuth flow already in progress for \(provider.rawValue)")
      return
    }

    flowState[provider] = .authorizing

    Task {
      switch provider {
      case .openAI:
        await runCodexFlow()

      case .anthropic:
        await runClaudeFlow()

      default:
        break
      }
    }
  }

  /// Submits a manually-copied authorization code for hosted-callback flows.
  ///
  /// Called by the UI after the user pastes the code from the browser.
  func submitCode(_ code: String, for provider: ProviderID) {
    guard flowState[provider] == .awaitingCode else {
      return
    }

    guard let verifier = pendingVerifier[provider] else {
      flowState[provider] = .failed("Missing PKCE verifier — please restart the flow")
      return
    }

    flowState[provider] = .exchanging

    Task {
      await exchangeClaudeCode(code, verifier: verifier)
    }
  }

  /// Cancels a pending code-paste flow and resets to idle.
  func cancelFlow(for provider: ProviderID) {
    pendingVerifier.removeValue(forKey: provider)
    flowState[provider] = .idle
  }

  // MARK: - Private — Codex (localhost callback)

  private func runCodexFlow() async {
    let server = OAuthCallbackServer(port: callbackPort)
    let redirectURI = server.redirectURI
    let client = CodexOAuthClient(
      clientID: CodexOAuthClient.defaultClientID,
      redirectURI: redirectURI
    )

    do {
      let start = try await client.startAuthorization()

      let result = try await waitForCallback(
        server: server,
        authorizeURL: start.authorizeURL,
        expectedState: start.state
      )

      flowState[.openAI] = .exchanging

      let token = try await client.exchange(code: result.code, verifier: start.verifier)

      try await tokenStore.save(provider: .openAI, auth: .oauth(token))

      flowState[.openAI] = .succeeded
      Logger.agent.info("Codex OAuth flow completed successfully")

      try? await Task.sleep(for: .seconds(2))
      if flowState[.openAI] == .succeeded {
        flowState[.openAI] = .idle
      }

    } catch {
      flowState[.openAI] = .failed(error.localizedDescription)
      Logger.agent.error("Codex OAuth flow failed: \(error.localizedDescription)")
    }
  }

  // MARK: - Private — Claude (hosted redirect, manual code paste)

  /// Opens the browser for Claude OAuth. The user authorizes, then the
  /// browser redirects to Anthropic's hosted page which displays the code.
  /// State transitions to `.awaitingCode` — the UI shows a text field
  /// for the user to paste the code.
  private func runClaudeFlow() async {
    let client = ClaudeOAuthClient(
      clientID: ClaudeOAuthClient.defaultClientID,
      redirectURI: ClaudeOAuthClient.hostedRedirectURI
    )

    do {
      let start = try await client.startAuthorization()

      /// Store verifier for later exchange when the user pastes the code.
      pendingVerifier[.anthropic] = start.verifier

      urlOpener(start.authorizeURL)

      flowState[.anthropic] = .awaitingCode

    } catch {
      flowState[.anthropic] = .failed(error.localizedDescription)
      Logger.agent.error("Claude OAuth flow failed to start: \(error.localizedDescription)")
    }
  }

  /// Exchanges a manually-pasted Claude authorization code for tokens.
  private func exchangeClaudeCode(_ code: String, verifier: String) async {
    let client = ClaudeOAuthClient(
      clientID: ClaudeOAuthClient.defaultClientID,
      redirectURI: ClaudeOAuthClient.hostedRedirectURI
    )

    do {
      let token = try await client.exchange(code: code, verifier: verifier)

      try await tokenStore.save(provider: .anthropic, auth: .oauth(token))

      pendingVerifier.removeValue(forKey: .anthropic)
      flowState[.anthropic] = .succeeded
      Logger.agent.info("Claude OAuth flow completed successfully")

      try? await Task.sleep(for: .seconds(2))
      if flowState[.anthropic] == .succeeded {
        flowState[.anthropic] = .idle
      }

    } catch {
      flowState[.anthropic] = .failed(error.localizedDescription)
      Logger.agent.error("Claude OAuth exchange failed: \(error.localizedDescription)")
    }
  }

  // MARK: - Private — Localhost callback helper

  /// Starts the callback server, opens the browser, waits for the redirect,
  /// validates the `state` parameter, and returns the callback result.
  ///
  /// Always stops the server when done (success or failure).
  private func waitForCallback(
    server: OAuthCallbackServer,
    authorizeURL: URL,
    expectedState: String
  ) async throws -> OAuthCallbackResult {
    let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<OAuthCallbackResult, Error>) in
      do {
        try server.start { result in
          continuation.resume(returning: result)
        }

        self.urlOpener(authorizeURL)
      } catch {
        continuation.resume(throwing: error)
      }
    }

    defer { server.stop() }

    /// Validate state to prevent CSRF attacks (RFC 6749 section 10.12).
    if let returnedState = result.state,
       returnedState != expectedState
    {
      throw OAuthFlowError.stateMismatch
    }

    return result
  }
}
