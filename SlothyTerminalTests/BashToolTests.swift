import Foundation
import Testing

@testable import SlothyTerminalLib

@Suite("BashTool")
struct BashToolTests {

  private let tool = BashTool()

  private func makeContext() -> ToolContext {
    ToolContext(
      sessionID: "test",
      workingDirectory: FileManager.default.temporaryDirectory,
      permissions: MockPermissionDelegate()
    )
  }

  // MARK: - Basic execution

  @Test("Simple echo command returns output")
  func simpleEcho() async throws {
    let result = try await tool.execute(
      arguments: ["command": .string("echo 'hello world'")],
      context: makeContext()
    )

    #expect(!result.isError)
    #expect(result.output.trimmingCharacters(in: .whitespacesAndNewlines) == "hello world")
  }

  @Test("Command with exit code 0 is not an error")
  func exitCodeZero() async throws {
    let result = try await tool.execute(
      arguments: ["command": .string("true")],
      context: makeContext()
    )

    #expect(!result.isError)
  }

  @Test("Command with non-zero exit code is an error")
  func nonZeroExitCode() async throws {
    let result = try await tool.execute(
      arguments: ["command": .string("exit 42")],
      context: makeContext()
    )

    #expect(result.isError)
    #expect(result.output.contains("Exit code: 42"))
  }

  @Test("Captures stderr for failed commands")
  func capturesStderr() async throws {
    let result = try await tool.execute(
      arguments: ["command": .string("echo 'err msg' >&2; exit 1")],
      context: makeContext()
    )

    #expect(result.isError)
    #expect(result.output.contains("err msg"))
  }

  // MARK: - Working directory

  @Test("Respects working directory from context")
  func workingDirectory() async throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(
      at: tempDir,
      withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let ctx = ToolContext(
      sessionID: "test",
      workingDirectory: tempDir,
      permissions: MockPermissionDelegate()
    )

    let result = try await tool.execute(
      arguments: ["command": .string("pwd")],
      context: ctx
    )

    #expect(!result.isError)

    /// macOS resolves /var → /private/var via symlink; normalize both paths.
    let actual = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    let expected = tempDir.path.replacingOccurrences(of: "/private", with: "")
    let normalizedActual = actual.replacingOccurrences(of: "/private", with: "")
    #expect(normalizedActual == expected)
  }

  // MARK: - Timeout

  @Test("Short timeout causes timeout error")
  func timeout() async throws {
    let result = try await tool.execute(
      arguments: [
        "command": .string("sleep 10"),
        "timeout": .number(500),
      ],
      context: makeContext()
    )

    #expect(result.isError)
    #expect(result.output.contains("timed out"))
  }

  // MARK: - Missing arguments

  @Test("Missing command argument returns error")
  func missingCommand() async throws {
    let result = try await tool.execute(
      arguments: [:],
      context: makeContext()
    )

    #expect(result.isError)
    #expect(result.output.contains("command is required"))
  }
}
