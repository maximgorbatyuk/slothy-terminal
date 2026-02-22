import Foundation

/// Represents a stored OAuth token set.
struct OAuthToken: Codable, Sendable, Equatable {
  let accessToken: String
  let refreshToken: String
  let expiresAt: Date
  let accountID: String?

  init(
    accessToken: String,
    refreshToken: String,
    expiresAt: Date,
    accountID: String?
  ) {
    self.accessToken = accessToken
    self.refreshToken = refreshToken
    self.expiresAt = expiresAt
    self.accountID = accountID
  }
}

/// Authentication mode for a provider — either a raw API key or OAuth tokens.
enum AuthMode: Codable, Sendable, Equatable {
  case apiKey(String)
  case oauth(OAuthToken)
}
