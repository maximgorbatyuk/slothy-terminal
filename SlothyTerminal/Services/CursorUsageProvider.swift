import Foundation
import OSLog
import SQLite3

/// Fetches Cursor usage from the dashboard backend that powers
/// `cursor.com/dashboard?tab=usage`. The legacy `cursor.com/api/usage`
/// endpoint reports zeros for accounts on the token-based billing model
/// (Pro/Pro+/Ultra) and is not used here.
///
/// Two endpoints, both authenticated with the same `WorkosCursorSessionToken`
/// cookie that the web dashboard uses:
///   - `POST /api/dashboard/get-filtered-usage-events` — per-event detail
///     (model, kind, tokenUsage, usageBasedCosts). Paginated.
///   - `POST /api/dashboard/get-current-period-usage` — aggregated $ spent
///     vs. plan limit for the current billing period. Best-effort: the
///     dashboard sometimes 4xxs this endpoint, in which case we still
///     produce a snapshot from the events alone.
///
/// Auth model (in priority order):
///   1. Auto-detect — read the JWT directly from Cursor.app's SQLite state
///      database at `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`,
///      row `cursorAuth/accessToken`. Refreshes whenever Cursor rotates the
///      token.
///   2. Manual paste — user pastes the JWT (the second half of the
///      `WorkosCursorSessionToken` cookie) into Settings; stored in the
///      macOS Keychain via `UsageKeychainStore`.
enum CursorUsageProvider {
  private static let usageEventsEndpoint = "https://cursor.com/api/dashboard/get-filtered-usage-events"
  private static let currentPeriodEndpoint = "https://cursor.com/api/dashboard/get-current-period-usage"
  private static let dashboardOrigin = "https://cursor.com"
  private static let dashboardReferer = "https://cursor.com/dashboard?tab=usage"
  private static let requestTimeout: TimeInterval = 15
  private static let eventsPageSize = 100
  private static let eventsPageCap = 50

  private static let userAgent: String = {
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
    return "SlothyTerminal/\(version)"
  }()

  /// Default location of Cursor.app's state database.
  static let defaultStateDBPath: String = {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return "\(home)/Library/Application Support/Cursor/User/globalStorage/state.vscdb"
  }()

  /// RFC 3986 unreserved set — used to percent-encode the userID and JWT
  /// halves of the `WorkosCursorSessionToken` cookie. The Cursor server
  /// expects URL-decoded values, so e.g. a Google OAuth `sub` like
  /// `google-oauth2|12345` round-trips correctly via percent-encoding.
  private static let cookieComponentAllowed: CharacterSet = {
    var set = CharacterSet.alphanumerics
    set.insert(charactersIn: "-._~")
    return set
  }()

  /// Fetches a usage snapshot using the provided session JWT. The source kind
  /// and label are stamped onto the resulting snapshot so the popover badge
  /// reflects whether this came from the Cursor app or a manual paste.
  static func fetchUsage(
    jwt: String,
    sourceKind: UsageSourceKind = .apiKey,
    sourceLabel: String = "Session token"
  ) async throws -> UsageSnapshot {
    let trimmed = jwt.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !trimmed.isEmpty else {
      Logger.usage.error("[cursor] fetchUsage called with empty JWT (sourceKind=\(sourceKind.rawValue), sourceLabel=\(sourceLabel))")
      throw UsageFetchError.noCredentials
    }

    let segmentCount = trimmed.split(separator: ".").count
    Logger.usage.info(
      "[cursor] fetchUsage entry — sourceKind=\(sourceKind.rawValue) sourceLabel=\(sourceLabel) jwtLength=\(trimmed.count) jwtSegments=\(segmentCount) jwtSample=\(redact(trimmed))"
    )

    guard let userID = decodeUserID(fromJWT: trimmed) else {
      Logger.usage.error(
        "[cursor] Failed to decode user ID from JWT — segments=\(segmentCount) sample=\(redact(trimmed)). See preceding [cursor] logs for the specific decode step that failed."
      )
      throw UsageFetchError.invalidCredentials
    }

    Logger.usage.info("[cursor] Decoded userID from JWT — userID=\(redact(userID)) length=\(userID.count)")

    let cookie = buildSessionCookie(userID: userID, jwt: trimmed)
    let (start, end) = currentBillingPeriod()

    let events = try await fetchAllEvents(cookie: cookie, start: start, end: end)
    let periodTotals = try await fetchCurrentPeriodTotals(cookie: cookie)

    return buildSnapshot(
      events: events,
      periodTotals: periodTotals,
      periodStart: start,
      sourceKind: sourceKind,
      sourceLabel: sourceLabel
    )
  }

