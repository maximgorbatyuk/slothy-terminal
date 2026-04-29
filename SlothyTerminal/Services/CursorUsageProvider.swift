import Foundation
import OSLog

/// Fetches Cursor usage from the undocumented `cursor.com/api/usage` endpoint.
///
/// Auth model: user pastes their Cursor session JWT (the second half of the
/// `WorkosCursorSessionToken` cookie set by cursor.com) into Settings, where
/// it's stored in the macOS Keychain via `UsageKeychainStore`. The JWT's
/// `sub` claim supplies the user ID required by the endpoint.
enum CursorUsageProvider {
  private static let usageEndpoint = "https://www.cursor.com/api/usage"
  private static let requestTimeout: TimeInterval = 10

  /// JWTs are base64url segments separated by dots — `[A-Za-z0-9_.-]`.
  /// The userID `sub` claim is opaque but in practice fits the same set;
  /// we restrict both to this charset so they can be safely placed in the
  /// `Cookie` header verbatim without percent-encoding (RFC 6265 cookie-octet
  /// range; servers receive cookies un-decoded).
  private static let cookieSafeCharacters: CharacterSet = {
    var set = CharacterSet.alphanumerics
    set.insert(charactersIn: "-._")
    return set
  }()

  /// Fetches a usage snapshot using the provided session JWT.
  static func fetchUsage(jwt: String) async throws -> UsageSnapshot {
    let trimmed = jwt.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !trimmed.isEmpty else {
      throw UsageFetchError.noCredentials
    }

    guard isHeaderSafe(trimmed) else {
      Logger.usage.error("[cursor] JWT contains characters not allowed in a Cookie header")
      throw UsageFetchError.invalidCredentials
    }

    guard let userID = decodeUserID(fromJWT: trimmed) else {
      Logger.usage.error("[cursor] Failed to decode user ID from JWT")
      throw UsageFetchError.invalidCredentials
    }

    guard isHeaderSafe(userID) else {
      Logger.usage.error("[cursor] JWT sub claim contains characters not allowed in a Cookie header")
      throw UsageFetchError.invalidCredentials
    }

    let (statusCode, data) = try await performRequest(jwt: trimmed, userID: userID)

    if statusCode == 401 {
      Logger.usage.warning("[cursor] Got 401 — JWT expired or revoked")
      throw UsageFetchError.tokenExpired
    }

    guard statusCode == 200 else {
      Logger.usage.error("[cursor] Usage request failed: HTTP \(statusCode)")
      throw UsageFetchError.httpError(statusCode)
    }

    return parseUsageResponse(data: data, userID: userID)
  }

  // MARK: - HTTP

  private static func performRequest(
    jwt: String,
    userID: String
  ) async throws -> (statusCode: Int, data: Data) {
    guard var components = URLComponents(string: usageEndpoint) else {
      throw UsageFetchError.invalidURL
    }

    components.queryItems = [URLQueryItem(name: "user", value: userID)]

    guard let url = components.url else {
      throw UsageFetchError.invalidURL
    }

    var request = URLRequest(url: url)
    request.timeoutInterval = requestTimeout
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("SlothyTerminal", forHTTPHeaderField: "User-Agent")
    /// Cookie values are passed verbatim by HTTP intermediaries — both
    /// `userID` and `jwt` are validated against `cookieSafeCharacters` by
    /// the caller, so no percent-encoding is needed here.
    request.setValue(
      "WorkosCursorSessionToken=\(userID)::\(jwt)",
      forHTTPHeaderField: "Cookie"
    )

    Logger.usage.info("[cursor] Requesting usage from cursor.com")
    let (data, response) = try await URLSession.shared.data(for: request)

    guard let http = response as? HTTPURLResponse else {
      throw UsageFetchError.invalidResponse
    }

    return (http.statusCode, data)
  }

  /// Returns true if the value contains only characters allowed in an HTTP
  /// header without quoting/encoding — i.e., no whitespace, control characters,
  /// or punctuation that would break Cookie-header parsing.
  nonisolated static func isHeaderSafe(_ value: String) -> Bool {
    !value.isEmpty
      && value.unicodeScalars.allSatisfy { cookieSafeCharacters.contains($0) }
  }

  // MARK: - JWT decoding

  /// Decodes the `sub` claim from a JWT without verifying its signature.
  /// Pure Foundation — no external dependency.
  static func decodeUserID(fromJWT jwt: String) -> String? {
    let segments = jwt.split(separator: ".")

    guard segments.count >= 2 else {
      return nil
    }

    guard let payload = base64URLDecode(String(segments[1])) else {
      return nil
    }

    guard let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
      return nil
    }

