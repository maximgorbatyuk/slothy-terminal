import XCTest
@testable import SlothyTerminalLib

final class UsageModelsTests: XCTestCase {

  // MARK: - Model Types

  func testUsageSourceKindIsOfficial() {
    XCTAssertTrue(UsageSourceKind.apiKey.isOfficial)
    XCTAssertTrue(UsageSourceKind.cliOAuth.isOfficial)
    XCTAssertFalse(UsageSourceKind.browser.isOfficial)
    XCTAssertFalse(UsageSourceKind.experimental.isOfficial)
  }

  func testUsageSourceKindDisplayName() {
    XCTAssertEqual(UsageSourceKind.apiKey.displayName, "API Key")
    XCTAssertEqual(UsageSourceKind.cliOAuth.displayName, "CLI Auth")
    XCTAssertEqual(UsageSourceKind.browser.displayName, "Browser")
    XCTAssertEqual(UsageSourceKind.experimental.displayName, "Experimental")
  }

  func testUsageProviderDisplayName() {
    XCTAssertEqual(UsageProvider.claude.displayName, "Claude")
    XCTAssertEqual(UsageProvider.codex.displayName, "Codex")
    XCTAssertEqual(UsageProvider.opencode.displayName, "OpenCode")
  }

  func testUsageStatusBarProviders() {
    XCTAssertEqual(UsageProvider.statusBarProviders, [.claude, .codex, .cursor, .minimax])
  }

  func testUsageAuthSourceExperimental() {
    let official = UsageAuthSource(
      provider: .claude, kind: .apiKey, label: "API Key", detail: nil
    )
    XCTAssertFalse(official.isExperimental)

    let cliAuth = UsageAuthSource(
      provider: .claude, kind: .cliOAuth, label: "CLI", detail: nil
    )
    XCTAssertFalse(cliAuth.isExperimental)

    let browser = UsageAuthSource(
      provider: .claude, kind: .browser, label: "Browser", detail: nil
    )
    XCTAssertTrue(browser.isExperimental)

    let experimental = UsageAuthSource(
      provider: .opencode, kind: .experimental, label: "Exp", detail: nil
    )
    XCTAssertTrue(experimental.isExperimental)
  }

  func testUsageFetchStatusEquality() {
    XCTAssertEqual(UsageFetchStatus.idle, UsageFetchStatus.idle)
    XCTAssertEqual(UsageFetchStatus.loading, UsageFetchStatus.loading)
    XCTAssertEqual(
      UsageFetchStatus.failed("error"),
      UsageFetchStatus.failed("error")
    )
    XCTAssertNotEqual(
      UsageFetchStatus.failed("a"),
      UsageFetchStatus.failed("b")
    )
    XCTAssertNotEqual(UsageFetchStatus.idle, UsageFetchStatus.loading)
    XCTAssertEqual(
      UsageFetchStatus.unavailable("reason"),
      UsageFetchStatus.unavailable("reason")
    )
    XCTAssertEqual(UsageFetchStatus.tokenExpired, UsageFetchStatus.tokenExpired)
    XCTAssertNotEqual(UsageFetchStatus.tokenExpired, UsageFetchStatus.idle)
  }

  func testUsageMetricEquality() {
    let a = UsageMetric(label: "Test", value: "100", style: .normal)
    let b = UsageMetric(label: "Test", value: "100", style: .normal)
    let c = UsageMetric(label: "Test", value: "200", style: .normal)
    let d = UsageMetric(label: "Test", value: "100", style: .highlighted)

    XCTAssertEqual(a, b)
    XCTAssertNotEqual(a, c)
    XCTAssertNotEqual(a, d)
  }

  func testUsageMetricIdentity() {
    let a = UsageMetric(label: "Tokens", value: "1K")
    let b = UsageMetric(label: "Tokens", value: "1K")

    // Each instance gets a unique ID for SwiftUI diffing.
    XCTAssertNotEqual(a.id, b.id)
  }

  // MARK: - Preferences

  func testUsagePreferencesCoding() throws {
    let prefs = UsagePreferences(
      isEnabled: true,
      enableExperimentalSources: true,
      refreshIntervalSeconds: 600
    )

    let data = try JSONEncoder().encode(prefs)
    let decoded = try JSONDecoder().decode(UsagePreferences.self, from: data)

    XCTAssertEqual(decoded, prefs)
  }

  func testUsagePreferencesDefaults() {
    let prefs = UsagePreferences()

    XCTAssertFalse(prefs.isEnabled)
    XCTAssertFalse(prefs.enableExperimentalSources)
    XCTAssertEqual(prefs.refreshIntervalSeconds, 300)
    XCTAssertEqual(prefs.refreshInterval, 300.0)
  }

