import Foundation
import OSLog

/// Manages usage data fetching for AI providers.
/// Handles auth source discovery, credential resolution, and API requests.
@Observable
@MainActor
class UsageService {
  static let shared = UsageService()

  /// Resolved auth sources per provider.
  private(set) var resolvedSources: [UsageProvider: UsageAuthSource] = [:]

  /// Cached snapshots per provider.
  private(set) var snapshots: [UsageProvider: UsageSnapshot] = [:]

  /// Current fetch status per provider.
  private(set) var fetchStatuses: [UsageProvider: UsageFetchStatus] = [:]

  @ObservationIgnored
  private var refreshTasks: [UsageProvider: Task<Void, Never>] = [:]

  @ObservationIgnored
  private var startupTask: Task<Void, Never>?

  private init() {}

  // MARK: - Public API

  /// Resolves auth sources and starts fetching if usage is enabled.
  func startIfEnabled() {
    let prefs = ConfigManager.shared.config.usagePreferences

    guard prefs.isEnabled else {
      stopAll()
      return
    }

    startupTask?.cancel()
    startupTask = Task {
      resolveAuthSources()
      await fetchAll()

      guard !Task.isCancelled else {
        return
      }

      startAutoRefresh(interval: prefs.refreshInterval)
    }
  }

  /// Stops all refresh timers and cancels in-flight startup.
  func stopAll() {
    startupTask?.cancel()
    startupTask = nil

    for (_, task) in refreshTasks {
      task.cancel()
    }
    refreshTasks.removeAll()
  }

  /// Fetches usage for a specific provider.
  func fetch(provider: UsageProvider) async {
    guard let source = resolvedSources[provider] else {
      fetchStatuses[provider] = .unavailable("No auth source found")
      return
    }

    fetchStatuses[provider] = .loading

    do {
      let snapshot = try await fetchUsage(source: source)
      snapshots[provider] = snapshot
      fetchStatuses[provider] = .loaded(Date())
    } catch is CancellationError {
      // Task was cancelled — don't update status.
      return
    } catch {
      Logger.usage.error(
        "Usage fetch failed for \(provider.rawValue): \(error.localizedDescription)"
      )
      fetchStatuses[provider] = .failed(error.localizedDescription)
    }
  }

  /// Fetches usage for all resolved providers concurrently.
  func fetchAll() async {
    await withTaskGroup(of: Void.self) { group in
      for provider in resolvedSources.keys {
        group.addTask { await self.fetch(provider: provider) }
      }
    }
  }

  /// Returns the snapshot for a provider.
  func snapshot(for provider: UsageProvider) -> UsageSnapshot? {
    snapshots[provider]
  }

  /// Returns the fetch status for a provider.
  func status(for provider: UsageProvider) -> UsageFetchStatus {
    fetchStatuses[provider] ?? .idle
  }

  /// Returns the resolved auth source for a provider.
  func authSource(for provider: UsageProvider) -> UsageAuthSource? {
    resolvedSources[provider]
  }

  /// Maps an agent type to a usage provider.
  nonisolated static func provider(for agentType: AgentType) -> UsageProvider? {
    switch agentType {
    case .claude:
      return .claude

    case .opencode:
      return .opencode

    case .terminal:
      return nil
    }
  }

  /// Clears all cached data and imported auth material for a provider.
  func clearProvider(_ provider: UsageProvider) {
    refreshTasks[provider]?.cancel()
    refreshTasks.removeValue(forKey: provider)
    snapshots.removeValue(forKey: provider)
    fetchStatuses.removeValue(forKey: provider)
    resolvedSources.removeValue(forKey: provider)
    UsageKeychainStore.deleteAll(provider: provider)
  }

  /// Clears all cached data and imported auth material.
  func clearAll() {
    stopAll()
    snapshots.removeAll()
    fetchStatuses.removeAll()
    resolvedSources.removeAll()
    UsageKeychainStore.deleteAll()
  }

  // MARK: - Auth Resolution

  /// Discovers available auth sources for all providers.
  func resolveAuthSources() {
    let prefs = ConfigManager.shared.config.usagePreferences

    resolvedSources[.claude] = resolveClaudeAuth(
      allowExperimental: prefs.enableExperimentalSources
    )

    if prefs.enableExperimentalSources {
      resolvedSources[.opencode] = resolveOpenCodeAuth()
    }
  }

