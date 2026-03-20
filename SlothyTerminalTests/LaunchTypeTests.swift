import XCTest

@testable import SlothyTerminalLib

final class LaunchTypeTests: XCTestCase {

  // MARK: - Metadata Tests

  func testAllCasesCount() {
    XCTAssertEqual(LaunchType.allCases.count, 4)
  }

  func testDisplayNames() {
    XCTAssertEqual(LaunchType.terminal.displayName, "Terminal")
    XCTAssertEqual(LaunchType.claude.displayName, "claude")
    XCTAssertEqual(LaunchType.opencode.displayName, "opencode")
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
    XCTAssertTrue(LaunchType.claude.requiresPrompt)
    XCTAssertTrue(LaunchType.opencode.requiresPrompt)
  }

  func testRequiresPredefinedPrompt() {
    XCTAssertFalse(LaunchType.terminal.requiresPredefinedPrompt)
    XCTAssertFalse(LaunchType.claude.requiresPredefinedPrompt)
    XCTAssertFalse(LaunchType.opencode.requiresPredefinedPrompt)
  }

  func testAgentTypeMapping() {
    XCTAssertEqual(LaunchType.terminal.agentType, .terminal)
    XCTAssertEqual(LaunchType.claude.agentType, .claude)
    XCTAssertEqual(LaunchType.opencode.agentType, .opencode)
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
    XCTAssertEqual(LaunchType.claude.rawValue, "claude")
    XCTAssertEqual(LaunchType.opencode.rawValue, "opencode")
  }

  // MARK: - Config Persistence Tests

  func testAppConfigLastUsedLaunchTypeEncoding() throws {
    var config = AppConfig.default
    config.lastUsedLaunchType = .opencode

    let encoded = try JSONEncoder().encode(config)
    let decoded = try JSONDecoder().decode(AppConfig.self, from: encoded)

    XCTAssertEqual(decoded.lastUsedLaunchType, .opencode)
  }

  func testAppConfigLastUsedLaunchTypeNewCases() throws {
    for launchType in [LaunchType.claude, LaunchType.opencode] {
      var config = AppConfig.default
      config.lastUsedLaunchType = launchType

      let encoded = try JSONEncoder().encode(config)
      let decoded = try JSONDecoder().decode(AppConfig.self, from: encoded)

      XCTAssertEqual(decoded.lastUsedLaunchType, launchType)
    }
  }

  func testAppConfigLastUsedLaunchTypeNilByDefault() throws {
    let config = AppConfig.default
    XCTAssertNil(config.lastUsedLaunchType)
  }

  func testAppConfigBackwardCompatibleWithoutLaunchType() throws {
    /// Encode a full config with lastUsedLaunchType set, then remove it from
    /// the JSON to simulate a config saved before the field existed.
    var config = AppConfig.default
    config.lastUsedLaunchType = .claude

    let encoded = try JSONEncoder().encode(config)
    var dict = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
    dict.removeValue(forKey: "lastUsedLaunchType")

    let modifiedData = try JSONSerialization.data(withJSONObject: dict)
    let decoded = try JSONDecoder().decode(AppConfig.self, from: modifiedData)

    XCTAssertNil(decoded.lastUsedLaunchType)
  }
}
