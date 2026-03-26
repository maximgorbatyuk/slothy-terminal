import Foundation
import OSLog
import Security

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

  @ObservationIgnored
  private var isStarted = false

  private init() {}

  // MARK: - Public API

  /// Starts the fetch + auto-refresh cycle if not already running.
  /// Idempotent — safe to call from multiple views.
  func ensureStarted() {
    guard !isStarted else {
      return
    }

    isStarted = true
    startIfEnabled()
  }

  /// Resolves auth sources and starts fetching if usage is enabled.
  func startIfEnabled() {
    let prefs = ConfigManager.shared.config.usagePreferences

    guard prefs.isEnabled else {
      stopAll()
      return
    }

    isStarted = true
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
    isStarted = false

    for (_, task) in refreshTasks {
      task.cancel()
    }
    refreshTasks.removeAll()
  }

  /// Fetches usage for a specific provider.
  func fetch(provider: UsageProvider) async {
    guard let source = resolvedSources[provider] else {
      Logger.usage.warning(
        "[\(provider.rawValue)] No auth source resolved — marking unavailable"
      )
      fetchStatuses[provider] = .unavailable("No auth source found")
      return
    }

    Logger.usage.info(
      "[\(provider.rawValue)] Fetching usage via \(source.kind.rawValue) source"
    )
    fetchStatuses[provider] = .loading

    do {
      let snapshot = try await fetchUsage(source: source)
      snapshots[provider] = snapshot
      fetchStatuses[provider] = .loaded(Date())
      Logger.usage.info(
        "[\(provider.rawValue)] Usage fetched successfully"
      )
    } catch is CancellationError {
      // Task was cancelled — don't update status.
      return
    } catch {
      Logger.usage.error(
        "[\(provider.rawValue)] Fetch failed (source=\(source.kind.rawValue)): \(error.localizedDescription)"
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

    resolvedSources[.codex] = resolveCodexAuth(
      allowExperimental: prefs.enableExperimentalSources
    )

    if prefs.enableExperimentalSources {
      resolvedSources[.opencode] = resolveOpenCodeAuth()
    }

    for provider in UsageProvider.sidebarProviders {
      if let source = resolvedSources[provider] {
        Logger.usage.info(
          "[\(provider.rawValue)] Auth resolved: \(source.kind.rawValue) — \(source.label)"
        )
      } else {
        Logger.usage.info(
          "[\(provider.rawValue)] No auth source found"
        )
      }
    }
  }

  /// Resolves Claude auth in priority order:
  /// 1. Claude Code OAuth from macOS Keychain (preferred — has session/weekly limits)
  /// 2. ANTHROPIC_API_KEY env var (admin API — token-level usage only)
  /// 3. Imported browser session (opt-in, experimental)
  func resolveClaudeAuth(allowExperimental: Bool) -> UsageAuthSource? {
    // 1. Claude Code OAuth credentials from Keychain.
    if Self.readClaudeCodeKeychainToken() != nil {
      return UsageAuthSource(
        provider: .claude,
        kind: .cliOAuth,
        label: "Claude Code",
        detail: "OAuth from Keychain"
      )
    }

    // 2. API key from environment.
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

  /// Resolves Codex (OpenAI) auth in priority order:
  /// 1. OPENAI_API_KEY env var
  /// 2. Codex CLI credentials (~/.codex/)
  /// 3. Imported browser session (opt-in, experimental)
  func resolveCodexAuth(allowExperimental: Bool) -> UsageAuthSource? {
    // 1. API key from environment.
    if let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"],
       !apiKey.isEmpty
    {
      return UsageAuthSource(
        provider: .codex,
        kind: .apiKey,
        label: "API Key",
        detail: "OPENAI_API_KEY environment variable"
      )
    }

    // 2. Codex CLI credentials.
    for path in Self.codexCredentialPaths {
      if FileManager.default.fileExists(atPath: path) {
        Logger.usage.info("[codex] Found credential file at \(path)")
        return UsageAuthSource(
          provider: .codex,
          kind: .cliOAuth,
          label: "CLI Auth",
          detail: "Codex CLI credentials"
        )
      }
    }

    // 3. Imported browser session (experimental, opt-in).
    if allowExperimental,
       UsageKeychainStore.loadString(provider: .codex, sourceKind: .browser) != nil
    {
      return UsageAuthSource(
        provider: .codex,
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

  nonisolated static let claudeCredentialPaths = [
    "\(NSHomeDirectory())/.claude/.credentials.json",
    "\(NSHomeDirectory())/.claude/credentials.json",
  ]

  nonisolated static let codexCredentialPaths = [
    "\(NSHomeDirectory())/.codex/auth.json",
    "\(NSHomeDirectory())/.codex/credentials.json",
    "\(NSHomeDirectory())/.config/codex/auth.json",
  ]

  // MARK: - Fetching

  private func fetchUsage(source: UsageAuthSource) async throws -> UsageSnapshot {
    switch source.provider {
    case .claude:
      return try await fetchClaudeUsage(source: source)

    case .codex:
      return try await fetchCodexUsage(source: source)

    case .opencode:
      return try await fetchOpenCodeUsage(source: source)
    }
  }

  // MARK: - Claude Fetching

  private func fetchClaudeUsage(source: UsageAuthSource) async throws -> UsageSnapshot {
    switch source.kind {
    case .cliOAuth:
      return try await fetchClaudeUsageViaOAuth()

    case .apiKey:
      return try await fetchClaudeUsageViaAPIKey()

    case .browser:
      return try await fetchClaudeUsageViaBrowser()

    case .experimental:
      Logger.usage.error("[claude] Experimental source kind is not supported for Claude")
      throw UsageFetchError.unsupportedSource
    }
  }

  /// Reads Claude Code OAuth credentials from macOS Keychain.
  /// Claude Code stores them under service "Claude Code-credentials".
  nonisolated private static func readClaudeCodeKeychainToken() -> (
    token: String, subscriptionType: String?, rateLimitTier: String?
  )? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "Claude Code-credentials",
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]

    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)

    guard status == errSecSuccess,
          let data = result as? Data,
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let oauth = json["claudeAiOauth"] as? [String: Any],
          let token = oauth["accessToken"] as? String,
          !token.isEmpty
    else {
      return nil
    }

    let subType = oauth["subscriptionType"] as? String
    let tier = oauth["rateLimitTier"] as? String
    return (token, subType, tier)
  }

  /// Fetches usage via the Claude Code OAuth token from Keychain.
  /// Calls https://api.anthropic.com/api/oauth/usage for session/weekly limits.
  private func fetchClaudeUsageViaOAuth() async throws -> UsageSnapshot {
    guard let creds = Self.readClaudeCodeKeychainToken() else {
      Logger.usage.error("[claude] No OAuth token found in Keychain (Claude Code-credentials)")
      throw UsageFetchError.noCredentials
    }

    Logger.usage.info(
      "[claude] Keychain OAuth: subscription=\(creds.subscriptionType ?? "nil"), tier=\(creds.rateLimitTier ?? "nil")"
    )

    // Validate token doesn't contain header-injection characters.
    guard !creds.token.contains(where: { $0.isNewline || $0 == "\r" || $0 == "\0" }) else {
      Logger.usage.error("[claude] OAuth token contains invalid characters")
      throw UsageFetchError.invalidCredentials
    }

    guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else {
      throw UsageFetchError.invalidURL
    }

    var request = URLRequest(url: url)
    request.setValue("Bearer \(creds.token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
    request.setValue("SlothyTerminal", forHTTPHeaderField: "User-Agent")

    Logger.usage.info("[claude] Requesting OAuth usage from api.anthropic.com")
    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
      Logger.usage.error("[claude] Non-HTTP response from OAuth usage endpoint")
      throw UsageFetchError.invalidResponse
    }

    Logger.usage.info("[claude] OAuth usage response: HTTP \(httpResponse.statusCode)")

    guard httpResponse.statusCode == 200 else {
      let body = Self.responseBodyPreview(data)
      Logger.usage.error(
        "[claude] OAuth usage failed HTTP \(httpResponse.statusCode): \(body)"
      )
      throw UsageFetchError.httpError(httpResponse.statusCode)
    }

    return Self.parseClaudeOAuthUsageResponse(
      data: data,
      subscriptionType: creds.subscriptionType,
      rateLimitTier: creds.rateLimitTier
    )
  }

  /// Parses the Claude OAuth usage response.
  /// Response has five_hour, seven_day, extra_usage windows.
  nonisolated static func parseClaudeOAuthUsageResponse(
    data: Data,
    subscriptionType: String?,
    rateLimitTier: String?
  ) -> UsageSnapshot {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      Logger.usage.error("[claude] Failed to parse OAuth usage response")
      return UsageSnapshot(
        provider: .claude,
        sourceKind: .cliOAuth,
        sourceLabel: "Claude Code",
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

    var metrics: [UsageMetric] = []

    // Plan from credential metadata.
    if let subType = subscriptionType {
      metrics.append(UsageMetric(
        label: "Plan",
        value: subType.capitalized,
        style: .normal
      ))
    }

    // Session window (five_hour).
    if let fiveHour = json["five_hour"] as? [String: Any] {
      let utilization = Self.normalizeUtilization(fiveHour["utilization"] as? Double ?? 0)
      let resetsAt = fiveHour["resets_at"] as? String
      let resetLabel = resetsAt.flatMap { Self.formatISO8601ResetTime($0) }

      metrics.append(UsageMetric(
        label: "Session (5h)",
        value: "\(Int(utilization))% used",
        style: utilization >= 90 ? .warning : utilization >= 70 ? .cost : .normal
      ))

      if utilization > 0, let resetLabel {
        metrics.append(UsageMetric(
          label: "Session resets",
          value: resetLabel,
          style: .normal
        ))
      }
    }

    // Weekly window (seven_day).
    if let sevenDay = json["seven_day"] as? [String: Any] {
      let utilization = Self.normalizeUtilization(sevenDay["utilization"] as? Double ?? 0)
      let resetsAt = sevenDay["resets_at"] as? String
      let resetLabel = resetsAt.flatMap { Self.formatISO8601ResetTime($0) }

      metrics.append(UsageMetric(
        label: "Weekly (7d)",
        value: "\(Int(utilization))% used",
        style: utilization >= 90 ? .warning : utilization >= 70 ? .cost : .normal
      ))

      if utilization > 0, let resetLabel {
        metrics.append(UsageMetric(
          label: "Weekly resets",
          value: resetLabel,
          style: .normal
        ))
      }
    }

    // Model-specific weekly windows.
    if let sonnet = json["seven_day_sonnet"] as? [String: Any],
       let util = sonnet["utilization"] as? Double,
       util > 0
    {
      metrics.append(UsageMetric(
        label: "Sonnet (7d)",
        value: "\(Int(util))% used",
        style: util >= 90 ? .warning : .normal
      ))
    }

    if let opus = json["seven_day_opus"] as? [String: Any],
       let util = opus["utilization"] as? Double,
       util > 0
    {
      metrics.append(UsageMetric(
        label: "Opus (7d)",
        value: "\(Int(util))% used",
        style: util >= 90 ? .warning : .normal
      ))
    }

    // Extra usage (monthly spend).
    if let extra = json["extra_usage"] as? [String: Any] {
      let isEnabled = extra["is_enabled"] as? Bool ?? false

      if isEnabled {
        let limit = extra["monthly_limit"] as? Double ?? 0
        let used = extra["used_credits"] as? Double ?? 0

        metrics.append(UsageMetric(
          label: "Extra usage",
          value: String(format: "$%.0f / $%.0f", used, limit),
          style: used >= limit ? .warning : .normal
        ))
      }
    }

    // Determine main "used" label from session utilization.
    let sessionUtil = (json["five_hour"] as? [String: Any])?["utilization"] as? Double ?? 0

    return UsageSnapshot(
      provider: .claude,
      sourceKind: .cliOAuth,
      sourceLabel: "Claude Code",
      account: subscriptionType?.capitalized,
      quotaWindow: nil,
      used: "\(Int(sessionUtil))% session",
      limit: nil,
      remaining: nil,
      percentUsed: sessionUtil / 100.0,
      metrics: metrics,
      fetchedAt: Date()
    )
  }

  /// Formats an ISO 8601 reset timestamp to a human-readable "in Xh Ym" string.
  nonisolated private static func formatISO8601ResetTime(_ isoString: String) -> String? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    guard let resetDate = formatter.date(from: isoString) else {
      // Try without fractional seconds.
      formatter.formatOptions = [.withInternetDateTime]

      guard let resetDate = formatter.date(from: isoString) else {
        return nil
      }

      return formatResetDate(resetDate)
    }

    return formatResetDate(resetDate)
  }

  /// Normalizes a utilization value to a 0-100 percentage.
  /// Handles both 0-1 fraction and 0-100 percentage conventions defensively.
  nonisolated private static func normalizeUtilization(_ value: Double) -> Double {
    if value > 0 && value <= 1.0 {
      return value * 100
    }

    return value
  }

  /// Formats a reset Date to "in Xh Ym" relative string.
  nonisolated private static func formatResetDate(_ date: Date) -> String {
    let seconds = Int(date.timeIntervalSinceNow)

    if seconds <= 0 {
      return "now"
    }

    return formatResetTime(seconds)
  }

  /// Fetches usage via the Anthropic admin API (ANTHROPIC_API_KEY).
  /// Fallback for users with API keys but no Claude Code OAuth.
  private func fetchClaudeUsageViaAPIKey() async throws -> UsageSnapshot {
    guard let apiKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] else {
      Logger.usage.error("[claude] ANTHROPIC_API_KEY not set in environment")
      throw UsageFetchError.noCredentials
    }

    guard let orgURL = URL(string: "https://api.anthropic.com/v1/organizations") else {
      throw UsageFetchError.invalidURL
    }

    var orgRequest = URLRequest(url: orgURL)
    orgRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
    orgRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

    Logger.usage.info("[claude] Requesting organizations from Anthropic admin API")
    let (orgData, orgResponse) = try await URLSession.shared.data(for: orgRequest)

    guard let httpResponse = orgResponse as? HTTPURLResponse else {
      Logger.usage.error("[claude] Non-HTTP response from organizations endpoint")
      throw UsageFetchError.invalidResponse
    }

    Logger.usage.info("[claude] Organizations response: HTTP \(httpResponse.statusCode)")

    if httpResponse.statusCode == 403 || httpResponse.statusCode == 401 {
      let body = Self.responseBodyPreview(orgData)
      Logger.usage.warning(
        "[claude] API key lacks admin access (HTTP \(httpResponse.statusCode)): \(body)"
      )
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
          UsageMetric(label: "Status", value: "Admin access required", style: .normal)
        ],
        fetchedAt: Date()
      )
    }

    guard httpResponse.statusCode == 200 else {
      let body = Self.responseBodyPreview(orgData)
      Logger.usage.error(
        "[claude] Organizations failed HTTP \(httpResponse.statusCode): \(body)"
      )
      throw UsageFetchError.httpError(httpResponse.statusCode)
    }

    let orgInfo = try JSONDecoder().decode(
      AnthropicOrganizationsResponse.self, from: orgData
    )

    guard let org = orgInfo.data.first else {
      Logger.usage.error("[claude] No organization found")
      throw UsageFetchError.noOrganization
    }

    return UsageSnapshot(
      provider: .claude,
      sourceKind: .apiKey,
      sourceLabel: "API Key",
      account: org.name,
      quotaWindow: nil,
      used: "Connected",
      limit: nil,
      remaining: nil,
      percentUsed: nil,
      metrics: [
        UsageMetric(label: "Org", value: org.name, style: .normal),
        UsageMetric(label: "Note", value: "Use Claude Code login for session/weekly limits", style: .normal),
      ],
      fetchedAt: Date()
    )
  }

  /// Fetches usage via an imported browser session cookie.
  private func fetchClaudeUsageViaBrowser() async throws -> UsageSnapshot {
    guard let sessionKey = UsageKeychainStore.loadString(
      provider: .claude,
      sourceKind: .browser
    ) else {
      Logger.usage.error("[claude] No browser session key found in Keychain")
      throw UsageFetchError.noCredentials
    }

    let sanitized = sessionKey.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !sanitized.isEmpty,
          !sanitized.contains(where: { $0.isNewline || $0 == "\r" })
    else {
      Logger.usage.error("[claude] Browser session key contains invalid characters")
      throw UsageFetchError.invalidCredentials
    }

    guard let url = URL(string: "https://claude.ai/api/organizations") else {
      throw UsageFetchError.invalidURL
    }

    var request = URLRequest(url: url)
    request.setValue("sessionKey=\(sanitized)", forHTTPHeaderField: "Cookie")
    request.setValue("application/json", forHTTPHeaderField: "Accept")

    Logger.usage.info("[claude] Requesting organizations via browser session")
    let (responseData, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw UsageFetchError.invalidResponse
    }

    Logger.usage.info("[claude] Browser session response: HTTP \(httpResponse.statusCode)")

    guard httpResponse.statusCode == 200 else {
      let body = Self.responseBodyPreview(responseData)
      Logger.usage.error(
        "[claude] Browser session failed HTTP \(httpResponse.statusCode): \(body)"
      )
      throw UsageFetchError.httpError(httpResponse.statusCode)
    }

    return Self.parseClaudeConsoleOrgsResponse(
      data: responseData, sourceKind: .browser
    )
  }

  // MARK: - Codex Fetching

  private func fetchCodexUsage(source: UsageAuthSource) async throws -> UsageSnapshot {
    let credential = try resolveCodexCredential(source: source)

    switch credential {
    case .apiKey(let key):
      return try await fetchCodexUsageWithKey(key)

    case .oauthToken(let token):
      return try await fetchCodexUsageWithOAuthToken(token)
    }
  }

  /// Resolved credential for Codex — either a plain API key or an OAuth token.
  private enum CodexCredential {
    case apiKey(String)
    case oauthToken(String)
  }

  /// Extracts a usable credential from the resolved auth source.
  private func resolveCodexCredential(source: UsageAuthSource) throws -> CodexCredential {
    switch source.kind {
    case .apiKey:
      guard let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"],
            !key.isEmpty
      else {
        Logger.usage.error("[codex] OPENAI_API_KEY not set in environment")
        throw UsageFetchError.noCredentials
      }

      return .apiKey(key)

    case .cliOAuth:
      return try readCodexCLICredential()

    case .browser:
      guard let key = UsageKeychainStore.loadString(
        provider: .codex,
        sourceKind: .browser
      ) else {
        Logger.usage.error("[codex] No browser session key found in Keychain")
        throw UsageFetchError.noCredentials
      }

      return .apiKey(key)

    case .experimental:
      Logger.usage.error("[codex] Experimental source kind is not supported for Codex")
      throw UsageFetchError.unsupportedSource
    }
  }

  /// Reads a credential from Codex CLI auth files.
  /// Supports two auth modes:
  /// - API key mode: `OPENAI_API_KEY` is a string
  /// - ChatGPT OAuth mode: `tokens.access_token` holds a JWT Bearer token
  private func readCodexCLICredential() throws -> CodexCredential {
    var credData: Data?
    var credPath: String?
    for path in Self.codexCredentialPaths {
      if let data = FileManager.default.contents(atPath: path) {
        credData = data
        credPath = path
        break
      }
    }

    guard let data = credData else {
      Logger.usage.error("[codex] No CLI credential file found at known paths")
      throw UsageFetchError.noCredentials
    }

    Logger.usage.info("[codex] Reading CLI credentials from \(credPath ?? "unknown")")

    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      Logger.usage.error("[codex] CLI credential file is not valid JSON")
      throw UsageFetchError.invalidCredentials
    }

    let authMode = json["auth_mode"] as? String ?? "unknown"
    Logger.usage.debug(
      "[codex] Credential file auth_mode=\(authMode)"
    )

    // 1. Check for a direct API key (non-null string).
    if let apiKey = json["OPENAI_API_KEY"] as? String,
       !apiKey.isEmpty
    {
      Logger.usage.info("[codex] Found OPENAI_API_KEY in credential file")
      return .apiKey(apiKey)
    }

    if let apiKey = json["api_key"] as? String ?? json["apiKey"] as? String,
       !apiKey.isEmpty
    {
      Logger.usage.info("[codex] Found api_key in credential file")
      return .apiKey(apiKey)
    }

    // 2. Check for ChatGPT OAuth tokens (tokens.access_token).
    if let tokens = json["tokens"] as? [String: Any] {
      Logger.usage.debug("[codex] Found tokens dict in credential file")

      if let accessToken = tokens["access_token"] as? String,
         !accessToken.isEmpty
      {
        Logger.usage.info("[codex] Using tokens.access_token (OAuth mode)")
        return .oauthToken(accessToken)
      }
    }

    // 3. Fallback: any token-like field at top level.
    if let token = json["token"] as? String ?? json["access_token"] as? String,
       !token.isEmpty
    {
      Logger.usage.info("[codex] Found top-level token field")
      return .oauthToken(token)
    }

    Logger.usage.error(
      "[codex] No usable credential found in CLI file (tried OPENAI_API_KEY, api_key, apiKey, tokens.access_token, token, access_token)"
    )
    throw UsageFetchError.noCredentials
  }

  /// Fetches Codex usage with a ChatGPT OAuth access token.
  /// Uses /backend-api/wham/usage for rate limits and plan info.
  private func fetchCodexUsageWithOAuthToken(
    _ token: String
  ) async throws -> UsageSnapshot {
    // Validate token doesn't contain header-injection characters.
    guard !token.contains(where: { $0.isNewline || $0 == "\r" || $0 == "\0" }) else {
      Logger.usage.error("[codex] OAuth token contains invalid characters")
      throw UsageFetchError.invalidCredentials
    }

    // Read account_id from the credential file for the header.
    let accountId = Self.readCodexAccountId()

    guard let url = URL(string: "https://chatgpt.com/backend-api/wham/usage") else {
      throw UsageFetchError.invalidURL
    }

    var request = URLRequest(url: url)
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("SlothyTerminal", forHTTPHeaderField: "User-Agent")

    if let accountId,
       !accountId.contains(where: { $0.isNewline || $0 == "\r" || $0 == "\0" })
    {
      request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
    }

    Logger.usage.info("[codex] Requesting wham/usage from ChatGPT backend API")
    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
      Logger.usage.error("[codex] Non-HTTP response from wham/usage")
      throw UsageFetchError.invalidResponse
    }

    Logger.usage.info("[codex] wham/usage response: HTTP \(httpResponse.statusCode)")

    guard httpResponse.statusCode == 200 else {
      let body = Self.responseBodyPreview(data)
      Logger.usage.error(
        "[codex] wham/usage failed HTTP \(httpResponse.statusCode): \(body)"
      )
      throw UsageFetchError.httpError(httpResponse.statusCode)
    }

    return Self.parseWhamUsageResponse(data: data)
  }

  /// Reads the account_id from the Codex auth file for the ChatGPT-Account-Id header.
  nonisolated private static func readCodexAccountId() -> String? {
    for path in codexCredentialPaths {
      guard let data = FileManager.default.contents(atPath: path),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let tokens = json["tokens"] as? [String: Any],
            let accountId = tokens["account_id"] as? String
      else {
        continue
      }

      return accountId
    }

    return nil
  }

  /// Parses the ChatGPT /backend-api/wham/usage response.
  nonisolated static func parseWhamUsageResponse(data: Data) -> UsageSnapshot {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      Logger.usage.error("[codex] Failed to parse wham/usage response")
      return UsageSnapshot(
        provider: .codex,
        sourceKind: .cliOAuth,
        sourceLabel: "CLI Auth",
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

    let email = json["email"] as? String
    let planType = json["plan_type"] as? String
    var metrics: [UsageMetric] = []

    // Plan type.
    if let planType {
      metrics.append(UsageMetric(
        label: "Plan",
        value: planType.capitalized,
        style: .normal
      ))
    }

    // Primary rate limit (session window — typically 5 hours).
    if let rateLimit = json["rate_limit"] as? [String: Any] {
      let limitReached = rateLimit["limit_reached"] as? Bool ?? false

      if limitReached {
        metrics.append(UsageMetric(
          label: "Status",
          value: "Rate limit reached",
          style: .warning
        ))
      }

      if let primary = rateLimit["primary_window"] as? [String: Any] {
        let usedPercent = primary["used_percent"] as? Int ?? 0
        let windowSeconds = primary["limit_window_seconds"] as? Int ?? 0
        let resetAfter = primary["reset_after_seconds"] as? Int ?? 0

        let windowLabel = Self.formatWindowDuration(windowSeconds)
        let resetLabel = Self.formatResetTime(resetAfter)

        metrics.append(UsageMetric(
          label: "Session (\(windowLabel))",
          value: "\(usedPercent)% used",
          style: usedPercent >= 90 ? .warning : usedPercent >= 70 ? .cost : .normal
        ))

        if usedPercent > 0 {
          metrics.append(UsageMetric(
            label: "Session resets",
            value: resetLabel,
            style: .normal
          ))
        }
      }

      if let secondary = rateLimit["secondary_window"] as? [String: Any] {
        let usedPercent = secondary["used_percent"] as? Int ?? 0
        let windowSeconds = secondary["limit_window_seconds"] as? Int ?? 0
        let resetAfter = secondary["reset_after_seconds"] as? Int ?? 0

        let windowLabel = Self.formatWindowDuration(windowSeconds)
        let resetLabel = Self.formatResetTime(resetAfter)

        metrics.append(UsageMetric(
          label: "Weekly (\(windowLabel))",
          value: "\(usedPercent)% used",
          style: usedPercent >= 90 ? .warning : usedPercent >= 70 ? .cost : .normal
        ))

        if usedPercent > 0 {
          metrics.append(UsageMetric(
            label: "Weekly resets",
            value: resetLabel,
            style: .normal
          ))
        }
      }
    }

    // Credits.
    if let credits = json["credits"] as? [String: Any] {
      let hasCredits = credits["has_credits"] as? Bool ?? false
      let unlimited = credits["unlimited"] as? Bool ?? false

      if unlimited {
        metrics.append(UsageMetric(
          label: "Credits",
          value: "Unlimited",
          style: .normal
        ))
      } else if hasCredits,
                let balance = credits["balance"] as? String,
                let balanceNum = Double(balance),
                balanceNum > 0
      {
        metrics.append(UsageMetric(
          label: "Credits",
          value: String(format: "$%.2f", balanceNum),
          style: .normal
        ))
      }
    }

    // Determine the main "used" label from session usage.
    let sessionPercent = (json["rate_limit"] as? [String: Any])?["primary_window"]
      .flatMap { ($0 as? [String: Any])?["used_percent"] as? Int } ?? 0

    return UsageSnapshot(
      provider: .codex,
      sourceKind: .cliOAuth,
      sourceLabel: "CLI Auth",
      account: email,
      quotaWindow: nil,
      used: "\(sessionPercent)% session",
      limit: nil,
      remaining: nil,
      percentUsed: Double(sessionPercent) / 100.0,
      metrics: metrics,
      fetchedAt: Date()
    )
  }

  /// Formats a window duration in seconds to a human-readable label.
  nonisolated private static func formatWindowDuration(_ seconds: Int) -> String {
    if seconds >= 86400 {
      let days = seconds / 86400
      return days == 7 ? "7d" : "\(days)d"
    } else if seconds >= 3600 {
      return "\(seconds / 3600)h"
    } else if seconds >= 60 {
      return "\(seconds / 60)m"
    }

    return "\(seconds)s"
  }

  /// Formats a reset-after-seconds value to a human-readable string.
  nonisolated private static func formatResetTime(_ seconds: Int) -> String {
    if seconds <= 0 {
      return "now"
    }

    let hours = seconds / 3600
    let minutes = (seconds % 3600) / 60

    if hours >= 24 {
      let days = hours / 24
      let remainingHours = hours % 24
      if remainingHours > 0 {
        return "in \(days)d \(remainingHours)h"
      }

      return "in \(days)d"
    }

    if hours > 0 {
      if minutes > 0 {
        return "in \(hours)h \(minutes)m"
      }

      return "in \(hours)h"
    }

    return "in \(minutes)m"
  }

  /// Fetches Codex usage with a resolved OpenAI API key.
  private func fetchCodexUsageWithKey(_ apiKey: String) async throws -> UsageSnapshot {
    guard let orgURL = URL(string: "https://api.openai.com/v1/organization") else {
      throw UsageFetchError.invalidURL
    }

    var orgRequest = URLRequest(url: orgURL)
    orgRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

    Logger.usage.info("[codex] Requesting organization from OpenAI API")
    let (orgData, orgResponse) = try await URLSession.shared.data(for: orgRequest)

    guard let httpResponse = orgResponse as? HTTPURLResponse else {
      Logger.usage.error("[codex] Non-HTTP response from organization endpoint")
      throw UsageFetchError.invalidResponse
    }

    Logger.usage.info("[codex] Organization response: HTTP \(httpResponse.statusCode)")

    // If admin access is required, return a limited snapshot.
    if httpResponse.statusCode == 403 || httpResponse.statusCode == 401 {
      let body = Self.responseBodyPreview(orgData)
      Logger.usage.warning(
        "[codex] API key lacks admin access (HTTP \(httpResponse.statusCode)): \(body)"
      )
      return UsageSnapshot(
        provider: .codex,
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
      let body = Self.responseBodyPreview(orgData)
      Logger.usage.error(
        "[codex] Organization request failed HTTP \(httpResponse.statusCode): \(body)"
      )
      throw UsageFetchError.httpError(httpResponse.statusCode)
    }

    return Self.parseCodexOrgResponse(data: orgData)
  }

  // MARK: - OpenCode Fetching

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
      Logger.usage.error("[claude] Failed to parse usage response as JSON")
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
      Logger.usage.error("[claude] Failed to parse console orgs response")
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

  /// Parses the OpenAI organization response into a usage snapshot.
  nonisolated static func parseCodexOrgResponse(data: Data) -> UsageSnapshot {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      Logger.usage.error("[codex] Failed to parse organization response as JSON")
      return UsageSnapshot(
        provider: .codex,
        sourceKind: .apiKey,
        sourceLabel: "API Key",
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

    Logger.usage.info(
      "[codex] Parsed org response keys: \(json.keys.sorted().joined(separator: ", "))"
    )

    let orgName = json["name"] as? String
      ?? json["title"] as? String
    var metrics: [UsageMetric] = []

    if let plan = json["plan"] as? String ?? json["tier"] as? String {
      metrics.append(UsageMetric(
        label: "Plan",
        value: plan.capitalized,
        style: .normal
      ))
    }

    if let hardLimit = json["hard_limit_usd"] as? Double {
      metrics.append(UsageMetric(
        label: "Hard limit",
        value: String(format: "$%.2f", hardLimit),
        style: .normal
      ))
    }

    return UsageSnapshot(
      provider: .codex,
      sourceKind: .apiKey,
      sourceLabel: "API Key",
      account: orgName,
      quotaWindow: nil,
      used: metrics.isEmpty ? "Connected" : metrics.first?.value ?? "Connected",
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
    // Cancel only existing refresh tasks, not the startup task.
    for (_, task) in refreshTasks {
      task.cancel()
    }
    refreshTasks.removeAll()

    // Minimum 30s to prevent abusive refresh from corrupted config.
    // 0 means manual-only.
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

  /// Returns a safe summary of a response body for logging.
  /// Only logs HTTP status-relevant info — never raw bodies that could contain tokens.
  nonisolated private static func responseBodyPreview(_ data: Data) -> String {
    guard String(data: data, encoding: .utf8) != nil else {
      return "<non-UTF8 \(data.count) bytes>"
    }

    // Only extract error type/message fields from JSON error responses.
    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
      if let error = json["error"] as? [String: Any] {
        let type = error["type"] as? String ?? "unknown"
        let message = error["message"] as? String ?? ""
        let safeMessage = String(message.prefix(200))
        return "error: \(type) — \(safeMessage)"
      }

      if let detail = json["detail"] as? String {
        return "detail: \(String(detail.prefix(200)))"
      }
    }

    return "\(data.count) bytes"
  }

}
