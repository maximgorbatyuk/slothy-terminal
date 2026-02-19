import XCTest

@testable import SlothyTerminalLib

final class LaunchTypeTests: XCTestCase {

  // MARK: - Metadata Tests

  func testAllCasesCount() {
    XCTAssertEqual(LaunchType.allCases.count, 6)
  }

  func testDisplayNames() {
    XCTAssertEqual(LaunchType.terminal.displayName, "Terminal")
    XCTAssertEqual(LaunchType.claudeChat.displayName, "Claude Chat")
    XCTAssertEqual(LaunchType.opencodeChat.displayName, "OpenCode Chat")
    XCTAssertEqual(LaunchType.claudeDesktop.displayName, "Claude Desktop")
    XCTAssertEqual(LaunchType.codexDesktop.displayName, "Codex Desktop")
    XCTAssertEqual(LaunchType.telegramBot.displayName, "Telegram Bot")
  }

  func testSubtitlesAreNonEmpty() {
    for launchType in LaunchType.allCases {
      XCTAssertFalse(
        launchType.subtitle.isEmpty,
        "\(launchType) should have a non-empty subtitle"
      )
    }
  }

  func testIconNamesAreNonEmpty() {
    for launchType in LaunchType.allCases {
      XCTAssertFalse(
        launchType.iconName.isEmpty,
        "\(launchType) should have a non-empty iconName"
      )
    }
  }

  func testRequiresPrompt() {
    XCTAssertTrue(LaunchType.terminal.requiresPrompt)
    XCTAssertTrue(LaunchType.claudeChat.requiresPrompt)
    XCTAssertTrue(LaunchType.opencodeChat.requiresPrompt)
    XCTAssertTrue(LaunchType.claudeDesktop.requiresPrompt)
    XCTAssertTrue(LaunchType.codexDesktop.requiresPrompt)
    XCTAssertFalse(LaunchType.telegramBot.requiresPrompt)
  }

  func testAgentTypeMapping() {
    XCTAssertEqual(LaunchType.terminal.agentType, .terminal)
    XCTAssertEqual(LaunchType.claudeChat.agentType, .claude)
    XCTAssertEqual(LaunchType.opencodeChat.agentType, .opencode)
    XCTAssertEqual(LaunchType.claudeDesktop.agentType, .claude)
    XCTAssertNil(LaunchType.codexDesktop.agentType)
    XCTAssertNil(LaunchType.telegramBot.agentType)
  }

  func testIdentifiable() {
    /// Each case should have a unique id.
    let ids = Set(LaunchType.allCases.map(\.id))
    XCTAssertEqual(ids.count, LaunchType.allCases.count)
  }

  // MARK: - Codable Tests

  func testCodableRoundTrip() throws {
    for launchType in LaunchType.allCases {
      let encoded = try JSONEncoder().encode(launchType)
      let decoded = try JSONDecoder().decode(LaunchType.self, from: encoded)
      XCTAssertEqual(decoded, launchType)
    }
  }

  func testRawValues() {
    XCTAssertEqual(LaunchType.terminal.rawValue, "terminal")
    XCTAssertEqual(LaunchType.claudeChat.rawValue, "claudeChat")
    XCTAssertEqual(LaunchType.opencodeChat.rawValue, "opencodeChat")
    XCTAssertEqual(LaunchType.claudeDesktop.rawValue, "claudeDesktop")
    XCTAssertEqual(LaunchType.codexDesktop.rawValue, "codexDesktop")
    XCTAssertEqual(LaunchType.telegramBot.rawValue, "telegramBot")
  }

  // MARK: - Config Persistence Tests

  func testAppConfigLastUsedLaunchTypeEncoding() throws {
    var config = AppConfig.default
    config.lastUsedLaunchType = .opencodeChat

    let encoded = try JSONEncoder().encode(config)
    let decoded = try JSONDecoder().decode(AppConfig.self, from: encoded)

    XCTAssertEqual(decoded.lastUsedLaunchType, .opencodeChat)
  }

  func testAppConfigLastUsedLaunchTypeNilByDefault() throws {
    let config = AppConfig.default
    XCTAssertNil(config.lastUsedLaunchType)
  }

  func testAppConfigBackwardCompatibleWithoutLaunchType() throws {
    /// Encode a full config with lastUsedLaunchType set, then remove it from
    /// the JSON to simulate a config saved before the field existed.
    var config = AppConfig.default
    config.lastUsedLaunchType = .claudeChat

    let encoded = try JSONEncoder().encode(config)
    var dict = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
    dict.removeValue(forKey: "lastUsedLaunchType")

    let modifiedData = try JSONSerialization.data(withJSONObject: dict)
    let decoded = try JSONDecoder().decode(AppConfig.self, from: modifiedData)

    XCTAssertNil(decoded.lastUsedLaunchType)
  }
}