  func testUsagePreferencesRefreshInterval() {
    var prefs = UsagePreferences()
    prefs.refreshIntervalSeconds = 60

    XCTAssertEqual(prefs.refreshInterval, 60.0)
  }


  // MARK: - Error Descriptions

  func testUsageFetchErrorDescriptions() {
    XCTAssertEqual(
      UsageFetchError.httpError(403).errorDescription,
      "HTTP error 403"
    )
    XCTAssertEqual(
      UsageFetchError.noCredentials.errorDescription,
      "No credentials found"
    )
    XCTAssertEqual(
      UsageFetchError.invalidCredentials.errorDescription,
      "Invalid credentials format"
    )
    XCTAssertEqual(
      UsageFetchError.invalidURL.errorDescription,
      "Invalid API URL"
    )
    XCTAssertEqual(
      UsageFetchError.invalidResponse.errorDescription,
      "Invalid API response"
    )
    XCTAssertEqual(
      UsageFetchError.noOrganization.errorDescription,
      "No organization found"
    )
    XCTAssertEqual(
      UsageFetchError.parseError.errorDescription,
      "Failed to parse response"
    )
    XCTAssertEqual(
      UsageFetchError.unsupportedSource.errorDescription,
      "Unsupported auth source"
    )
    XCTAssertEqual(
      UsageFetchError.tokenExpired.errorDescription,
      "OAuth token expired"
    )
  }

  // MARK: - Token Formatting

  func testFormatTokenCountSmall() {
    XCTAssertEqual(UsageService.formatTokenCount(0), "0")
    XCTAssertEqual(UsageService.formatTokenCount(1), "1")
    XCTAssertEqual(UsageService.formatTokenCount(500), "500")
    XCTAssertEqual(UsageService.formatTokenCount(999), "999")
  }

  func testFormatTokenCountThousands() {
    XCTAssertEqual(UsageService.formatTokenCount(1_000), "1.0K")
    XCTAssertEqual(UsageService.formatTokenCount(1_500), "1.5K")
    XCTAssertEqual(UsageService.formatTokenCount(10_000), "10.0K")
    XCTAssertEqual(UsageService.formatTokenCount(999_999), "1000.0K")
  }

  func testFormatTokenCountMillions() {
    XCTAssertEqual(UsageService.formatTokenCount(1_000_000), "1.0M")
    XCTAssertEqual(UsageService.formatTokenCount(2_500_000), "2.5M")
    XCTAssertEqual(UsageService.formatTokenCount(100_000_000), "100.0M")
  }

  func testFormatTokenCountBillions() {
    XCTAssertEqual(UsageService.formatTokenCount(1_000_000_000), "1.0B")
    XCTAssertEqual(UsageService.formatTokenCount(3_700_000_000), "3.7B")
  }

  // MARK: - Provider Mapping

  func testProviderMapping() {
    XCTAssertEqual(UsageService.provider(for: .claude), .claude)
    XCTAssertEqual(UsageService.provider(for: .opencode), .opencode)
    XCTAssertNil(UsageService.provider(for: .terminal))
  }

  // MARK: - Response Parsing

  func testParseAnthropicUsageResponse() {
    let json: [String: Any] = [
      "data": [
        ["input_tokens": 1000, "output_tokens": 500],
        ["input_tokens": 2000, "output_tokens": 1500],
      ]
    ]
    let data = try! JSONSerialization.data(withJSONObject: json)

    let snapshot = UsageService.parseAnthropicUsageResponse(
      data: data, orgName: "Test Org"
    )

    XCTAssertEqual(snapshot.provider, .claude)
    XCTAssertEqual(snapshot.sourceKind, .apiKey)
    XCTAssertEqual(snapshot.account, "Test Org")
    XCTAssertEqual(snapshot.used, "5.0K")
    XCTAssertEqual(snapshot.metrics.count, 2)
    XCTAssertEqual(snapshot.metrics[0].label, "Input tokens")
    XCTAssertEqual(snapshot.metrics[0].value, "3.0K")
    XCTAssertEqual(snapshot.metrics[1].label, "Output tokens")
    XCTAssertEqual(snapshot.metrics[1].value, "2.0K")
  }

  func testParseAnthropicUsageResponseEmpty() {
    let json: [String: Any] = ["data": [] as [[String: Any]]]
    let data = try! JSONSerialization.data(withJSONObject: json)

    let snapshot = UsageService.parseAnthropicUsageResponse(
      data: data, orgName: "Empty Org"
    )

    XCTAssertEqual(snapshot.used, "0")
    XCTAssertTrue(snapshot.metrics.isEmpty)
    XCTAssertEqual(snapshot.account, "Empty Org")
  }

