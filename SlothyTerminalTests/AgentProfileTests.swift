import Foundation
import Testing

@testable import SlothyTerminalLib

@Suite("AgentProfile")
struct AgentProfileTests {

  // MARK: - Default values

  @Test("Default profile has nil IDE and empty collections")
  func defaultValues() {
    let profile = AgentProfile()

    #expect(profile.preferredIDE == nil)
    #expect(profile.projectRoots.isEmpty)
    #expect(profile.customInstructions == nil)
    #expect(profile.preferredApps.isEmpty)
  }

  // MARK: - Codable roundtrip

  @Test("Full profile encodes and decodes correctly")
  func codableRoundtrip() throws {
    let original = AgentProfile(
      preferredIDE: "Cursor",
      projectRoots: ["/Users/dev/projects", "/Users/dev/work"],
      customInstructions: "Always write tests first.",
      preferredApps: ["browser": "Arc", "terminal": "SlothyTerminal"]
    )

    let encoder = JSONEncoder()
    let data = try encoder.encode(original)
    let decoded = try JSONDecoder().decode(AgentProfile.self, from: data)

    #expect(decoded.preferredIDE == "Cursor")
    #expect(decoded.projectRoots == ["/Users/dev/projects", "/Users/dev/work"])
    #expect(decoded.customInstructions == "Always write tests first.")
    #expect(decoded.preferredApps["browser"] == "Arc")
    #expect(decoded.preferredApps["terminal"] == "SlothyTerminal")
  }

  // MARK: - Resilient decoding

  @Test("Missing keys decode to defaults")
  func resilientDecoding() throws {
    let json = "{}"
    let data = json.data(using: .utf8)!
    let decoded = try JSONDecoder().decode(AgentProfile.self, from: data)

    #expect(decoded.preferredIDE == nil)
    #expect(decoded.projectRoots.isEmpty)
    #expect(decoded.customInstructions == nil)
    #expect(decoded.preferredApps.isEmpty)
  }

  @Test("Partial JSON decodes only present fields")
  func partialDecoding() throws {
    let json = """
      {"preferredIDE": "Xcode", "projectRoots": ["/tmp"]}
      """
    let data = json.data(using: .utf8)!
    let decoded = try JSONDecoder().decode(AgentProfile.self, from: data)

    #expect(decoded.preferredIDE == "Xcode")
    #expect(decoded.projectRoots == ["/tmp"])
    #expect(decoded.customInstructions == nil)
    #expect(decoded.preferredApps.isEmpty)
  }

  // MARK: - Equatable

  @Test("Two default profiles are equal")
  func equatable() {
    let a = AgentProfile()
    let b = AgentProfile()
    #expect(a == b)
  }

  @Test("Different profiles are not equal")
  func notEqual() {
    let a = AgentProfile(preferredIDE: "Xcode")
    let b = AgentProfile(preferredIDE: "VSCode")
    #expect(a != b)
  }
}
