import Foundation
import Testing

@testable import SlothyTerminalLib

@Suite("SystemInfoTool")
struct SystemInfoToolTests {

  private let tool = SystemInfoTool()

  private func makeContext() -> ToolContext {
    ToolContext(
      sessionID: "test",
      workingDirectory: FileManager.default.temporaryDirectory,
      permissions: MockPermissionDelegate()
    )
  }

  // MARK: - Validation

  @Test("Missing category argument returns error")
  func missingCategory() async throws {
    let result = try await tool.execute(
      arguments: [:],
      context: makeContext()
    )

    #expect(result.isError)
    #expect(result.output.contains("category is required"))
  }

  @Test("Unknown category returns error")
  func unknownCategory() async throws {
    let result = try await tool.execute(
      arguments: ["category": .string("unknown_thing")],
      context: makeContext()
    )

    #expect(result.isError)
    #expect(result.output.contains("Unknown category"))
  }

  // MARK: - System category

  @Test("System category returns OS and memory info")
  func systemInfo() async throws {
    let result = try await tool.execute(
      arguments: ["category": .string("system")],
      context: makeContext()
    )

    #expect(!result.isError)
    #expect(result.output.contains("OS: macOS"))
    #expect(result.output.contains("Physical Memory:"))
    #expect(result.output.contains("Processor Count:"))
  }

  // MARK: - Environment category

  @Test("Env category returns PATH and HOME")
  func envInfo() async throws {
    let result = try await tool.execute(
      arguments: ["category": .string("env")],
      context: makeContext()
    )

    #expect(!result.isError)
    #expect(result.output.contains("PATH="))
    #expect(result.output.contains("HOME="))
    #expect(result.output.contains("SHELL="))
  }

  // MARK: - Installed tools category

  @Test("Installed tools checks common tools")
  func installedTools() async throws {
    let result = try await tool.execute(
      arguments: ["category": .string("installed_tools")],
      context: makeContext()
    )

    #expect(!result.isError)
    /// git should always be available on a macOS dev machine.
    #expect(result.output.contains("git:"))
  }

  // MARK: - Disk category

  @Test("Disk category returns filesystem info")
  func diskInfo() async throws {
    let result = try await tool.execute(
      arguments: ["category": .string("disk")],
      context: makeContext()
    )

    #expect(!result.isError)
    #expect(result.output.contains("Filesystem") || result.output.contains("/dev/"))
  }

  // MARK: - Tool metadata

  @Test("Tool ID is 'system_info'")
  func toolID() {
    #expect(tool.id == "system_info")
  }

  @Test("Parameters require category")
  func categoryRequired() {
    #expect(tool.parameters.required.contains("category"))
  }
}
