import Foundation
import OSLog

/// Fetches MiniMax (platform.minimax.io) coding-plan quota usage.
///
/// Endpoint: `GET /v1/api/openplatform/coding_plan/remains` with the user's
/// platform API key as `Authorization: Bearer <key>`. Returns per-model
/// interval (≈5h) and weekly (7d) quotas. The `MiniMax-M*` row is the
/// canonical coding-plan slot; `coding-plan-vlm` and `coding-plan-search`
/// share the same numbers and are skipped to avoid double-counting.
enum MinimaxUsageProvider {
  private static let endpoint = "https://platform.minimax.io/v1/api/openplatform/coding_plan/remains"
  private static let requestTimeout: TimeInterval = 15

  static func fetchUsage(apiKey: String) async throws -> UsageSnapshot {
    let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

    Logger.usage.info("[minimax] fetchUsage entry — apiKeyLength=\(trimmed.count)")

    guard !trimmed.isEmpty else {
      Logger.usage.error("[minimax] Empty API key after trimming")
      throw UsageFetchError.noCredentials
    }

    guard let url = URL(string: endpoint) else {
      Logger.usage.error("[minimax] Invalid endpoint URL: \(endpoint)")
      throw UsageFetchError.invalidURL
    }

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.timeoutInterval = requestTimeout
    request.setValue("Bearer \(trimmed)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("SlothyTerminal", forHTTPHeaderField: "User-Agent")

    Logger.usage.info("[minimax] Sending GET \(endpoint)")

    let (data, response) = try await URLSession.shared.data(for: request)

    let httpStatus = (response as? HTTPURLResponse)?.statusCode

    ProviderResponseStore.record(
      provider: .minimax,
      endpoint: "coding_plan/remains",
      url: endpoint,
      statusCode: httpStatus,
      body: data
    )

    guard let httpResponse = response as? HTTPURLResponse else {
      Logger.usage.error("[minimax] Response is not HTTPURLResponse")
      throw UsageFetchError.invalidResponse
    }

    Logger.usage.info("[minimax] HTTP \(httpResponse.statusCode) — \(data.count) bytes")

    if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
      let preview = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
      Logger.usage.warning("[minimax] HTTP \(httpResponse.statusCode) — token rejected. Body preview: \(preview)")
      throw UsageFetchError.tokenExpired
    }

    guard httpResponse.statusCode == 200 else {
      let preview = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
      Logger.usage.error("[minimax] HTTP \(httpResponse.statusCode). Body preview: \(preview)")
      throw UsageFetchError.httpError(httpResponse.statusCode)
    }

    return try parseSnapshot(data: data)
  }

  /// Pure parser — exposed for tests. Throws `.parseError` on schema mismatch
  /// or `base_resp.status_code != 0`.
  nonisolated static func parseSnapshot(data: Data) throws -> UsageSnapshot {
    let decoded: MinimaxUsageResponse
    do {
      decoded = try JSONDecoder().decode(MinimaxUsageResponse.self, from: data)
    } catch {
      let preview = String(data: data, encoding: .utf8)?.prefix(300) ?? ""
      Logger.usage.error("[minimax] Decode failed: \(error.localizedDescription). Body preview: \(preview)")
      throw UsageFetchError.parseError
    }

    guard decoded.baseResp.statusCode == 0 else {
      Logger.usage.error("[minimax] base_resp.status_code=\(decoded.baseResp.statusCode), msg=\(decoded.baseResp.statusMsg)")
      throw UsageFetchError.parseError
    }

    Logger.usage.info("[minimax] Parsed \(decoded.modelRemains.count) model rows")
    return buildSnapshot(rows: decoded.modelRemains)
  }

