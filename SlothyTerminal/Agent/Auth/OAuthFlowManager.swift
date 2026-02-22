import Foundation
import OSLog

/// State of an OAuth authorization flow for a single provider.
enum OAuthFlowState: Sendable, Equatable {
  case idle
  case authorizing
  case exchanging
  case succeeded
  case failed(String)
}

/// Orchestrates the OAuth PKCE authorization flow for providers that support it.
///
/// Coordinates between the OAuth client, callback server, browser, and token store:
/// 1. Generates PKCE verifier + authorization URL via `CodexOAuthClient`
/// 2. Starts `OAuthCallbackServer` to receive the redirect
/// 3. Opens the browser for user authorization
/// 4. Exchanges the authorization code for tokens
/// 5. Persists tokens to `KeychainTokenStore`
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
    provider == .openAI
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
          flowState[provider] != .exchanging
    else {
      Logger.agent.info("OAuth flow already in progress for \(provider.rawValue)")
      return
    }

    flowState[provider] = .authorizing

    Task {
      await runCodexFlow()
    }
  }

  // MARK: - Private

  private func runCodexFlow() async {
    let server = OAuthCallbackServer(port: callbackPort)
    let redirectURI = server.redirectURI
    let client = CodexOAuthClient(
      clientID: CodexOAuthClient.defaultClientID,
      redirectURI: redirectURI
    )

    do {
      let start = try await client.startAuthorization()

      /// Start the callback server, open the browser, then wait for the code.
      let code = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
        do {
          try server.start { code in
            continuation.resume(returning: code)
          }

          /// Open browser after server is listening so redirect is caught.
          self.urlOpener(start.authorizeURL)
        } catch {
          continuation.resume(throwing: error)
        }
      }

      flowState[.openAI] = .exchanging

      let token = try await client.exchange(code: code, verifier: start.verifier)

      try await tokenStore.save(provider: .openAI, auth: .oauth(token))

      flowState[.openAI] = .succeeded
      Logger.agent.info("Codex OAuth flow completed successfully")

      /// Auto-reset to idle after a brief success display.
      try? await Task.sleep(for: .seconds(2))
      if flowState[.openAI] == .succeeded {
        flowState[.openAI] = .idle
      }

    } catch {
      server.stop()
      flowState[.openAI] = .failed(error.localizedDescription)
      Logger.agent.error("Codex OAuth flow failed: \(error.localizedDescription)")
    }
  }
}
