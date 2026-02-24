import Foundation
import Testing

@testable import SlothyTerminalLib

@Suite("AppleScriptTool")
struct AppleScriptToolTests {

  private let tool = AppleScriptTool()

  private func makeContext() -> ToolContext {
    ToolContext(
      sessionID: "test",
      workingDirectory: FileManager.default.temporaryDirectory,
      permissions: MockPermissionDelegate()
    )
  }

  // MARK: - Validation

  @Test("Missing script argument returns error")
  func missingScript() async throws {
    let result = try await tool.execute(
      arguments: [:],
      context: makeContext()
    )

    #expect(result.isError)
    #expect(result.output.contains("script is required"))
  }

  // MARK: - AppleScript execution

  @Test("Simple string return works")
  func simpleReturn() async throws {
    let result = try await tool.execute(
      arguments: ["script": .string("return \"hello\"")],
      context: makeContext()
    )

    #expect(!result.isError)
    #expect(result.output == "hello")
  }

  @Test("Arithmetic expression returns result")
  func arithmetic() async throws {
    let result = try await tool.execute(
      arguments: ["script": .string("return 2 + 3")],
      context: makeContext()
    )

    #expect(!result.isError)
    #expect(result.output == "5")
  }

  @Test("Invalid script returns error")
  func invalidScript() async throws {
    let result = try await tool.execute(
      arguments: ["script": .string("this is not valid applescript syntax !!!")],
      context: makeContext()
    )

    #expect(result.isError)
  }

  // MARK: - JXA mode

  @Test("JavaScript for Automation works")
  func jxaMode() async throws {
    let result = try await tool.execute(
      arguments: [
        "script": .string("2 + 3"),
        "language": .string("JavaScript"),
      ],
      context: makeContext()
    )

    #expect(!result.isError)
    #expect(result.output == "5")
  }

  // MARK: - Tool metadata

  @Test("Tool ID is 'applescript'")
  func toolID() {
    #expect(tool.id == "applescript")
  }

  @Test("Parameters require script")
  func scriptRequired() {
    #expect(tool.parameters.required.contains("script"))
  }
}