  /// Builds a snapshot from parsed rows. `MiniMax-M*` is the headline; if
  /// missing, the row with the highest real interval utilization wins.
  /// `coding-plan-vlm` and `coding-plan-search` are skipped (duplicates of M*).
  ///
  /// Important: despite their names, MiniMax's `current_*_usage_count` fields
  /// report **remaining** quota, not consumed quota. So real consumption is
  /// `total - usage_count`. See `MinimaxModelRemains` doc comment.
  nonisolated static func buildSnapshot(rows: [MinimaxModelRemains]) -> UsageSnapshot {
    let codingPlanAliases: Set<String> = ["coding-plan-vlm", "coding-plan-search"]
    let candidates = rows.filter { !codingPlanAliases.contains($0.modelName) }

    let headline = candidates.first { $0.modelName == "MiniMax-M*" }
      ?? candidates
        .filter { $0.currentIntervalTotalCount > 0 }
        .max { lhs, rhs in
          let lUsed = lhs.currentIntervalTotalCount - lhs.currentIntervalUsageCount
          let rUsed = rhs.currentIntervalTotalCount - rhs.currentIntervalUsageCount
          let lUtil = Double(lUsed) / Double(lhs.currentIntervalTotalCount)
          let rUtil = Double(rUsed) / Double(rhs.currentIntervalTotalCount)
          return lUtil < rUtil
        }

    let now = Date()

    guard let row = headline else {
      return UsageSnapshot(
        provider: .minimax,
        sourceKind: .apiKey,
        sourceLabel: "API Key",
        account: nil,
        quotaWindow: nil,
        used: "Connected",
        limit: nil,
        remaining: nil,
        percentUsed: nil,
        metrics: [],
        fetchedAt: now
      )
    }

    let intervalEnd = Date(timeIntervalSince1970: TimeInterval(row.endTime) / 1000)
    let weeklyEnd = Date(timeIntervalSince1970: TimeInterval(row.weeklyEndTime) / 1000)

    let intervalRemaining = max(0, row.currentIntervalUsageCount)
    let intervalUsed = max(0, row.currentIntervalTotalCount - intervalRemaining)
    let weeklyRemaining = max(0, row.currentWeeklyUsageCount)
    let weeklyUsed = max(0, row.currentWeeklyTotalCount - weeklyRemaining)

    let percent = row.currentIntervalTotalCount > 0
      ? Double(intervalUsed) / Double(row.currentIntervalTotalCount)
      : nil

    var metrics: [UsageMetric] = []

    metrics.append(UsageMetric(
      label: "Weekly used",
      value: "\(weeklyUsed) / \(row.currentWeeklyTotalCount)",
      style: .highlighted
    ))

    metrics.append(UsageMetric(
      label: "Weekly resets",
      value: formatRelative(weeklyEnd, from: now),
      style: .normal
    ))

    for other in candidates where other.modelName != row.modelName && other.currentIntervalTotalCount > 0 {
      let otherUsed = max(0, other.currentIntervalTotalCount - other.currentIntervalUsageCount)
      metrics.append(UsageMetric(
        label: other.modelName,
        value: "\(otherUsed) / \(other.currentIntervalTotalCount)",
        style: .normal
      ))
    }

    return UsageSnapshot(
      provider: .minimax,
      sourceKind: .apiKey,
      sourceLabel: "API Key",
      account: row.modelName,
      quotaWindow: UsageQuotaWindow(
        name: "Interval",
        resetLabel: "resets \(formatRelative(intervalEnd, from: now))"
      ),
      used: "\(intervalUsed)",
      limit: "\(row.currentIntervalTotalCount)",
      remaining: "\(intervalRemaining)",
      percentUsed: percent,
      metrics: metrics,
      fetchedAt: now
    )
  }

  nonisolated private static func formatRelative(_ date: Date, from now: Date) -> String {
    let seconds = Int(date.timeIntervalSince(now))

    guard seconds > 0 else {
      return "soon"
    }

    let hours = seconds / 3600
    let minutes = (seconds % 3600) / 60

    if hours >= 24 {
      let days = hours / 24
      let remHours = hours % 24
      return "in \(days)d \(remHours)h"
    }

    if hours > 0 {
      return "in \(hours)h \(minutes)m"
    }

    return "in \(minutes)m"
  }
}