  func testParseAnthropicUsageResponseInvalidJSON() {
    let data = "not json".data(using: .utf8)!

    let snapshot = UsageService.parseAnthropicUsageResponse(
      data: data, orgName: "Bad"
    )

    XCTAssertEqual(snapshot.used, "Parse error")
    XCTAssertEqual(snapshot.account, "Bad")
  }

  func testParseClaudeConsoleOrgsResponse() {
    let json: [[String: Any]] = [
      [
        "name": "Personal",
        "billing_plan": "pro",
        "rate_limits": [
          "message_limit": 100,
          "messages_used": 42,
        ],
      ]
    ]
    let data = try! JSONSerialization.data(withJSONObject: json)

    let snapshot = UsageService.parseClaudeConsoleOrgsResponse(
      data: data, sourceKind: .cliOAuth
    )

    XCTAssertEqual(snapshot.provider, .claude)
    XCTAssertEqual(snapshot.sourceKind, .cliOAuth)
    XCTAssertEqual(snapshot.account, "Personal")
    XCTAssertEqual(snapshot.used, "42")
    XCTAssertEqual(snapshot.metrics.count, 3)

    /// Verify individual metrics.
    XCTAssertEqual(snapshot.metrics[0].label, "Message limit")
    XCTAssertEqual(snapshot.metrics[0].value, "100")
    XCTAssertEqual(snapshot.metrics[1].label, "Messages used")
    XCTAssertEqual(snapshot.metrics[1].value, "42")
    XCTAssertEqual(snapshot.metrics[1].style, .highlighted)
    XCTAssertEqual(snapshot.metrics[2].label, "Plan")
    XCTAssertEqual(snapshot.metrics[2].value, "Pro")
  }

  func testParseClaudeConsoleOrgsResponseNoRateLimits() {
    let json: [[String: Any]] = [
      ["name": "Simple Org"]
    ]
    let data = try! JSONSerialization.data(withJSONObject: json)

    let snapshot = UsageService.parseClaudeConsoleOrgsResponse(
      data: data, sourceKind: .browser
    )

    XCTAssertEqual(snapshot.sourceKind, .browser)
    XCTAssertEqual(snapshot.account, "Simple Org")
    XCTAssertEqual(snapshot.used, "Connected")
    XCTAssertTrue(snapshot.metrics.isEmpty)
  }

  func testParseClaudeConsoleOrgsResponseInvalidJSON() {
    let data = "invalid".data(using: .utf8)!

    let snapshot = UsageService.parseClaudeConsoleOrgsResponse(
      data: data, sourceKind: .cliOAuth
    )

    XCTAssertEqual(snapshot.used, "Parse error")
    XCTAssertNil(snapshot.account)
  }

  // MARK: - Snapshot Equality

  func testUsageSnapshotEquality() {
    let date = Date()

    let a = UsageSnapshot(
      provider: .claude,
      sourceKind: .apiKey,
      sourceLabel: "API Key",
      account: "Test",
      quotaWindow: nil,
      used: "1K",
      limit: nil,
      remaining: nil,
      percentUsed: nil,
      metrics: [],
      fetchedAt: date
    )

    let b = UsageSnapshot(
      provider: .claude,
      sourceKind: .apiKey,
      sourceLabel: "API Key",
      account: "Test",
      quotaWindow: nil,
      used: "1K",
      limit: nil,
      remaining: nil,
      percentUsed: nil,
      metrics: [],
      fetchedAt: date
    )

    XCTAssertEqual(a, b)
  }

  // MARK: - API Response Models

  func testAnthropicOrganizationsResponseDecoding() throws {
    let json = """
    {
      "data": [
        {"id": "org-123", "name": "My Org"}
      ]
    }
    """
    let data = json.data(using: .utf8)!
    let response = try JSONDecoder().decode(
      AnthropicOrganizationsResponse.self, from: data
    )

    XCTAssertEqual(response.data.count, 1)
    XCTAssertEqual(response.data[0].id, "org-123")
    XCTAssertEqual(response.data[0].name, "My Org")
  }

  // MARK: - mergedClaudeWindow