  // MARK: - HTTP

  /// Builds the `WorkosCursorSessionToken` cookie value. Both halves are
  /// percent-encoded (RFC 3986 unreserved) and joined with `%3A%3A` — the
  /// Cursor server URL-decodes before parsing, so OAuth `sub` claims like
  /// `google-oauth2|12345` survive the Cookie header intact.
  private static func buildSessionCookie(userID: String, jwt: String) -> String {
    let encodedUserID = percentEncodeCookieComponent(userID)
    let encodedJWT = percentEncodeCookieComponent(jwt)
    return "WorkosCursorSessionToken=\(encodedUserID)%3A%3A\(encodedJWT)"
  }

  private static func dashboardRequest(url: URL, cookie: String, body: Data) -> URLRequest {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = requestTimeout
    request.httpBody = body
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
    request.setValue(dashboardOrigin, forHTTPHeaderField: "Origin")
    request.setValue(dashboardReferer, forHTTPHeaderField: "Referer")
    request.setValue(cookie, forHTTPHeaderField: "Cookie")
    return request
  }

  /// Fetches every page of `get-filtered-usage-events` for the given window.
  /// Stops when a page returns fewer than `eventsPageSize` events, or when
  /// `eventsPageCap` is hit (a safety cap against runaway loops).
  /// 401 maps to `tokenExpired`; other non-2xx maps to `httpError`.
  private static func fetchAllEvents(
    cookie: String,
    start: Date,
    end: Date
  ) async throws -> [UsageEvent] {
    guard let url = URL(string: usageEventsEndpoint) else {
      throw UsageFetchError.invalidURL
    }

    let startMS = Int64(start.timeIntervalSince1970 * 1000)
    let endMS = Int64(end.timeIntervalSince1970 * 1000)
    var aggregated: [UsageEvent] = []

    for page in 1...eventsPageCap {
      let payload: [String: Any] = [
        "teamId": 0,
        "startDate": String(startMS),
        "endDate": String(endMS),
        "page": page,
        "pageSize": eventsPageSize,
      ]
      let body = try JSONSerialization.data(withJSONObject: payload)
      let request = dashboardRequest(url: url, cookie: cookie, body: body)

      Logger.usage.info("[cursor] events request page=\(page) start=\(startMS) end=\(endMS)")
      let (data, response) = try await URLSession.shared.data(for: request)

      ProviderResponseStore.record(
        provider: .cursor,
        endpoint: "events",
        url: url.absoluteString,
        statusCode: (response as? HTTPURLResponse)?.statusCode,
        body: data
      )

      guard let http = response as? HTTPURLResponse else {
        throw UsageFetchError.invalidResponse
      }

      switch http.statusCode {
      case 200:
        break

      case 401:
        Logger.usage.warning("[cursor] events 401 — token expired or revoked. snippet=\(bodySnippet(data))")
        throw UsageFetchError.tokenExpired

      case 429:
        Logger.usage.warning("[cursor] events 429 — rate limited. Stopping pagination at page \(page).")
        throw UsageFetchError.httpError(429)

      default:
        Logger.usage.error("[cursor] events HTTP \(http.statusCode). snippet=\(bodySnippet(data))")
        throw UsageFetchError.httpError(http.statusCode)
      }

      let pageEvents = parseEventsPage(data: data)
      aggregated.append(contentsOf: pageEvents)

      Logger.usage.info("[cursor] events page=\(page) returned=\(pageEvents.count) cumulative=\(aggregated.count)")

      if pageEvents.count < eventsPageSize {
        break
      }
    }

    return aggregated
  }

