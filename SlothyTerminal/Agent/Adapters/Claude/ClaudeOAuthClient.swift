import Foundation

/// OAuth start payload for the Anthropic authorization flow.
struct ClaudeOAuthStart: Sendable {
  let authorizeURL: URL
  let verifier: String
  let state: String
}

/// OAuth client for Anthropic (Claude) subscriptions.
///
/// This is a skeleton — `exchange` and `refresh` will be implemented
/// in Phase 9 when the OAuth callback server is wired up.
/// The `startAuthorization` method generates a valid authorize URL.
final class ClaudeOAuthClient: OAuthClient, @unchecked Sendable {
  typealias StartPayload = ClaudeOAuthStart

  private let clientID: String
  private let redirectURI: String
  private let session: URLSession

  init(
    clientID: String,
    redirectURI: String,
    session: URLSession = .shared
  ) {
    self.clientID = clientID
    self.redirectURI = redirectURI
    self.session = session
  }

  func startAuthorization() async throws -> ClaudeOAuthStart {
    let verifier = UUID().uuidString.replacingOccurrences(of: "-", with: "")
    let state = UUID().uuidString

    var components = URLComponents(string: "https://claude.ai/oauth/authorize")!
    components.queryItems = [
      .init(name: "response_type", value: "code"),
      .init(name: "client_id", value: clientID),
      .init(name: "redirect_uri", value: redirectURI),
      .init(name: "scope", value: "org:create_api_key user:profile user:inference"),
      .init(name: "state", value: state),
    ]

    guard let url = components.url else {
      throw ClaudeOAuthError.invalidAuthorizeURL
    }

    return ClaudeOAuthStart(authorizeURL: url, verifier: verifier, state: state)
  }

  func exchange(code: String) async throws -> OAuthToken {
    throw ClaudeOAuthError.notImplemented("exchange")
  }

  func refresh(token: OAuthToken) async throws -> OAuthToken {
    throw ClaudeOAuthError.notImplemented("refresh")
  }
}

/// Errors specific to the Claude OAuth flow.
enum ClaudeOAuthError: Error, LocalizedError {
  case notImplemented(String)
  case invalidAuthorizeURL

  var errorDescription: String? {
    switch self {
    case .notImplemented(let method):
      return "ClaudeOAuthClient.\(method) is not yet implemented"

    case .invalidAuthorizeURL:
      return "Failed to construct Anthropic OAuth authorize URL"
    }
  }
}
