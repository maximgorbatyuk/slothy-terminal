import Foundation

/// Supported usage stats providers.
enum UsageProvider: String, Codable, CaseIterable {
  case claude
  case codex
  case opencode
  case cursor
  case minimax

  var displayName: String {
    switch self {
    case .claude:
      return "Claude"

    case .codex:
      return "Codex"

    case .opencode:
      return "OpenCode"

    case .cursor:
      return "Cursor"

    case .minimax:
      return "MiniMax"
    }
  }

  /// Providers shown in the status bar usage area.
  static let statusBarProviders: [UsageProvider] = [.claude, .codex, .cursor, .minimax]

  /// SF Symbol icon name for the usage display.
  var iconName: String {
    switch self {
    case .claude:
      return "brain.head.profile"

    case .codex:
      return "curlybraces"

    case .opencode:
      return "chevron.left.forwardslash.chevron.right"

    case .cursor:
      return "cursorarrow.rays"

    case .minimax:
      return "sparkles"
    }
  }
}

/// The kind of authentication source used for usage fetching.
enum UsageSourceKind: String, Codable, CaseIterable {
  case apiKey
  case cliOAuth
  case browser
  case experimental

  var displayName: String {
    switch self {
    case .apiKey:
      return "API Key"

    case .cliOAuth:
      return "CLI Auth"

    case .browser:
      return "Browser"

    case .experimental:
      return "Experimental"
    }
  }

  /// Whether this source kind uses official/documented provider APIs.
  var isOfficial: Bool {
    switch self {
    case .apiKey, .cliOAuth:
      return true

    case .browser, .experimental:
      return false
    }
  }
}

/// Describes a discovered authentication source for a provider.
struct UsageAuthSource: Equatable {
  let provider: UsageProvider
  let kind: UsageSourceKind
  let label: String
  let detail: String?

  /// Whether this source relies on undocumented or private endpoints.
  var isExperimental: Bool {
    !kind.isOfficial
  }
}

/// Current fetch status for usage data.
enum UsageFetchStatus: Equatable {
  case idle
  case loading
  case loaded(Date)
  case failed(String)
  case unavailable(String)
  case tokenExpired
}

/// A billing or quota window.
struct UsageQuotaWindow: Equatable {
  let name: String
  let resetLabel: String?
}

/// Display style for a usage metric value.
enum UsageMetricStyle: String, Codable, Equatable {
  case normal
  case highlighted
  case warning
  case cost
}

/// A single usage metric for display.
struct UsageMetric: Identifiable, Equatable {
  let id = UUID()
  let label: String
  let value: String
  let style: UsageMetricStyle

  init(label: String, value: String, style: UsageMetricStyle = .normal) {
    self.label = label
    self.value = value
    self.style = style
  }

  static func == (lhs: UsageMetric, rhs: UsageMetric) -> Bool {
    lhs.label == rhs.label && lhs.value == rhs.value && lhs.style == rhs.style
  }
}

/// A single chargeable event for the "Recent usage" tooltip section.
/// Provider-agnostic, but currently only Cursor populates it.
///
/// `id` is derived from `timestamp` + `model` so SwiftUI's `ForEach` keeps
/// the same row identity across refetches when the underlying event is the
/// same — without this, every refresh would generate fresh UUIDs and
/// trigger view diff churn (potential animation flicker).
struct UsageEventDisplay: Identifiable, Equatable {
  let model: String
  let dollars: Double
  let timestamp: Date

  var id: String {
    "\(timestamp.timeIntervalSince1970)-\(model)"
  }
}

/// A snapshot of usage data from a provider.
struct UsageSnapshot: Equatable {
  let provider: UsageProvider
  let sourceKind: UsageSourceKind
  let sourceLabel: String
  let account: String?
  let quotaWindow: UsageQuotaWindow?
  let used: String
  let limit: String?
  let remaining: String?
  let percentUsed: Double?
  let metrics: [UsageMetric]
  let events: [UsageEventDisplay]
  let fetchedAt: Date

