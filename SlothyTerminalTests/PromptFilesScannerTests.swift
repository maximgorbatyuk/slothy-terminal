import Foundation
import Testing

@testable import SlothyTerminalLib

@Suite("PromptFilesScanner")
struct PromptFilesScannerTests {
  private func makeTempWorkspace() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("PromptFilesScannerTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  private func createFile(at url: URL, content: String = "") throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try content.write(to: url, atomically: true, encoding: .utf8)
  }

  private func cleanup(_ dir: URL) {
    try? FileManager.default.removeItem(at: dir)
  }

  // MARK: - Missing folder

  @Test("Returns empty when docs/prompts is missing")
  func returnsEmptyWhenFolderMissing() throws {
    let root = try makeTempWorkspace()
    defer { cleanup(root) }

    let results = PromptFilesScanner.scanSync(workspaceRoot: root)

    #expect(results.isEmpty)
  }

  @Test("Returns empty when docs/prompts exists but is empty")
  func returnsEmptyWhenFolderEmpty() throws {
    let root = try makeTempWorkspace()
    defer { cleanup(root) }

    try FileManager.default.createDirectory(
      at: root.appendingPathComponent("docs/prompts"),
      withIntermediateDirectories: true
    )

    let results = PromptFilesScanner.scanSync(workspaceRoot: root)

    #expect(results.isEmpty)
  }

  // MARK: - Extension filtering

  @Test("Detects .md and .txt files at the prompts root")
  func detectsSupportedExtensions() throws {
    let root = try makeTempWorkspace()
    defer { cleanup(root) }

    let prompts = root.appendingPathComponent("docs/prompts")
    try createFile(at: prompts.appendingPathComponent("intro.md"), content: "# Intro\n")
    try createFile(at: prompts.appendingPathComponent("notes.txt"), content: "hi\n")

    let results = PromptFilesScanner.scanSync(workspaceRoot: root)

    #expect(results.count == 2)
    #expect(results.map(\.fileName).sorted() == ["intro.md", "notes.txt"])
  }

  @Test("Ignores unsupported extensions")
  func ignoresUnsupportedExtensions() throws {
    let root = try makeTempWorkspace()
    defer { cleanup(root) }

    let prompts = root.appendingPathComponent("docs/prompts")
    try createFile(at: prompts.appendingPathComponent("a.md"))
    try createFile(at: prompts.appendingPathComponent("b.png"))
    try createFile(at: prompts.appendingPathComponent("c.json"))
    try createFile(at: prompts.appendingPathComponent("d"))

    let results = PromptFilesScanner.scanSync(workspaceRoot: root)

    #expect(results.count == 1)
    #expect(results[0].fileName == "a.md")
  }

  @Test("Matches extensions case-insensitively")
  func matchesExtensionsCaseInsensitively() throws {
    let root = try makeTempWorkspace()
    defer { cleanup(root) }

    let prompts = root.appendingPathComponent("docs/prompts")
    try createFile(at: prompts.appendingPathComponent("upper.MD"))
    try createFile(at: prompts.appendingPathComponent("mixed.Txt"))

    let results = PromptFilesScanner.scanSync(workspaceRoot: root)

    #expect(results.count == 2)
    #expect(results.allSatisfy { ["md", "txt"].contains($0.fileExtension) })
  }

  // MARK: - Recursion

  @Test("Recurses into subfolders")
  func recursesIntoSubfolders() throws {
    let root = try makeTempWorkspace()
    defer { cleanup(root) }

    let prompts = root.appendingPathComponent("docs/prompts")
    try createFile(at: prompts.appendingPathComponent("top.md"))
    try createFile(at: prompts.appendingPathComponent("sub/nested.md"))
    try createFile(at: prompts.appendingPathComponent("sub/deeper/more.txt"))

    let results = PromptFilesScanner.scanSync(workspaceRoot: root)

    #expect(results.count == 3)

    let paths = Set(results.map(\.relativePath))
    #expect(paths == ["top.md", "sub/nested.md", "sub/deeper/more.txt"])
  }

  @Test("Results sorted alphabetically by relative path")
  func resultsSortedAlphabetically() throws {
    let root = try makeTempWorkspace()
    defer { cleanup(root) }

    let prompts = root.appendingPathComponent("docs/prompts")
    try createFile(at: prompts.appendingPathComponent("zeta.md"))
    try createFile(at: prompts.appendingPathComponent("alpha.txt"))
    try createFile(at: prompts.appendingPathComponent("sub/beta.md"))

    let results = PromptFilesScanner.scanSync(workspaceRoot: root)

    #expect(results.map(\.relativePath) == ["alpha.txt", "sub/beta.md", "zeta.md"])
  }

  // MARK: - readContent

  @Test("readContent returns UTF-8 text")
  func readContentReturnsText() async throws {
    let root = try makeTempWorkspace()
    defer { cleanup(root) }

    let prompts = root.appendingPathComponent("docs/prompts")
    let body = "# Title\n\nHello, мир 🌍\n"
    try createFile(at: prompts.appendingPathComponent("file.md"), content: body)

    let results = PromptFilesScanner.scanSync(workspaceRoot: root)

    #expect(results.count == 1)

    let content = await PromptFilesScanner.readContent(of: results[0])

    #expect(content == body)
  }
}
