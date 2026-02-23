import Foundation

/// OAuth start payload for the Anthropic authorization flow.
struct ClaudeOAuthStart: Sendable {
  let authorizeURL: URL
  let verifier: String
  let state: String
}

/// OAuth client for Anthropic (Claude) Pro/Max subscriptions.
///
/// Supports:
/// - Browser-based PKCE (S256) authorization flow via `claude.ai`
/// - Token exchange with authorization code + verifier via `console.anthropic.com`
/// - Token refresh
///
/// Auth codes are returned in `code#state` format — the `#` delimiter
/// is stripped before exchange.
final class ClaudeOAuthClient: OAuthClient, @unchecked Sendable {
  typealias StartPayload = ClaudeOAuthStart

  /// Official Claude Code CLI OAuth client ID.
  static let defaultClientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

  /// Anthropic's hosted redirect URI for the CLI client.
  ///
  /// Anthropic does not support localhost redirect URIs for this client ID.
  /// Instead, the browser redirects to this hosted page which displays
  /// the authorization code for the user to copy.
  static let hostedRedirectURI = "https://console.anthropic.com/oauth/code/callback"

  private let clientID: String
  private let tokenEndpoint = URL(string: "https://console.anthropic.com/v1/oauth/token")!
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
    let verifier = CodexOAuthClient.randomURLSafe(length: 64)
    let challenge = CodexOAuthClient.pkceChallenge(verifier)
    let state = CodexOAuthClient.randomURLSafe(length: 32)

    var components = URLComponents(string: "https://claude.ai/oauth/authorize")!
    components.queryItems = [
      .init(name: "response_type", value: "code"),
      .init(name: "client_id", value: clientID),
      .init(name: "redirect_uri", value: redirectURI),
      .init(name: "scope", value: "org:create_api_key user:profile user:inference"),
      .init(name: "code_challenge", value: challenge),
      .init(name: "code_challenge_method", value: "S256"),
      .init(name: "state", value: state),
    ]

    guard let url = components.url else {
      throw ClaudeOAuthError.invalidAuthorizeURL
    }

    return ClaudeOAuthStart(authorizeURL: url, verifier: verifier, state: state)
  }

  /// Exchanges an authorization code + PKCE verifier for tokens.
  ///
  /// Anthropic returns auth codes as `code#state` — this method
  /// strips the `#state` suffix if present before exchanging.
  ///
  /// The token endpoint expects a **JSON** body (not form-urlencoded)
  /// with `Origin` / `Referer` headers pointing to `claude.ai`.
  func exchange(code: String, verifier: String) async throws -> OAuthToken {
    /// Strip `#state` suffix if the callback delivered the raw response.
    let cleanCode = code.split(separator: "#").first.map(String.init) ?? code

    var request = URLRequest(url: tokenEndpoint)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("https://claude.ai/", forHTTPHeaderField: "Referer")
    request.setValue("https://claude.ai", forHTTPHeaderField: "Origin")

    let body: [String: String] = [
      "grant_type": "authorization_code",
      "client_id": clientID,
      "code": cleanCode,
      "redirect_uri": redirectURI,
      "code_verifier": verifier,
    ]
    request.httpBody = try JSONSerialization.data(
      withJSONObject: body,
      options: [.sortedKeys]
    )

    let (data, response) = try await session.data(for: request)

    guard let http = response as? HTTPURLResponse,
          (200..<300).contains(http.statusCode)
    else {
      let body = String(data: data, encoding: .utf8) ?? ""
      throw ClaudeOAuthError.exchangeFailed(detail: body)
    }

    let payload = try JSONDecoder().decode(TokenResponse.self, from: data)

    guard let refreshToken = payload.refreshToken else {
      throw ClaudeOAuthError.exchangeFailed(detail: "Server did not return a refresh token")
    }

    return OAuthToken(
      accessToken: payload.accessToken,
      refreshToken: refreshToken,
      expiresAt: Date().addingTimeInterval(TimeInterval(payload.expiresIn ?? 28800)),
      accountID: nil
    )
  }

  func refresh(token: OAuthToken) async throws -> OAuthToken {
    var request = URLRequest(url: tokenEndpoint)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("https://claude.ai/", forHTTPHeaderField: "Referer")
    request.setValue("https://claude.ai", forHTTPHeaderField: "Origin")

    let body: [String: String] = [
      "grant_type": "refresh_token",
      "refresh_token": token.refreshToken,
      "client_id": clientID,
    ]
    request.httpBody = try JSONSerialization.data(
      withJSONObject: body,
      options: [.sortedKeys]
    )

    let (data, response) = try await session.data(for: request)

    guard let http = response as? HTTPURLResponse,
          (200..<300).contains(http.statusCode)
    else {
      let body = String(data: data, encoding: .utf8) ?? ""
      throw ClaudeOAuthError.refreshFailed(detail: body)
    }

    let payload = try JSONDecoder().decode(TokenResponse.self, from: data)
    return OAuthToken(
      accessToken: payload.accessToken,
      refreshToken: payload.refreshToken ?? token.refreshToken,
      expiresAt: Date().addingTimeInterval(TimeInterval(payload.expiresIn ?? 28800)),
      accountID: token.accountID
    )
  }

  // MARK: - Private types

  private struct TokenResponse: Codable {
    let accessToken: String
    /// Optional per RFC 6749 section 5.1 — refresh responses may omit this.
    let refreshToken: String?
    let expiresIn: Int?

    enum CodingKeys: String, CodingKey {
      case accessToken = "access_token"
      case refreshToken = "refresh_token"
      case expiresIn = "expires_in"
    }
  }

}

/// Errors specific to the Claude OAuth flow.
enum ClaudeOAuthError: Error, LocalizedError {
  case exchangeFailed(detail: String)
  case refreshFailed(detail: String)
  case invalidAuthorizeURL

  var errorDescription: String? {
    switch self {
    case .exchangeFailed(let detail):
      return "Claude OAuth token exchange failed: \(detail.prefix(200))"

    case .refreshFailed(let detail):
      return "Claude OAuth token refresh failed: \(detail.prefix(200))"

    case .invalidAuthorizeURL:
      return "Failed to construct Anthropic OAuth authorize URL"
    }
  }
}