  /// Best-effort fetch of `get-current-period-usage` (plan totals).
  /// Returns nil on any non-2xx — the snapshot will fall back to event sums.
  /// 401 still throws so the caller surfaces a re-login prompt.
  private static func fetchCurrentPeriodTotals(cookie: String) async throws -> CurrentPeriodTotals? {
    guard let url = URL(string: currentPeriodEndpoint) else {
      return nil
    }

    let body = Data("{}".utf8)
    let request = dashboardRequest(url: url, cookie: cookie, body: body)

    Logger.usage.info("[cursor] current-period request")
    let (data, response): (Data, URLResponse)
    do {
      (data, response) = try await URLSession.shared.data(for: request)
    } catch {
      Logger.usage.warning("[cursor] current-period transport error: \(error.localizedDescription)")
      ProviderResponseStore.record(
        provider: .cursor,
        endpoint: "current-period",
        url: url.absoluteString,
        statusCode: nil,
        body: Data(),
        error: error.localizedDescription
      )
      return nil
    }

    ProviderResponseStore.record(
      provider: .cursor,
      endpoint: "current-period",
      url: url.absoluteString,
      statusCode: (response as? HTTPURLResponse)?.statusCode,
      body: data
    )

    guard let http = response as? HTTPURLResponse else {
      return nil
    }

    if http.statusCode == 401 {
      Logger.usage.warning("[cursor] current-period 401 — token expired or revoked. snippet=\(bodySnippet(data))")
      throw UsageFetchError.tokenExpired
    }

    guard http.statusCode == 200 else {
      Logger.usage.info("[cursor] current-period HTTP \(http.statusCode) — proceeding without plan totals. snippet=\(bodySnippet(data))")
      return nil
    }

    return parseCurrentPeriod(data: data)
  }

  // MARK: - Diagnostic helpers

  /// Returns a redacted preview of a sensitive string for logs.
  /// Shows length and first/last 4 characters so format changes are visible
  /// without leaking the full secret.
  nonisolated private static func redact(_ value: String) -> String {
    if value.count <= 8 {
      return "<\(value.count) chars>"
    }
    let prefix = value.prefix(4)
    let suffix = value.suffix(4)
    return "\(prefix)…\(suffix)(\(value.count) chars)"
  }

  /// Returns up to 512 bytes of the response body as a UTF-8 string for
  /// diagnostic logging. Falls back to a hex-style summary for binary data.
  nonisolated private static func bodySnippet(_ data: Data) -> String {
    let limit = 512
    let slice = data.prefix(limit)

    if let text = String(data: slice, encoding: .utf8) {
      let suffix = data.count > limit ? "… (\(data.count) bytes total)" : ""
      return text.replacingOccurrences(of: "\n", with: " ") + suffix
    }

    return "<non-UTF8 body, \(data.count) bytes>"
  }

  nonisolated private static func percentEncodeCookieComponent(_ value: String) -> String {
    value.addingPercentEncoding(withAllowedCharacters: cookieComponentAllowed) ?? value
  }

  // MARK: - JWT decoding

  /// Decodes the `sub` claim from a JWT without verifying its signature.
  /// Pure Foundation — no external dependency.
  static func decodeUserID(fromJWT jwt: String) -> String? {
    let segments = jwt.split(separator: ".")

    guard segments.count >= 2 else {
      Logger.usage.error(
        "[cursor] decodeUserID: JWT has only \(segments.count) dot-separated segment(s), expected 3 — token may not be a JWT (sample=\(redact(jwt)))"
      )
      return nil
    }

    guard let payload = base64URLDecode(String(segments[1])) else {
      Logger.usage.error(
        "[cursor] decodeUserID: base64URL decode of payload segment failed — segmentLength=\(segments[1].count)"
      )
      return nil
    }

    guard let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
      let preview = String(data: payload.prefix(256), encoding: .utf8) ?? "<non-UTF8>"
      Logger.usage.error(
        "[cursor] decodeUserID: JWT payload is not a JSON object — payloadBytes=\(payload.count) preview=\(preview)"
      )
      return nil
    }

    guard let sub = json["sub"] as? String else {
      let keys = json.keys.sorted().joined(separator: ", ")
      Logger.usage.error(
        "[cursor] decodeUserID: JWT payload missing string `sub` claim — keys=[\(keys)]"
      )
      return nil
    }

    return sub
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

