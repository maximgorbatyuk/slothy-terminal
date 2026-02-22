import Foundation
import Testing

@testable import SlothyTerminalLib

@Suite("EditFileTool")
struct EditFileToolTests {

  private let tool = EditFileTool()

  private func makeContext(dir: URL) -> ToolContext {
    ToolContext(
      sessionID: "test",
      workingDirectory: dir,
      permissions: MockPermissionDelegate()
    )
  }

  private func makeTempFile(
    content: String
  ) throws -> (file: URL, dir: URL) {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(
      at: tempDir,
      withIntermediateDirectories: true
    )
    let file = tempDir.appendingPathComponent("test.swift")
    try content.write(to: file, atomically: true, encoding: .utf8)
    return (file, tempDir)
  }

  // MARK: - Replacement

  @Test("Replace unique string succeeds")
  func replaceUnique() async throws {
    let (file, dir) = try makeTempFile(content: "hello world")
    defer { try? FileManager.default.removeItem(at: dir) }

    let result = try await tool.execute(
      arguments: [
        "file_path": .string(file.path),
        "old_string": .string("hello"),
        "new_string": .string("goodbye"),
      ],
      context: makeContext(dir: dir)
    )

    #expect(!result.isError)
    #expect(result.output.contains("Replaced 1 occurrence"))

    let updated = try String(contentsOf: file, encoding: .utf8)
    #expect(updated == "goodbye world")
  }

  @Test("Replace all occurrences with replace_all flag")
  func replaceAll() async throws {
    let (file, dir) = try makeTempFile(content: "foo bar foo baz foo")
    defer { try? FileManager.default.removeItem(at: dir) }

    let result = try await tool.execute(
      arguments: [
        "file_path": .string(file.path),
        "old_string": .string("foo"),
        "new_string": .string("qux"),
        "replace_all": .bool(true),
      ],
      context: makeContext(dir: dir)
    )

    #expect(!result.isError)
    #expect(result.output.contains("Replaced 3 occurrence"))

    let updated = try String(contentsOf: file, encoding: .utf8)
    #expect(updated == "qux bar qux baz qux")
  }

  // MARK: - Error cases

  @Test("Non-unique string without replace_all returns error")
  func nonUniqueWithoutFlag() async throws {
    let (file, dir) = try makeTempFile(content: "aaa aaa aaa")
    defer { try? FileManager.default.removeItem(at: dir) }

    let result = try await tool.execute(
      arguments: [
        "file_path": .string(file.path),
        "old_string": .string("aaa"),
        "new_string": .string("bbb"),
      ],
      context: makeContext(dir: dir)
    )

    #expect(result.isError)
    #expect(result.output.contains("appears 3 times"))
  }

  @Test("Old string not found returns error")
  func oldStringNotFound() async throws {
    let (file, dir) = try makeTempFile(content: "hello world")
    defer { try? FileManager.default.removeItem(at: dir) }

    let result = try await tool.execute(
      arguments: [
        "file_path": .string(file.path),
        "old_string": .string("xyz"),
        "new_string": .string("abc"),
      ],
      context: makeContext(dir: dir)
    )

    #expect(result.isError)
    #expect(result.output.contains("not found"))
  }

  @Test("Identical old and new string returns error")
  func identicalStrings() async throws {
    let (file, dir) = try makeTempFile(content: "hello world")
    defer { try? FileManager.default.removeItem(at: dir) }

    let result = try await tool.execute(
      arguments: [
        "file_path": .string(file.path),
        "old_string": .string("hello"),
        "new_string": .string("hello"),
      ],
      context: makeContext(dir: dir)
    )

    #expect(result.isError)
    #expect(result.output.contains("identical"))
  }

  @Test("Edit missing file returns error")
  func editMissingFile() async throws {
    let dir = FileManager.default.temporaryDirectory
    let result = try await tool.execute(
      arguments: [
        "file_path": .string("/nonexistent/file.swift"),
        "old_string": .string("a"),
        "new_string": .string("b"),
      ],
      context: makeContext(dir: dir)
    )

    #expect(result.isError)
    #expect(result.output.contains("File not found"))
  }
}
