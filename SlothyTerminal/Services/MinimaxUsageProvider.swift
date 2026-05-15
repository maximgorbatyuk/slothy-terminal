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

    guard !trimmed.isEmpty else {
      throw UsageFetchError.noCredentials
    }

    guard let url = URL(string: endpoint) else {
      throw UsageFetchError.invalidURL
    }

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.timeoutInterval = requestTimeout
    request.setValue("Bearer \(trimmed)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("SlothyTerminal", forHTTPHeaderField: "User-Agent")

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw UsageFetchError.invalidResponse
    }

    if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
      Logger.usage.warning("[minimax] HTTP \(httpResponse.statusCode) — token expired/invalid")
      throw UsageFetchError.tokenExpired
    }

    guard httpResponse.statusCode == 200 else {
      Logger.usage.error("[minimax] HTTP \(httpResponse.statusCode)")
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
      Logger.usage.error("[minimax] Decode failed: \(error.localizedDescription)")
      throw UsageFetchError.parseError
    }

    guard decoded.baseResp.statusCode == 0 else {
      Logger.usage.error("[minimax] API error \(decoded.baseResp.statusCode): \(decoded.baseResp.statusMsg)")
      throw UsageFetchError.parseError
    }

    return buildSnapshot(rows: decoded.modelRemains)
  }

  /// Builds a snapshot from parsed rows. `MiniMax-M*` is the headline; if
  /// missing, the row with the highest non-zero interval utilization wins.
  /// `coding-plan-vlm` and `coding-plan-search` are skipped (duplicates of M*).
  nonisolated static func buildSnapshot(rows: [MinimaxModelRemains]) -> UsageSnapshot {
    let codingPlanAliases: Set<String> = ["coding-plan-vlm", "coding-plan-search"]
    let candidates = rows.filter { !codingPlanAliases.contains($0.modelName) }

    let headline = candidates.first { $0.modelName == "MiniMax-M*" }
      ?? candidates
        .filter { $0.currentIntervalTotalCount > 0 }
        .max { lhs, rhs in
          let lUtil = Double(lhs.currentIntervalUsageCount) / Double(lhs.currentIntervalTotalCount)
          let rUtil = Double(rhs.currentIntervalUsageCount) / Double(rhs.currentIntervalTotalCount)
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

    let percent = row.currentIntervalTotalCount > 0
      ? Double(row.currentIntervalUsageCount) / Double(row.currentIntervalTotalCount)
      : nil

    var metrics: [UsageMetric] = []

    metrics.append(UsageMetric(
      label: "Weekly used",
      value: "\(row.currentWeeklyUsageCount) / \(row.currentWeeklyTotalCount)",
      style: .highlighted
    ))

    metrics.append(UsageMetric(
      label: "Weekly resets",
      value: formatRelative(weeklyEnd, from: now),
      style: .normal
    ))

    for other in candidates where other.modelName != row.modelName && other.currentIntervalTotalCount > 0 {
      metrics.append(UsageMetric(
        label: other.modelName,
        value: "\(other.currentIntervalUsageCount) / \(other.currentIntervalTotalCount)",
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
      used: "\(row.currentIntervalUsageCount)",
      limit: "\(row.currentIntervalTotalCount)",
      remaining: "\(max(0, row.currentIntervalTotalCount - row.currentIntervalUsageCount))",
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