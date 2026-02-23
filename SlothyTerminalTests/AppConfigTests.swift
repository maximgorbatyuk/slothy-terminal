import Foundation
import Testing

@testable import SlothyTerminalLib

@Suite("AppConfig")
struct AppConfigTests {

  // MARK: - Resilient Decoding

  @Test("Decodes full config without error")
  func decodesFullConfig() throws {
    let json = """
      {
        "sidebarWidth": 300,
        "showSidebarByDefault": false,
        "sidebarPosition": "left",
        "defaultTabMode": "chat",
        "defaultAgent": "Claude",
        "maxRecentFolders": 5,
        "colorScheme": "dark",
        "terminalFontName": "Menlo",
        "terminalFontSize": 14,
        "terminalInteractionMode": "appMouse",
        "savedPrompts": [],
        "chatSendKey": "Shift+Enter",
        "chatRenderMode": "plainText",
        "chatMessageTextSize": "large",
        "chatShowTimestamps": false,
        "chatShowTokenMetadata": false,
        "lastUsedOpenCodeAskModeEnabled": true,
        "nativeAgentEnabled": true,
        "zaiEndpoint": "international",
        "shortcuts": {},
        "telegramExecutionAgent": "Claude",
        "telegramAutoStartOnOpen": false,
        "telegramDefaultListenMode": "passive",
        "telegramOpenDirectoryTabMode": "chat",
        "telegramOpenDirectoryAgent": "Claude",
        "sidebarTab": "explorer"
      }
      """

    let data = Data(json.utf8)
    let config = try JSONDecoder().decode(AppConfig.self, from: data)

    #expect(config.sidebarWidth == 300)
    #expect(config.showSidebarByDefault == false)
    #expect(config.colorScheme == .dark)
    #expect(config.chatSendKey == .shiftEnter)
    #expect(config.nativeAgentEnabled == true)
    #expect(config.zaiEndpoint == .international)
    #expect(config.terminalFontName == "Menlo")
  }

  @Test("Decodes empty JSON object with all defaults")
  func decodesEmptyJSON() throws {
    let data = Data("{}".utf8)
    let config = try JSONDecoder().decode(AppConfig.self, from: data)
    let defaults = AppConfig()

    #expect(config.sidebarWidth == defaults.sidebarWidth)
    #expect(config.showSidebarByDefault == defaults.showSidebarByDefault)
    #expect(config.defaultTabMode == defaults.defaultTabMode)
    #expect(config.nativeAgentEnabled == defaults.nativeAgentEnabled)
    #expect(config.zaiEndpoint == defaults.zaiEndpoint)
    #expect(config.chatSendKey == defaults.chatSendKey)
    #expect(config.terminalFontName == defaults.terminalFontName)
    #expect(config.terminalFontSize == defaults.terminalFontSize)
  }

  @Test("Decodes partial JSON, missing keys use defaults")
  func decodesPartialJSON() throws {
    let json = """
      {
        "sidebarWidth": 400,
        "chatSendKey": "Shift+Enter"
      }
      """

    let data = Data(json.utf8)
    let config = try JSONDecoder().decode(AppConfig.self, from: data)
    let defaults = AppConfig()

    /// Provided values are used.
    #expect(config.sidebarWidth == 400)
    #expect(config.chatSendKey == .shiftEnter)

    /// Missing values fall back to defaults.
    #expect(config.nativeAgentEnabled == defaults.nativeAgentEnabled)
    #expect(config.zaiEndpoint == defaults.zaiEndpoint)
    #expect(config.terminalFontName == defaults.terminalFontName)
    #expect(config.showSidebarByDefault == defaults.showSidebarByDefault)
    #expect(config.colorScheme == defaults.colorScheme)
  }

  @Test("Unknown keys are ignored gracefully")
  func unknownKeysIgnored() throws {
    let json = """
      {
        "futureFeatureFlag": true,
        "sidebarWidth": 260
      }
      """

    let data = Data(json.utf8)
    let config = try JSONDecoder().decode(AppConfig.self, from: data)

    #expect(config.sidebarWidth == 260)
  }

  @Test("Invalid enum value falls back to default")
  func invalidEnumFallsBack() throws {
    let json = """
      {
        "zaiEndpoint": "unknown_region",
        "colorScheme": "neon"
      }
      """

    let data = Data(json.utf8)
    let config = try JSONDecoder().decode(AppConfig.self, from: data)
    let defaults = AppConfig()

    #expect(config.zaiEndpoint == defaults.zaiEndpoint)
    #expect(config.colorScheme == defaults.colorScheme)
  }

  // MARK: - Round-trip

  @Test("Encode then decode preserves values")
  func roundTrip() throws {
    var original = AppConfig()
    original.sidebarWidth = 350
    original.nativeAgentEnabled = true
    original.zaiEndpoint = .codingPlan
    original.chatSendKey = .shiftEnter
    original.terminalFontName = "Monaco"

    let encoder = JSONEncoder()
    let data = try encoder.encode(original)
    let decoded = try JSONDecoder().decode(AppConfig.self, from: data)

    #expect(decoded == original)
  }
}