  /// Parsed event from `get-filtered-usage-events`. Field names match the
  /// dashboard payload — we only keep what we display or aggregate.
  struct UsageEvent: Equatable {
    let model: String
    /// Raw `kind` string from the API. Examples: `INCLUDED_IN_PRO`,
    /// `USAGE_BASED`, `ERRORED_NOT_CHARGED`, `INCLUDED_IN_ULTRA`.
    let kind: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheWriteTokens: Int
    /// Dollar value reported for this event. Present even on `INCLUDED_IN_*`
    /// rows (where it represents the would-be cost — useful for a "value
    /// included" display). May be 0 for free/error rows.
    let cost: Double
    /// Cents charged to the user for this event, from `chargedCents`.
    /// Authoritative source for the per-event dollar amount shown in the
    /// "Recent usage" tooltip section (vs. `cost`, which is the legacy
    /// `usageBasedCosts` field — often `"-"` on Ultra plans).
    let chargedDollars: Double
    /// Event timestamp, parsed from the `timestamp` field (milliseconds
    /// since epoch, serialized as a string by the dashboard API).
    let timestamp: Date
  }

  /// Aggregated plan totals from `get-current-period-usage`. Field shape
  /// varies across plans; we extract both the legacy flat shape and the
  /// current `planUsage`-nested shape.
  struct CurrentPeriodTotals: Equatable {
    /// Dollars spent in the current period (usage-based portion).
    let spent: Double?
    /// Plan's included credit allowance in dollars (e.g. $20 Pro, $400 Ultra).
    let includedDollars: Double?
    /// Hard usage-based cap in dollars, if the user has set one.
    let hardLimitDollars: Double?
    /// `planUsage.apiPercentUsed` — already a percentage (e.g. 5.318 = 5.32%).
    let apiPercentUsed: Double?
    /// `planUsage.autoPercentUsed` — already a percentage.
    let autoPercentUsed: Double?
    /// `planUsage.totalSpend` in dollars (raw API value is cents — divided by 100).
    let totalSpendDollars: Double?
    /// `planUsage.limit` in dollars (raw API value is cents — e.g. 40000 = $400 Ultra).
    let limitDollars: Double?
    /// `billingCycleEnd` as Date — period reset moment.
    let billingCycleEnd: Date?
  }

  nonisolated static func parseEventsPage(data: Data) -> [UsageEvent] {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      Logger.usage.error("[cursor] events: non-JSON response — snippet=\(bodySnippet(data))")
      return []
    }

    guard let raw = root["usageEventsDisplay"] as? [[String: Any]] else {
      let keys = root.keys.sorted().joined(separator: ", ")
      Logger.usage.error("[cursor] events: missing usageEventsDisplay — keys=[\(keys)]")
      return []
    }

