import Foundation
import Testing

@testable import SlothyTerminalLib

@Suite("OpenTool")
struct OpenToolTests {

  private let tool = OpenTool()

  private func makeContext() -> ToolContext {
    ToolContext(
      sessionID: "test",
      workingDirectory: FileManager.default.temporaryDirectory,
      permissions: MockPermissionDelegate()
    )
  }

  // MARK: - Validation

  @Test("Missing target argument returns error")
  func missingTarget() async throws {
    let result = try await tool.execute(
      arguments: [:],
      context: makeContext()
    )

    #expect(result.isError)
    #expect(result.output.contains("target is required"))
  }

  // MARK: - File opening

  @Test("Opening a real directory succeeds")
  func openDirectory() async throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(
      at: tempDir,
      withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let result = try await tool.execute(
      arguments: ["target": .string(tempDir.path)],
      context: makeContext()
    )

    #expect(!result.isError)
    #expect(result.output.contains("Opened"))
  }

  // MARK: - Tool metadata

  @Test("Tool ID is 'open'")
  func toolID() {
    #expect(tool.id == "open")
  }

  @Test("Parameters include target as required")
  func targetRequired() {
    #expect(tool.parameters.required.contains("target"))
  }

  @Test("Parameters include optional application")
  func applicationOptional() {
    #expect(tool.parameters.properties["application"] != nil)
    #expect(!tool.parameters.required.contains("application"))
  }
}