  /// Resolves Claude auth in priority order:
  /// 1. ANTHROPIC_API_KEY env var
  /// 2. Claude CLI OAuth tokens (~/.claude/)
  /// 3. Imported browser session (opt-in, experimental)
  func resolveClaudeAuth(allowExperimental: Bool) -> UsageAuthSource? {
    // 1. API key from environment.
    if let apiKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"],
       !apiKey.isEmpty
    {
      return UsageAuthSource(
        provider: .claude,
        kind: .apiKey,
        label: "API Key",
        detail: "ANTHROPIC_API_KEY environment variable"
      )
    }

    // 2. Claude CLI OAuth credentials.
    for path in Self.claudeCredentialPaths {
      if FileManager.default.fileExists(atPath: path) {
        return UsageAuthSource(
          provider: .claude,
          kind: .cliOAuth,
          label: "CLI Auth",
          detail: "Claude CLI credentials"
        )
      }
    }

    // 3. Imported browser session (experimental, opt-in).
    if allowExperimental,
       UsageKeychainStore.loadString(provider: .claude, sourceKind: .browser) != nil
    {
      return UsageAuthSource(
        provider: .claude,
        kind: .browser,
        label: "Browser Session",
        detail: "Imported browser cookies"
      )
    }

    return nil
  }

  /// Resolves OpenCode auth.
  /// No stable public usage API exists — always experimental.
  func resolveOpenCodeAuth() -> UsageAuthSource? {
    if UsageKeychainStore.loadString(provider: .opencode, sourceKind: .experimental) != nil {
      return UsageAuthSource(
        provider: .opencode,
        kind: .experimental,
        label: "Experimental",
        detail: "OpenCode private endpoint"
      )
    }

    return nil
  }

  // MARK: - Credential Paths

  static let claudeCredentialPaths = [
    "\(NSHomeDirectory())/.claude/.credentials.json",
    "\(NSHomeDirectory())/.claude/credentials.json",
  ]

  // MARK: - Fetching

  private func fetchUsage(source: UsageAuthSource) async throws -> UsageSnapshot {
    switch source.provider {
    case .claude:
      return try await fetchClaudeUsage(source: source)

    case .opencode:
      return try await fetchOpenCodeUsage(source: source)
    }
  }

  private func fetchClaudeUsage(source: UsageAuthSource) async throws -> UsageSnapshot {
    switch source.kind {
    case .apiKey:
      return try await fetchClaudeUsageViaAPI()

    case .cliOAuth:
      return try await fetchClaudeUsageViaCLIAuth()

    case .browser:
      return try await fetchClaudeUsageViaBrowser()

    case .experimental:
      throw UsageFetchError.unsupportedSource
    }
  }

  /// Fetches usage via the Anthropic API (ANTHROPIC_API_KEY).
  private func fetchClaudeUsageViaAPI() async throws -> UsageSnapshot {
    guard let apiKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] else {
      throw UsageFetchError.noCredentials
    }

    guard let orgURL = URL(string: "https://api.anthropic.com/v1/organizations") else {
      throw UsageFetchError.invalidURL
    }

    var orgRequest = URLRequest(url: orgURL)
    orgRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
    orgRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

    let (orgData, orgResponse) = try await URLSession.shared.data(for: orgRequest)

    guard let httpResponse = orgResponse as? HTTPURLResponse else {
      throw UsageFetchError.invalidResponse
    }

    // If the key lacks admin access, return a limited snapshot.
    if httpResponse.statusCode == 403 || httpResponse.statusCode == 401 {
      return UsageSnapshot(
        provider: .claude,
        sourceKind: .apiKey,
        sourceLabel: "API Key",
        account: nil,
        quotaWindow: nil,
        used: "N/A",
        limit: nil,
        remaining: nil,
        percentUsed: nil,
        metrics: [
          UsageMetric(
            label: "Status",
            value: "Admin access required for usage data",
            style: .normal
          )
        ],
        fetchedAt: Date()
      )
    }

    guard httpResponse.statusCode == 200 else {
      throw UsageFetchError.httpError(httpResponse.statusCode)
    }

    let orgInfo = try JSONDecoder().decode(
      AnthropicOrganizationsResponse.self, from: orgData
    )

    guard let org = orgInfo.data.first else {
      throw UsageFetchError.noOrganization
    }

    // Build usage request for current month.
    let now = Date()
    let components = Calendar(identifier: .gregorian).dateComponents(
      [.year, .month], from: now
    )

    guard let year = components.year,
          let month = components.month
    else {
      throw UsageFetchError.invalidURL
    }

    let monthStart = String(format: "%04d-%02d-01", year, month)
    let today = Self.isoDateFormatter.string(from: now)

