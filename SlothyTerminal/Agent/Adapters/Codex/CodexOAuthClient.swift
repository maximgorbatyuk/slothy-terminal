import CryptoKit
import Foundation

/// OAuth start payload for the OpenAI / Codex authorization flow.
struct CodexOAuthStart: Sendable {
  let authorizeURL: URL
  let state: String
  let verifier: String
}

/// OAuth client for OpenAI Codex (ChatGPT subscription + API key fallback).
///
/// Supports:
/// - Browser-based PKCE authorization flow
/// - Token exchange with authorization code + verifier
/// - Token refresh
/// - JWT account ID extraction from id_token / access_token
final class CodexOAuthClient: OAuthClient, @unchecked Sendable {
  typealias StartPayload = CodexOAuthStart

  /// Default OAuth client ID for the Codex CLI authorization flow.
  static let defaultClientID = "app_EMoamEEZ73f0CkXaXp7hrann"

  private let clientID: String
  private let issuer = URL(string: "https://auth.openai.com")!
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

  func startAuthorization() async throws -> CodexOAuthStart {
    let verifier = Self.randomURLSafe(length: 64)
    let challenge = Self.pkceChallenge(verifier)
    let state = Self.randomURLSafe(length: 32)

    var components = URLComponents(
      url: issuer.appendingPathComponent("oauth/authorize"),
      resolvingAgainstBaseURL: false
    )!
    components.queryItems = [
      .init(name: "response_type", value: "code"),
      .init(name: "client_id", value: clientID),
      .init(name: "redirect_uri", value: redirectURI),
      .init(name: "scope", value: "openid profile email offline_access"),
      .init(name: "code_challenge", value: challenge),
      .init(name: "code_challenge_method", value: "S256"),
      .init(name: "state", value: state),
      .init(name: "id_token_add_organizations", value: "true"),
      .init(name: "codex_cli_simplified_flow", value: "true"),
    ]

    guard let url = components.url else {
      throw CodexOAuthError.invalidAuthorizeURL
    }

    return CodexOAuthStart(authorizeURL: url, state: state, verifier: verifier)
  }

  /// Exchanges an authorization code + PKCE verifier for tokens.
  func exchange(code: String, verifier: String) async throws -> OAuthToken {
    var request = URLRequest(url: issuer.appendingPathComponent("oauth/token"))
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

    let body = [
      "grant_type": "authorization_code",
      "code": code,
      "redirect_uri": redirectURI,
      "client_id": clientID,
      "code_verifier": verifier,
    ]
    request.httpBody = Self.formURLEncoded(body).data(using: .utf8)

    let (data, response) = try await session.data(for: request)

    guard let http = response as? HTTPURLResponse,
          (200..<300).contains(http.statusCode)
    else {
      throw CodexOAuthError.exchangeFailed
    }

    let payload = try JSONDecoder().decode(TokenResponse.self, from: data)

    guard let refreshToken = payload.refreshToken else {
      throw CodexOAuthError.exchangeFailed
    }

    return OAuthToken(
      accessToken: payload.accessToken,
      refreshToken: refreshToken,
      expiresAt: Date().addingTimeInterval(TimeInterval(payload.expiresIn ?? 3600)),
      accountID: Self.extractAccountID(
        idToken: payload.idToken,
        accessToken: payload.accessToken
      )
    )
  }

  func refresh(token: OAuthToken) async throws -> OAuthToken {
    var request = URLRequest(url: issuer.appendingPathComponent("oauth/token"))
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.httpBody = Self.formURLEncoded([
      "grant_type": "refresh_token",
      "refresh_token": token.refreshToken,
      "client_id": clientID,
    ]).data(using: .utf8)

    let (data, response) = try await session.data(for: request)

    guard let http = response as? HTTPURLResponse,
          (200..<300).contains(http.statusCode)
    else {
      throw CodexOAuthError.refreshFailed
    }

    let payload = try JSONDecoder().decode(TokenResponse.self, from: data)
    return OAuthToken(
      accessToken: payload.accessToken,
      refreshToken: payload.refreshToken ?? token.refreshToken,
      expiresAt: Date().addingTimeInterval(TimeInterval(payload.expiresIn ?? 3600)),
      accountID: Self.extractAccountID(
        idToken: payload.idToken,
        accessToken: payload.accessToken
      ) ?? token.accountID
    )
  }

  // MARK: - Private types

  private struct TokenResponse: Codable {
    let idToken: String?
    let accessToken: String
    /// Optional per RFC 6749 section 5.1 — refresh responses may omit this.
    let refreshToken: String?
    let expiresIn: Int?

    enum CodingKeys: String, CodingKey {
      case idToken = "id_token"
      case accessToken = "access_token"
      case refreshToken = "refresh_token"
      case expiresIn = "expires_in"
    }
  }

  // MARK: - PKCE

  static func pkceChallenge(_ verifier: String) -> String {
    let digest = SHA256.hash(data: Data(verifier.utf8))
    return Data(digest).base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }

  static func randomURLSafe(length: Int) -> String {
    let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
    var out = ""
    out.reserveCapacity(length)
    for _ in 0..<length {
      out.append(alphabet.randomElement()!)
    }
    return out
  }

  // MARK: - JWT account ID extraction

  static func extractAccountID(idToken: String?, accessToken: String) -> String? {
    if let idToken,
       let claims = decodeJWTPayload(idToken),
       let id = accountID(from: claims)
    {
      return id
    }

    if let claims = decodeJWTPayload(accessToken),
       let id = accountID(from: claims)
    {
      return id
    }

    return nil
  }

  static func decodeJWTPayload(_ token: String) -> [String: Any]? {
    let parts = token.split(separator: ".")

    guard parts.count == 3 else {
      return nil
    }

    var payload = String(parts[1])
      .replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")

    while payload.count % 4 != 0 {
      payload += "="
    }

    guard let data = Data(base64Encoded: payload) else {
      return nil
    }

    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
  }

  private static func accountID(from claims: [String: Any]) -> String? {
    if let root = claims["chatgpt_account_id"] as? String {
      return root
    }

    if let nested = (claims["https://api.openai.com/auth"] as? [String: Any])?["chatgpt_account_id"] as? String {
      return nested
    }

    if let org = (claims["organizations"] as? [[String: Any]])?.first?["id"] as? String {
      return org
    }

    return nil
  }

  /// Characters allowed unescaped in `application/x-www-form-urlencoded`.
  /// Only alphanumerics and `-._~` — notably excludes `+`, `=`, `&`, `#`.
  private static let formAllowed: CharacterSet = {
    var set = CharacterSet.alphanumerics
    set.insert(charactersIn: "-._~")
    return set
  }()

  private static func formURLEncoded(_ map: [String: String]) -> String {
    map.sorted(by: { $0.key < $1.key }).map { key, value in
      let k = key.addingPercentEncoding(withAllowedCharacters: formAllowed) ?? key
      let v = value.addingPercentEncoding(withAllowedCharacters: formAllowed) ?? value
      return "\(k)=\(v)"
    }.joined(separator: "&")
  }
}

/// Errors specific to the Codex OAuth flow.
enum CodexOAuthError: Error, LocalizedError {
  case exchangeFailed
  case refreshFailed
  case invalidAuthorizeURL

  var errorDescription: String? {
    switch self {
    case .exchangeFailed:
      return "Codex OAuth token exchange failed"

    case .refreshFailed:
      return "Codex OAuth token refresh failed"

    case .invalidAuthorizeURL:
      return "Failed to construct Codex OAuth authorize URL"
    }
  }
}