    return json["sub"] as? String
  }

  private static func base64URLDecode(_ value: String) -> Data? {
    var s = value
      .replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")

    let remainder = s.count % 4
    if remainder > 0 {
      s.append(String(repeating: "=", count: 4 - remainder))
    }

    return Data(base64Encoded: s)
  }

  // MARK: - Response parsing

  /// Parses the Cursor usage response.
  ///
  /// Shape (top-level keys):
  /// ```
  /// {
  ///   "startOfMonth": "2026-04-01T00:00:00.000Z",
  ///   "gpt-4":            { "numRequests": 12, "maxRequestUsage": 500 },
  ///   "claude-3.5-sonnet": { "numRequests": 0,  "maxRequestUsage": null },
  ///   ...
  /// }
  /// ```
  /// Some deployments may nest the per-model entries under a `modelUsages`
  /// object — both shapes are handled.
  nonisolated static func parseUsageResponse(
    data: Data,
    userID: String
  ) -> UsageSnapshot {
    let now = Date()

    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      Logger.usage.error("[cursor] Failed to parse usage response JSON")
      return failureSnapshot(message: "Parse error", userID: userID, fetchedAt: now)
    }

    let startOfMonth = json["startOfMonth"] as? String

    let modelEntries = extractModelEntries(from: json)

    /// A valid response always carries `startOfMonth`. An empty modelUsages
    /// list is normal for fresh accounts, but with NO `startOfMonth` either,
    /// the schema has changed and the snapshot would silently look healthy.
    /// Surface that as a parse failure so the user/operator notices.
    if startOfMonth == nil && modelEntries.isEmpty {
      Logger.usage.error("[cursor] Response missing both startOfMonth and model entries — schema changed?")
      return failureSnapshot(message: "Parse error", userID: userID, fetchedAt: now)
    }

    var totalRequests = 0
    var maxLimit: Int? = nil

    for (_, entry) in modelEntries {
      if let used = entry["numRequests"] as? Int {
        totalRequests += used
      }

      if let limit = entry["maxRequestUsage"] as? Int {
        if let current = maxLimit {
          maxLimit = max(current, limit)
        } else {
          maxLimit = limit
        }
      }
    }

    let resetLabel = startOfMonth.flatMap { formatMonthlyReset(startOfMonthISO: $0) }
    let usedString = "\(totalRequests)"
    let limitString = maxLimit.map { "\($0)" }
    let remainingString = maxLimit.map { "\(max(0, $0 - totalRequests))" }
    let percentUsed: Double? = maxLimit.flatMap { limit in
      limit > 0 ? min(100, Double(totalRequests) / Double(limit) * 100) : nil
    }

    var metrics: [UsageMetric] = []

    let requestsValue: String
    if let limitString {
      requestsValue = "\(totalRequests) / \(limitString)"
    } else {
      requestsValue = "\(totalRequests)"
    }

    let requestsStyle: UsageMetricStyle
    if let pct = percentUsed {
      requestsStyle = pct >= 90 ? .warning : pct >= 70 ? .cost : .normal
    } else {
      requestsStyle = .normal
    }

    metrics.append(UsageMetric(
      label: "Requests (monthly)",
      value: requestsValue,
      style: requestsStyle
    ))

    if let resetLabel {
      metrics.append(UsageMetric(
        label: "Resets",
        value: resetLabel,
        style: .normal
      ))
    }

    return UsageSnapshot(
      provider: .cursor,
      sourceKind: .apiKey,
      sourceLabel: "Session token",
      account: userID,
      quotaWindow: UsageQuotaWindow(name: "Monthly", resetLabel: resetLabel),
      used: usedString,
      limit: limitString,
      remaining: remainingString,
      percentUsed: percentUsed,
      metrics: metrics,
      fetchedAt: now
    )
  }

  /// Returns per-model entries from either the flat or nested response shape.
  nonisolated private static func extractModelEntries(
    from json: [String: Any]
  ) -> [(String, [String: Any])] {
    if let nested = json["modelUsages"] as? [String: Any] {
      return nested.compactMap { key, value in
        guard let dict = value as? [String: Any] else {
          return nil
        }
        return (key, dict)
      }
    }

    return json.compactMap { key, value in
      guard key != "startOfMonth",
            let dict = value as? [String: Any]
      else {
        return nil
      }
      return (key, dict)
    }
  }

  nonisolated private static func formatMonthlyReset(startOfMonthISO: String) -> String? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    var startDate = formatter.date(from: startOfMonthISO)
    if startDate == nil {
      formatter.formatOptions = [.withInternetDateTime]
      startDate = formatter.date(from: startOfMonthISO)
    }

    guard let start = startDate else {
      return nil
    }

    guard let resetDate = Calendar(identifier: .gregorian).date(
      byAdding: .month,
      value: 1,
      to: start
    ) else {
      return nil
    }

    let display = DateFormatter()
    display.dateStyle = .medium
    display.timeStyle = .none
    return display.string(from: resetDate)
  }

  nonisolated private static func failureSnapshot(
    message: String,
    userID: String,
    fetchedAt: Date
  ) -> UsageSnapshot {
    UsageSnapshot(
      provider: .cursor,
      sourceKind: .apiKey,
      sourceLabel: "Session token",
      account: userID,
      quotaWindow: nil,
      used: message,
      limit: nil,
      remaining: nil,
      percentUsed: nil,
      metrics: [],
      fetchedAt: fetchedAt
    )
  }
}