    // Use URLComponents to safely construct the usage URL.
    var usageComponents = URLComponents(
      string: "https://api.anthropic.com/v1/organizations"
    )!
    usageComponents.path += "/\(org.id)/usage"
    usageComponents.queryItems = [
      URLQueryItem(name: "start_date", value: monthStart),
      URLQueryItem(name: "end_date", value: today),
    ]

    guard let usageURL = usageComponents.url else {
      throw UsageFetchError.invalidURL
    }

    var usageRequest = URLRequest(url: usageURL)
    usageRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
    usageRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

    let (usageData, usageResponse) = try await URLSession.shared.data(for: usageRequest)

    guard let usageHTTP = usageResponse as? HTTPURLResponse,
          usageHTTP.statusCode == 200
    else {
      // Org fetched but usage endpoint inaccessible.
      return UsageSnapshot(
        provider: .claude,
        sourceKind: .apiKey,
        sourceLabel: "API Key",
        account: org.name,
        quotaWindow: UsageQuotaWindow(name: "Monthly", resetLabel: nil),
        used: "Unavailable",
        limit: nil,
        remaining: nil,
        percentUsed: nil,
        metrics: [],
        fetchedAt: Date()
      )
    }

    return Self.parseAnthropicUsageResponse(data: usageData, orgName: org.name)
  }

  /// Fetches usage via Claude CLI OAuth tokens.
  private func fetchClaudeUsageViaCLIAuth() async throws -> UsageSnapshot {
    var credData: Data?
    for path in Self.claudeCredentialPaths {
      if let data = FileManager.default.contents(atPath: path) {
        credData = data
        break
      }
    }

    guard let data = credData else {
      throw UsageFetchError.noCredentials
    }

    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw UsageFetchError.invalidCredentials
    }

    // Look for an OAuth access token in common credential formats.
    let token = json["accessToken"] as? String
      ?? json["access_token"] as? String
      ?? (json["claude.ai"] as? [String: Any])?["accessToken"] as? String

    guard let oauthToken = token,
          !oauthToken.isEmpty
    else {
      throw UsageFetchError.noCredentials
    }

    guard let url = URL(string: "https://api.claude.ai/api/organizations") else {
      throw UsageFetchError.invalidURL
    }

    var request = URLRequest(url: url)
    request.setValue("Bearer \(oauthToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")

    let (responseData, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw UsageFetchError.invalidResponse
    }

    guard httpResponse.statusCode == 200 else {
      throw UsageFetchError.httpError(httpResponse.statusCode)
    }

    return Self.parseClaudeConsoleOrgsResponse(
      data: responseData, sourceKind: .cliOAuth
    )
  }

  /// Fetches usage via an imported browser session cookie.
  private func fetchClaudeUsageViaBrowser() async throws -> UsageSnapshot {
    guard let sessionKey = UsageKeychainStore.loadString(
      provider: .claude,
      sourceKind: .browser
    ) else {
      throw UsageFetchError.noCredentials
    }

    // Reject values with control characters to prevent header injection.
    let sanitized = sessionKey.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !sanitized.isEmpty,
          !sanitized.contains(where: { $0.isNewline || $0 == "\r" })
    else {
      throw UsageFetchError.invalidCredentials
    }

    guard let url = URL(string: "https://api.claude.ai/api/organizations") else {
      throw UsageFetchError.invalidURL
    }

    var request = URLRequest(url: url)
    request.setValue("sessionKey=\(sanitized)", forHTTPHeaderField: "Cookie")
    request.setValue("application/json", forHTTPHeaderField: "Accept")

    let (responseData, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw UsageFetchError.invalidResponse
    }

    guard httpResponse.statusCode == 200 else {
      throw UsageFetchError.httpError(httpResponse.statusCode)
    }

    return Self.parseClaudeConsoleOrgsResponse(
      data: responseData, sourceKind: .browser
    )
  }

  /// OpenCode usage fetching (experimental / placeholder).
  /// No stable public usage endpoint exists for OpenCode.
  private func fetchOpenCodeUsage(source: UsageAuthSource) async throws -> UsageSnapshot {
    UsageSnapshot(
      provider: .opencode,
      sourceKind: .experimental,
      sourceLabel: "Experimental",
      account: nil,
      quotaWindow: nil,
      used: "Not available",
      limit: nil,
      remaining: nil,
      percentUsed: nil,
      metrics: [
        UsageMetric(label: "Status", value: "No stable usage endpoint", style: .normal)
      ],
      fetchedAt: Date()
    )
  }

  // MARK: - Response Parsing

  /// Parses the Anthropic admin usage API response.
  nonisolated static func parseAnthropicUsageResponse(
    data: Data,
    orgName: String
  ) -> UsageSnapshot {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return UsageSnapshot(
        provider: .claude,
        sourceKind: .apiKey,
        sourceLabel: "API Key",
        account: orgName,
        quotaWindow: UsageQuotaWindow(name: "Monthly", resetLabel: nil),
        used: "Parse error",
        limit: nil,
        remaining: nil,
        percentUsed: nil,
        metrics: [],
        fetchedAt: Date()
      )
    }

    var totalInputTokens = 0
    var totalOutputTokens = 0

    if let items = json["data"] as? [[String: Any]] {
      for item in items {
        totalInputTokens += item["input_tokens"] as? Int ?? 0
        totalOutputTokens += item["output_tokens"] as? Int ?? 0
      }
    }

    let totalTokens = totalInputTokens + totalOutputTokens
    var metrics: [UsageMetric] = []

    if totalTokens > 0 {
      metrics.append(UsageMetric(
        label: "Input tokens",
        value: formatTokenCount(totalInputTokens),
        style: .normal
      ))
      metrics.append(UsageMetric(
        label: "Output tokens",
        value: formatTokenCount(totalOutputTokens),
        style: .normal
      ))
    }

    return UsageSnapshot(
      provider: .claude,
      sourceKind: .apiKey,
      sourceLabel: "API Key",
      account: orgName,
      quotaWindow: UsageQuotaWindow(name: "Monthly", resetLabel: nil),
      used: formatTokenCount(totalTokens),
      limit: nil,
      remaining: nil,
      percentUsed: nil,
      metrics: metrics,
      fetchedAt: Date()
    )
  }

  /// Parses the Claude console organizations response.
  nonisolated static func parseClaudeConsoleOrgsResponse(
    data: Data,
    sourceKind: UsageSourceKind
  ) -> UsageSnapshot {
    guard let orgs = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
          let org = orgs.first
    else {
      return UsageSnapshot(
        provider: .claude,
        sourceKind: sourceKind,
        sourceLabel: sourceKind.displayName,
        account: nil,
        quotaWindow: nil,
        used: "Parse error",
        limit: nil,
        remaining: nil,
        percentUsed: nil,
        metrics: [],
        fetchedAt: Date()
      )
    }

    let orgName = org["name"] as? String
    var metrics: [UsageMetric] = []

    if let rateLimits = org["rate_limits"] as? [String: Any] {
      if let messageLimit = rateLimits["message_limit"] as? Int {
        metrics.append(UsageMetric(
          label: "Message limit",
          value: "\(messageLimit)",
          style: .normal
        ))
      }

      if let messagesUsed = rateLimits["messages_used"] as? Int {
        metrics.append(UsageMetric(
          label: "Messages used",
          value: "\(messagesUsed)",
          style: .highlighted
        ))
      }
    }

    if let plan = org["billing_plan"] as? String ?? org["plan"] as? String {
      metrics.append(UsageMetric(
        label: "Plan",
        value: plan.capitalized,
        style: .normal
      ))
    }

    let usedLabel = metrics.first { $0.label == "Messages used" }?.value ?? "Connected"

    return UsageSnapshot(
      provider: .claude,
      sourceKind: sourceKind,
      sourceLabel: sourceKind.displayName,
      account: orgName,
      quotaWindow: nil,
      used: usedLabel,
      limit: nil,
      remaining: nil,
      percentUsed: nil,
      metrics: metrics,
      fetchedAt: Date()
    )
  }

  // MARK: - Formatting

  /// Formats a token count for display.
  nonisolated static func formatTokenCount(_ count: Int) -> String {
    if count >= 1_000_000_000 {
      return String(format: "%.1fB", Double(count) / 1_000_000_000)
    } else if count >= 1_000_000 {
      return String(format: "%.1fM", Double(count) / 1_000_000)
    } else if count >= 1_000 {
      return String(format: "%.1fK", Double(count) / 1_000)
    }

    return "\(count)"
  }

  // MARK: - Auto Refresh

  private func startAutoRefresh(interval: TimeInterval) {
    stopAll()

    // Minimum 30s to prevent abusive refresh from corrupted config.
    // 0 means manual-only (handled by stopAll above clearing timers).
    guard interval >= 30 else {
      return
    }

    for provider in resolvedSources.keys {
      let task = Task { [weak self] in
        while !Task.isCancelled {
          try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))

          guard !Task.isCancelled else {
            return
          }

          await self?.fetch(provider: provider)
        }
      }
      refreshTasks[provider] = task
    }
  }

  // MARK: - Private

  private static let isoDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    return formatter
  }()
}
