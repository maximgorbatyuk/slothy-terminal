import XCTest
@testable import SlothyTerminalLib

final class SavedPromptDecodingTests: XCTestCase {

  func testDecodeLegacySavedPromptDefaultsMissingFields() throws {
    let promptID = UUID()
    let json = """
    {
      "id": "\(promptID.uuidString)",
      "name": "Legacy Prompt",
      "promptText": "Summarize this pull request"
    }
    """

    let decoded = try decode(SavedPrompt.self, from: json)

    XCTAssertEqual(decoded.id, promptID)
    XCTAssertEqual(decoded.name, "Legacy Prompt")
    XCTAssertEqual(decoded.promptDescription, "")
    XCTAssertEqual(decoded.tagIDs, [])
    XCTAssertEqual(decoded.updatedAt, decoded.createdAt)
  }

  func testDecodeLegacyAppConfigWithoutPromptTagsDefaultsToEmptyCollection() throws {
    var encodedConfig = AppConfig.default
    encodedConfig.savedPrompts = [
      SavedPrompt(name: "Legacy Prompt", promptText: "Review this patch")
    ]

    let data = try JSONEncoder().encode(encodedConfig)
    let json = try XCTUnwrap(String(data: data, encoding: .utf8))
    XCTAssertFalse(json.contains("\"savedPromptTags\""))

    let decoded = try JSONDecoder().decode(AppConfig.self, from: data)

    XCTAssertEqual(decoded.savedPrompts.count, 1)
    XCTAssertEqual(decoded.savedPrompts[0].tagIDs, [])
    XCTAssertEqual(decoded.promptTags, [])
    XCTAssertNil(decoded.savedPromptTags)
  }

  func testDecodeAppConfigWithPromptTagsAndAssignments() throws {
    let promptID = UUID()
    let bugTagID = UUID()
    let refactorTagID = UUID()
    var encodedConfig = AppConfig.default
    encodedConfig.promptTags = [
      PromptTag(id: bugTagID, name: "Bug"),
      PromptTag(id: refactorTagID, name: "Refactor")
    ]
    encodedConfig.savedPrompts = [
      SavedPrompt(
        id: promptID,
        name: "Fix Prompt",
        promptDescription: "Use safe migrations",
        promptText: "Fix migration issues without data loss",
        tagIDs: [bugTagID, refactorTagID]
      )
    ]

    let data = try JSONEncoder().encode(encodedConfig)
    let decoded = try JSONDecoder().decode(AppConfig.self, from: data)

    XCTAssertEqual(decoded.promptTags.count, 2)
    XCTAssertEqual(Set(decoded.promptTags.map(\.id)), Set([bugTagID, refactorTagID]))
    XCTAssertEqual(decoded.savedPrompts.count, 1)
    XCTAssertEqual(Set(decoded.savedPrompts[0].tagIDs), Set([bugTagID, refactorTagID]))
  }

  private func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
    let data = try XCTUnwrap(json.data(using: .utf8))
    return try JSONDecoder().decode(type, from: data)
  }
}
