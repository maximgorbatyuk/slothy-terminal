import Foundation

/// Supported usage stats providers.
enum UsageProvider: String, Codable, CaseIterable {
  case claude
  case codex
  case opencode

  var displayName: String {
    switch self {
    case .claude:
      return "Claude"

    case .codex:
      return "Codex"

    case .opencode:
      return "OpenCode"
    }
  }

  /// Providers shown as subtabs in the sidebar usage block.
  static let sidebarProviders: [UsageProvider] = [.claude, .codex]
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
  let fetchedAt: Date
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

/// Layout values for the sidebar usage stats card.
enum UsageStatsLayout {
  static func contentHeight(forSidebarHeight sidebarHeight: CGFloat) -> CGFloat {
    max(140, sidebarHeight / 4 + 20)
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
    }
  }
}