  init(
    provider: UsageProvider,
    sourceKind: UsageSourceKind,
    sourceLabel: String,
    account: String?,
    quotaWindow: UsageQuotaWindow?,
    used: String,
    limit: String?,
    remaining: String?,
    percentUsed: Double?,
    metrics: [UsageMetric],
    events: [UsageEventDisplay] = [],
    fetchedAt: Date
  ) {
    self.provider = provider
    self.sourceKind = sourceKind
    self.sourceLabel = sourceLabel
    self.account = account
    self.quotaWindow = quotaWindow
    self.used = used
    self.limit = limit
    self.remaining = remaining
    self.percentUsed = percentUsed
    self.metrics = metrics
    self.events = events
    self.fetchedAt = fetchedAt
  }
}

/// User preferences for the usage stats feature.
struct UsagePreferences: Codable, Equatable {
  var isEnabled: Bool = false
  var enableExperimentalSources: Bool = false
  var refreshIntervalSeconds: Int = 300

  /// Refresh interval as TimeInterval, clamped to non-negative.
  var refreshInterval: TimeInterval {
    max(0, TimeInterval(refreshIntervalSeconds))
  }
}

// MARK: - API Response Models

/// Anthropic organizations list response.
struct AnthropicOrganizationsResponse: Codable {
  let data: [AnthropicOrganization]
}

/// A single Anthropic organization.
struct AnthropicOrganization: Codable {
  let id: String
  let name: String
}

/// MiniMax usage API response.
struct MinimaxUsageResponse: Codable {
  let modelRemains: [MinimaxModelRemains]
  let baseResp: MinimaxBaseResp

  enum CodingKeys: String, CodingKey {
    case modelRemains = "model_remains"
    case baseResp = "base_resp"
  }
}

/// MiniMax API response status.
struct MinimaxBaseResp: Codable {
  let statusCode: Int
  let statusMsg: String

  enum CodingKeys: String, CodingKey {
    case statusCode = "status_code"
    case statusMsg = "status_msg"
  }
}

/// A single model's usage data from MiniMax API.
///
/// Despite their names, `current_interval_usage_count` and
/// `current_weekly_usage_count` report **remaining** quota in the window —
/// not consumed quota. Real consumption is `total - usage_count`. The field
/// names mirror the wire format; do not rename. See `MinimaxUsageProvider`.
struct MinimaxModelRemains: Codable {
  let modelName: String
  let startTime: Int64
  let endTime: Int64
  let remainsTime: Int64
  let currentIntervalTotalCount: Int
  /// Remaining (not consumed) calls in the current interval, despite the name.
  let currentIntervalUsageCount: Int
  let currentWeeklyTotalCount: Int
  /// Remaining (not consumed) calls in the current week, despite the name.
  let currentWeeklyUsageCount: Int
  let weeklyStartTime: Int64
  let weeklyEndTime: Int64
  let weeklyRemainsTime: Int64

  enum CodingKeys: String, CodingKey {
    case modelName = "model_name"
    case startTime = "start_time"
    case endTime = "end_time"
    case remainsTime = "remains_time"
    case currentIntervalTotalCount = "current_interval_total_count"
    case currentIntervalUsageCount = "current_interval_usage_count"
    case currentWeeklyTotalCount = "current_weekly_total_count"
    case currentWeeklyUsageCount = "current_weekly_usage_count"
    case weeklyStartTime = "weekly_start_time"
    case weeklyEndTime = "weekly_end_time"
    case weeklyRemainsTime = "weekly_remains_time"
  }
}

// MARK: - Errors

/// Errors that can occur during usage data fetching.
enum UsageFetchError: LocalizedError {
  case noCredentials
  case invalidCredentials
  case invalidURL
  case invalidResponse
  case httpError(Int)
  case noOrganization
  case parseError
  case unsupportedSource
  case tokenExpired

  var errorDescription: String? {
    switch self {
    case .noCredentials:
      return "No credentials found"

    case .invalidCredentials:
      return "Invalid credentials format"

    case .invalidURL:
      return "Invalid API URL"

    case .invalidResponse:
      return "Invalid API response"

    case .httpError(let code):
      return "HTTP error \(code)"

    case .noOrganization:
      return "No organization found"

    case .parseError:
      return "Failed to parse response"

    case .unsupportedSource:
      return "Unsupported auth source"

    case .tokenExpired:
      return "OAuth token expired"
    }
  }
}
