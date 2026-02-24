import CryptoKit
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
/// Auth codes are returned in `code#state` format — the token exchange
/// must include both parts: `code` (before `#`) and `state` (after `#`).
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
    let verifier = Self.randomBase64URLVerifier()
    let challenge = CodexOAuthClient.pkceChallenge(verifier)

    /// Anthropic expects `state` to equal the PKCE verifier. The callback
    /// page returns `code#state` — on exchange the server validates that
    /// the `state` portion matches the original verifier.
    let state = verifier

    var components = URLComponents(string: "https://claude.ai/oauth/authorize")!
    components.queryItems = [
      .init(name: "code", value: "true"),
      .init(name: "client_id", value: clientID),
      .init(name: "response_type", value: "code"),
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
  /// Anthropic returns auth codes as `code#state` — both parts must be
  /// included in the token exchange request body.
  func exchange(code: String, verifier: String) async throws -> OAuthToken {
    let splits = code.split(separator: "#", maxSplits: 1)
    let cleanCode = String(splits[0])
    let state = splits.count > 1 ? String(splits[1]) : nil

    var request = URLRequest(url: tokenEndpoint)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    var body: [String: String] = [
      "grant_type": "authorization_code",
      "client_id": clientID,
      "code": cleanCode,
      "redirect_uri": redirectURI,
      "code_verifier": verifier,
    ]
    if let state {
      body["state"] = state
    }
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

  // MARK: - PKCE verifier

  /// Generates a PKCE code verifier matching the format used by
  /// `@openauthjs/openauth`: 64 cryptographically random bytes,
  /// base64url-encoded (no padding).
  ///
  /// This differs from `CodexOAuthClient.randomURLSafe(length:)` which
  /// picks random characters from the RFC 7636 unreserved set. Anthropic's
  /// OAuth server expects the base64url-of-random-bytes format.
  static func randomBase64URLVerifier(byteCount: Int = 64) -> String {
    var bytes = [UInt8](repeating: 0, count: byteCount)
    let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)

    guard status == errSecSuccess else {
      preconditionFailure("SecRandomCopyBytes failed with status \(status)")
    }

    return Data(bytes)
      .base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
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
