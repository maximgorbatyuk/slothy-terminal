import Foundation
import Testing

@testable import SlothyTerminalLib

@Suite("ReadFileTool")
struct ReadFileToolTests {

  private let tool = ReadFileTool()

  private func makeContext(dir: URL) -> ToolContext {
    ToolContext(
      sessionID: "test",
      workingDirectory: dir,
      permissions: MockPermissionDelegate()
    )
  }

  private func makeTempFile(
    content: String,
    in dir: URL? = nil
  ) throws -> (file: URL, dir: URL) {
    let tempDir = dir ?? FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(
      at: tempDir,
      withIntermediateDirectories: true
    )
    let file = tempDir.appendingPathComponent("test.txt")
    try content.write(to: file, atomically: true, encoding: .utf8)
    return (file, tempDir)
  }

  // MARK: - Reading

  @Test("Read a simple file returns numbered lines")
  func readSimpleFile() async throws {
    let (file, dir) = try makeTempFile(content: "line1\nline2\nline3")
    defer { try? FileManager.default.removeItem(at: dir) }

    let result = try await tool.execute(
      arguments: ["file_path": .string(file.path)],
      context: makeContext(dir: dir)
    )

    #expect(!result.isError)
    #expect(result.output.contains("1\tline1"))
    #expect(result.output.contains("2\tline2"))
    #expect(result.output.contains("3\tline3"))
  }

  @Test("Read with offset starts from specified line")
  func readWithOffset() async throws {
    let (file, dir) = try makeTempFile(content: "a\nb\nc\nd\ne")
    defer { try? FileManager.default.removeItem(at: dir) }

    let result = try await tool.execute(
      arguments: [
        "file_path": .string(file.path),
        "offset": .number(3),
      ],
      context: makeContext(dir: dir)
    )

    #expect(!result.isError)
    #expect(result.output.contains("3\tc"))
    #expect(!result.output.contains("1\ta"))
  }

  @Test("Read with limit restricts number of lines")
  func readWithLimit() async throws {
    let (file, dir) = try makeTempFile(content: "a\nb\nc\nd\ne")
    defer { try? FileManager.default.removeItem(at: dir) }

    let result = try await tool.execute(
      arguments: [
        "file_path": .string(file.path),
        "limit": .number(2),
      ],
      context: makeContext(dir: dir)
    )

    #expect(!result.isError)
    #expect(result.output.contains("1\ta"))
    #expect(result.output.contains("2\tb"))
    #expect(!result.output.contains("3\tc"))
  }

  @Test("Read with offset and limit together")
  func readWithOffsetAndLimit() async throws {
    let (file, dir) = try makeTempFile(content: "a\nb\nc\nd\ne")
    defer { try? FileManager.default.removeItem(at: dir) }

    let result = try await tool.execute(
      arguments: [
        "file_path": .string(file.path),
        "offset": .number(2),
        "limit": .number(2),
      ],
      context: makeContext(dir: dir)
    )

    #expect(!result.isError)
    #expect(result.output.contains("2\tb"))
    #expect(result.output.contains("3\tc"))
    #expect(!result.output.contains("4\td"))
  }

  // MARK: - Error cases

  @Test("Read missing file returns error")
  func readMissingFile() async throws {
    let dir = FileManager.default.temporaryDirectory
    let result = try await tool.execute(
      arguments: ["file_path": .string("/nonexistent/path/file.txt")],
      context: makeContext(dir: dir)
    )

    #expect(result.isError)
    #expect(result.output.contains("File not found"))
  }

  @Test("Read without file_path returns error")
  func readMissingArg() async throws {
    let dir = FileManager.default.temporaryDirectory
    let result = try await tool.execute(
      arguments: [:],
      context: makeContext(dir: dir)
    )

    #expect(result.isError)
    #expect(result.output.contains("file_path is required"))
  }
}