    return raw.map { event in
      let tokenUsage = event["tokenUsage"] as? [String: Any] ?? [:]
      let chargedCents = doubleAny(event["chargedCents"]) ?? 0
      return UsageEvent(
        model: (event["model"] as? String) ?? "Unknown",
        kind: (event["kind"] as? String) ?? "Unknown",
        inputTokens: intField(tokenUsage["inputTokens"]),
        outputTokens: intField(tokenUsage["outputTokens"]),
        cacheReadTokens: intField(tokenUsage["cacheReadTokens"]),
        cacheWriteTokens: intField(tokenUsage["cacheWriteTokens"]),
        cost: parseCostField(event["usageBasedCosts"]),
        chargedDollars: chargedCents / 100,
        timestamp: parseEpochMSField(event["timestamp"]) ?? .distantPast
      )
    }
  }

  /// Parses a number that the API may serialize as a number or a numeric
  /// string. Returns nil if neither matches.
  nonisolated private static func doubleAny(_ value: Any?) -> Double? {
    if let d = value as? Double { return d }
    if let i = value as? Int { return Double(i) }
    if let s = value as? String, let d = Double(s) { return d }
    return nil
  }

  /// Parses an epoch-milliseconds timestamp serialized as a string or number.
  nonisolated private static func parseEpochMSField(_ value: Any?) -> Date? {
    guard let ms = doubleAny(value) else {
      return nil
    }
    return Date(timeIntervalSince1970: ms / 1000)
  }

  nonisolated static func parseCurrentPeriod(data: Data) -> CurrentPeriodTotals? {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      Logger.usage.error("[cursor] current-period: non-JSON — snippet=\(bodySnippet(data))")
      return nil
    }

    Logger.usage.info("[cursor] current-period keys=[\(root.keys.sorted().joined(separator: ", "))]")

    let planUsage = root["planUsage"] as? [String: Any] ?? [:]

    /// Cursor reports `planUsage.totalSpend`, `limit`, and `includedSpend` in
    /// cents — e.g. `limit: 40000` is $400 (Ultra plan), not $40,000. Divide
    /// by 100 to get dollars consistent with the rest of the snapshot.
    let totalSpendDollars = doubleField(planUsage, keys: ["totalSpend"]).map { $0 / 100 }
    let limitDollars = doubleField(planUsage, keys: ["limit"]).map { $0 / 100 }
    let includedDollarsFromPlan = doubleField(planUsage, keys: ["includedSpend"]).map { $0 / 100 }

    return CurrentPeriodTotals(
      spent: totalSpendDollars
        ?? doubleField(root, keys: ["totalCents", "currentSpendCents"]).map { $0 / 100 }
        ?? doubleField(root, keys: ["totalCost", "totalSpend", "currentSpend", "spent"]),
      includedDollars: includedDollarsFromPlan
        ?? doubleField(root, keys: ["includedCreditCents", "includedAmountCents"]).map { $0 / 100 }
        ?? doubleField(root, keys: ["includedCredit", "includedAmount", "planCredit"]),
      hardLimitDollars: doubleField(root, keys: ["hardLimitCents"]).map { $0 / 100 }
        ?? doubleField(root, keys: ["hardLimit", "hardLimitDollars"]),
      apiPercentUsed: doubleField(planUsage, keys: ["apiPercentUsed"]),
      autoPercentUsed: doubleField(planUsage, keys: ["autoPercentUsed"]),
      totalSpendDollars: totalSpendDollars,
      limitDollars: limitDollars,
      billingCycleEnd: doubleField(root, keys: ["billingCycleEnd"]).map {
        Date(timeIntervalSince1970: $0 / 1000)
      }
    )
  }

  nonisolated private static func intField(_ value: Any?) -> Int {
    if let i = value as? Int { return i }
    if let d = value as? Double { return Int(d) }
    if let s = value as? String, let i = Int(s) { return i }
    return 0
  }

  nonisolated private static func doubleField(
    _ root: [String: Any],
    keys: [String]
  ) -> Double? {
    for key in keys {
      if let v = root[key] {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        if let s = v as? String, let d = Double(s.replacingOccurrences(of: "$", with: "")) {
          return d
        }
      }
    }
    return nil
  }

  /// Parses `usageBasedCosts` which the API serializes inconsistently —
  /// sometimes a `"$1.23"` string, sometimes a number, sometimes an object
  /// with a `cost`/`totalCost` field.
  nonisolated private static func parseCostField(_ value: Any?) -> Double {
    if let s = value as? String {
      let trimmed = s.replacingOccurrences(of: "$", with: "")
        .replacingOccurrences(of: ",", with: "")
      return Double(trimmed) ?? 0
    }
    if let d = value as? Double { return d }
    if let i = value as? Int { return Double(i) }
    if let dict = value as? [String: Any] {
      for key in ["cost", "totalCost", "amount", "value", "price"] {
        if let nested = dict[key] {
          let v = parseCostField(nested)
          if v != 0 { return v }
        }
      }
    }
    if let array = value as? [Any] {
      return array.map { parseCostField($0) }.reduce(0, +)
    }
    return 0
  }

  // MARK: - Snapshot building

  /// How many events to surface in the tooltip's "Recent usage" section.
  static let recentEventsLimit = 5

  /// `internal` so unit tests can build snapshots from synthetic inputs
  /// without going through the full `fetchUsage` HTTP path.
  nonisolated static func buildSnapshot(
    events: [UsageEvent],
    periodTotals: CurrentPeriodTotals?,
    periodStart: Date,
    sourceKind: UsageSourceKind,
    sourceLabel: String
  ) -> UsageSnapshot {
    let now = Date()

    var spentUsageBased = 0.0
    for event in events where !event.kind.uppercased().contains("ERROR")
      && !event.kind.uppercased().contains("INCLUDED") {
      spentUsageBased += event.cost
    }

    let spent = periodTotals?.totalSpendDollars
      ?? periodTotals?.spent
      ?? spentUsageBased

    let limit = periodTotals?.limitDollars
      ?? periodTotals?.includedDollars
      ?? periodTotals?.hardLimitDollars

    /// `UsageSnapshot.percentUsed` is the 0-1 fraction the status-bar bars
    /// and popover progress bar expect — multiplied to a percentage by the
    /// view layer. Storing it as 0-100 here would cause double-scaling in
    /// `StatusBarUsageBars`.
    let percentUsed: Double? = limit.flatMap { lim in
      lim > 0 ? min(1, spent / lim) : nil
    }

    let resetLabel = formatPeriodReset(
      cycleEnd: periodTotals?.billingCycleEnd,
      periodStart: periodStart
    )

    var metrics: [UsageMetric] = []

    if let apiPct = periodTotals?.apiPercentUsed {
      metrics.append(UsageMetric(
        label: "API usage",
        value: formatPercent(apiPct),
        style: percentStyle(apiPct)
      ))
    }

    if let autoPct = periodTotals?.autoPercentUsed {
      metrics.append(UsageMetric(
        label: "Auto model usage",
        value: formatPercent(autoPct),
        style: .normal
      ))
    }

    if let limit {
      let pctDisplay = (percentUsed ?? 0) * 100
      metrics.append(UsageMetric(
        label: "Spend",
        value: "\(formatDollars(spent)) / \(formatDollars(limit)) (\(formatPercent(pctDisplay)))",
        style: percentStyle(pctDisplay)
      ))
    } else {
      metrics.append(UsageMetric(
        label: "Spend",
        value: formatDollars(spent),
        style: .cost
      ))
    }

    if let resetLabel {
      metrics.append(UsageMetric(label: "Resets", value: resetLabel, style: .normal))
    }

    let recentEvents = groupEventsByModel(events, limit: recentEventsLimit)

    return UsageSnapshot(
      provider: .cursor,
      sourceKind: sourceKind,
      sourceLabel: sourceLabel,
      account: nil,
      quotaWindow: UsageQuotaWindow(name: "Monthly", resetLabel: resetLabel),
      used: formatDollars(spent),
      limit: limit.map { formatDollars($0) },
      remaining: limit.map { formatDollars(max(0, $0 - spent)) },
      percentUsed: percentUsed,
      metrics: metrics,
      events: recentEvents,
      fetchedAt: now
    )
  }

  /// Groups events by `model`, sums their `chargedDollars`, and returns the
  /// top `limit` rows ordered by total spend descending. Each row's
  /// `timestamp` is the most recent event for that model — preserves stable
  /// SwiftUI identity across refetches via `UsageEventDisplay.id`.
  ///
  /// `internal` (not `private`) so unit tests can exercise the grouping
  /// logic without going through the full `fetchUsage` HTTP path.
  nonisolated static func groupEventsByModel(
    _ events: [UsageEvent],
    limit: Int
  ) -> [UsageEventDisplay] {
    var totals: [String: (dollars: Double, latest: Date)] = [:]

    for event in events {
      let existing = totals[event.model]
      let newest = max(existing?.latest ?? .distantPast, event.timestamp)
      totals[event.model] = (
        dollars: (existing?.dollars ?? 0) + event.chargedDollars,
        latest: newest
      )
    }

    return totals
      .map { model, value in
        UsageEventDisplay(model: model, dollars: value.dollars, timestamp: value.latest)
      }
      .sorted { lhs, rhs in
        if lhs.dollars != rhs.dollars {
          return lhs.dollars > rhs.dollars
        }

        return lhs.timestamp > rhs.timestamp
      }
      .prefix(limit)
      .map { $0 }
  }

  /// Maps a percentage (0-100) to the metric style we use for the spend row,
  /// matching the popover's color thresholds.
  nonisolated private static func percentStyle(_ percent: Double) -> UsageMetricStyle {
    if percent >= 90 { return .warning }
    return .cost
  }

  nonisolated private static func formatPercent(_ value: Double) -> String {
    String(format: "%.2f%%", value)
  }

  // MARK: - Period & formatting helpers

  /// Returns `[startOfCurrentMonthUTC, now]`. Matches Cursor's billing
  /// display, which resets on the 1st of each calendar month.
  nonisolated private static func currentBillingPeriod() -> (Date, Date) {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
    let now = Date()
    let components = calendar.dateComponents([.year, .month], from: now)
    let start = calendar.date(from: components) ?? now
    return (start, now)
  }

  /// Prefers the API-provided `billingCycleEnd` when available; otherwise
  /// falls back to "first of next month" derived from `periodStart`. The
  /// fallback only matters for accounts where the dashboard endpoint omits
  /// or 4xxs the period totals.
  nonisolated private static func formatPeriodReset(
    cycleEnd: Date?,
    periodStart: Date
  ) -> String? {
    let display = DateFormatter()
    display.dateStyle = .medium
    display.timeStyle = .none

    if let cycleEnd {
      return display.string(from: cycleEnd)
    }

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
    guard let next = calendar.date(byAdding: .month, value: 1, to: periodStart) else {
      return nil
    }
    return display.string(from: next)
  }

  nonisolated private static func formatDollars(_ value: Double) -> String {
    String(format: "$%.2f", value)
  }

  nonisolated private static func formatTokens(_ value: Int) -> String {
    if value >= 1_000_000 {
      return String(format: "%.1fM", Double(value) / 1_000_000)
    }
    if value >= 1_000 {
      return "\(value / 1_000)k"
    }
    return "\(value)"
  }

  // MARK: - Cursor State DB (auto-detect)

  /// Returns true when Cursor.app's state DB is present at its default path.
  /// A cheap, prompt-free probe used by `UsageService.resolveCursorAuth` to
  /// decide between auto-detect and manual-paste paths.
  nonisolated static func canReadStateDB(
    path: String = defaultStateDBPath
  ) -> Bool {
    FileManager.default.fileExists(atPath: path)
  }

  /// Reads the current Cursor session JWT from Cursor.app's state DB.
  /// Throws `UsageFetchError.noCredentials` when the file is missing, locked,
  /// or doesn't contain the `cursorAuth/accessToken` row. The DB is opened
  /// read-only with no journal mutations so it's safe alongside a running
  /// Cursor instance — but Cursor can briefly hold an exclusive lock during
  /// writes, in which case the caller's cache fallback covers the gap.
  nonisolated static func readJWTFromCursorState(
    path: String = defaultStateDBPath
  ) throws -> String {
    guard FileManager.default.fileExists(atPath: path) else {
      Logger.usage.info("[cursor] State DB not found at \(path) — Cursor.app likely not installed")
      throw UsageFetchError.noCredentials
    }

    var db: OpaquePointer?
    let openFlags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX

    guard sqlite3_open_v2(path, &db, openFlags, nil) == SQLITE_OK else {
      let message = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
      sqlite3_close(db)
      Logger.usage.error("[cursor] sqlite3_open_v2 failed: \(message)")
      throw UsageFetchError.noCredentials
    }

    defer { sqlite3_close(db) }

    var stmt: OpaquePointer?
    let query = "SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken' LIMIT 1"

    guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
      Logger.usage.error("[cursor] sqlite3_prepare_v2 failed — schema change in state.vscdb?")
      throw UsageFetchError.noCredentials
    }

    defer { sqlite3_finalize(stmt) }

    guard sqlite3_step(stmt) == SQLITE_ROW else {
      Logger.usage.warning("[cursor] cursorAuth/accessToken row not found — user likely not signed in to Cursor.app")
      throw UsageFetchError.noCredentials
    }

    guard let cString = sqlite3_column_text(stmt, 0) else {
      Logger.usage.error("[cursor] cursorAuth/accessToken row is NULL")
      throw UsageFetchError.noCredentials
    }

    let token = String(cString: cString).trimmingCharacters(in: .whitespacesAndNewlines)

    guard !token.isEmpty else {
      Logger.usage.error("[cursor] cursorAuth/accessToken row is empty after trim")
      throw UsageFetchError.noCredentials
    }

    let segmentCount = token.split(separator: ".").count
    let looksLikeJWT = segmentCount == 3
    Logger.usage.info(
      "[cursor] Read accessToken from state DB — length=\(token.count) segments=\(segmentCount) looksLikeJWT=\(looksLikeJWT) sample=\(redact(token))"
    )

    if !looksLikeJWT {
      // Not throwing — let the caller try anyway and log the downstream
      // failure. Common cause: Cursor wrapped the token in JSON or changed
      // the storage key.
      Logger.usage.warning(
        "[cursor] Token in state DB does not look like a JWT (expected 3 dot-separated segments). Cursor.app may have changed its storage format."
      )
    }

    return token
  }
}