  /// Regression: Anthropic returns utilization as a 0-100 percentage. A value
  /// of `1` means 1% used — not 100%. An earlier "defensive" normalization
  /// step multiplied any value in (0, 1] by 100, which broke the 1% case.
  func testMergedClaudeWindowReturnsRawPercentage() throws {
    // Mirrors the payload from https://github.com/maximgorbatyuk/slothy-terminal/issues/12:
    // Anthropic returns utilization as an already-scaled 0-100 percentage, so
    // `utilization: 1` is 1% — not 100%.
    let raw = """
    {
      "five_hour": {
        "resets_at": "2026-05-11T14:10:00.489581+00:00",
        "utilization": 1
      },
      "seven_day": {
        "resets_at": "2026-05-16T05:00:00.489601+00:00",
        "utilization": 7
      }
    }
    """
    let data = raw.data(using: .utf8)!
    let json = try XCTUnwrap(
      JSONSerialization.jsonObject(with: data) as? [String: Any]
    )

    let fiveHour = UsageService.mergedClaudeWindow(json, baseKey: "five_hour")
    let sevenDay = UsageService.mergedClaudeWindow(json, baseKey: "seven_day")

    XCTAssertEqual(fiveHour?.utilization, 1)
    XCTAssertEqual(sevenDay?.utilization, 7)
  }

  func testMergedClaudeWindowZeroUtilization() throws {
    let raw = """
    {
      "seven_day_sonnet": {
        "resets_at": null,
        "utilization": 0
      }
    }
    """
    let data = raw.data(using: .utf8)!
    let json = try XCTUnwrap(
      JSONSerialization.jsonObject(with: data) as? [String: Any]
    )

    let window = UsageService.mergedClaudeWindow(json, baseKey: "seven_day_sonnet")
    XCTAssertEqual(window?.utilization, 0)
  }

  // MARK: - MinimaxUsageProvider

  func testMinimaxParseHeadlineSnapshot() throws {
    let payload = """
    {
      "model_remains": [
        {
          "start_time": 1778821200000,
          "end_time": 1778839200000,
          "remains_time": 15395586,
          "current_interval_total_count": 4500,
          "current_interval_usage_count": 4462,
          "model_name": "MiniMax-M*",
          "current_weekly_total_count": 45000,
          "current_weekly_usage_count": 44954,
          "weekly_start_time": 1778457600000,
          "weekly_end_time": 1779062400000,
          "weekly_remains_time": 238595586
        },
        {
          "start_time": 1778803200000,
          "end_time": 1778889600000,
          "remains_time": 65795584,
          "current_interval_total_count": 4000,
          "current_interval_usage_count": 4000,
          "model_name": "speech-hd",
          "current_weekly_total_count": 28000,
          "current_weekly_usage_count": 28000,
          "weekly_start_time": 1778457600000,
          "weekly_end_time": 1779062400000,
          "weekly_remains_time": 238595584
        },
        {
          "start_time": 1778821200000,
          "end_time": 1778839200000,
          "remains_time": 15395540,
          "current_interval_total_count": 4500,
          "current_interval_usage_count": 4462,
          "model_name": "coding-plan-vlm",
          "current_weekly_total_count": 45000,
          "current_weekly_usage_count": 44954,
          "weekly_start_time": 1778457600000,
          "weekly_end_time": 1779062400000,
          "weekly_remains_time": 238595540
        }
      ],
      "base_resp": { "status_code": 0, "status_msg": "success" }
    }
    """.data(using: .utf8)!

    let snapshot = try MinimaxUsageProvider.parseSnapshot(data: payload)

    XCTAssertEqual(snapshot.provider, .minimax)
    XCTAssertEqual(snapshot.account, "MiniMax-M*")
    XCTAssertEqual(snapshot.used, "4462")
    XCTAssertEqual(snapshot.limit, "4500")
    XCTAssertEqual(snapshot.remaining, "38")
    XCTAssertNotNil(snapshot.percentUsed)
    XCTAssertEqual(snapshot.percentUsed ?? 0, 0.9915555, accuracy: 0.0001)

    XCTAssertFalse(snapshot.metrics.contains { $0.label == "coding-plan-vlm" })

    XCTAssertTrue(snapshot.metrics.contains { $0.label == "speech-hd" })

    XCTAssertTrue(snapshot.metrics.contains { $0.label == "Weekly used" })
  }

  func testMinimaxParseRejectsErrorStatus() {
    let payload = """
    {
      "model_remains": [],
      "base_resp": { "status_code": 1004, "status_msg": "invalid api key" }
    }
    """.data(using: .utf8)!

    do {
      try MinimaxUsageProvider.parseSnapshot(data: payload)
      XCTFail("Expected parseError to be thrown")
    } catch UsageFetchError.parseError {
      // Expected
    } catch {
      XCTFail("Expected parseError but got \(error)")
    }
  }
}
