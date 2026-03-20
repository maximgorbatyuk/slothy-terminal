import Foundation
import Testing

@testable import SlothyTerminalLib

@Suite("DirectoryTreeScanner")
struct DirectoryTreeScannerTests {
  private func makeTempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("DirectoryTreeScannerTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  private func createDirectory(at url: URL, name: String) throws {
    try FileManager.default.createDirectory(
      at: url.appendingPathComponent(name, isDirectory: true),
      withIntermediateDirectories: true
    )
  }

  private func createFile(at url: URL, name: String, contents: String = "") throws {
    try contents.write(
      to: url.appendingPathComponent(name),
      atomically: true,
      encoding: .utf8
    )
  }

  private func cleanup(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
  }

  @Test("Async scan matches sorted directory-first sync results")
  func asyncScanMatchesSortedSyncResults() async throws {
    let dir = try makeTempDir()
    defer { cleanup(dir) }

    try createDirectory(at: dir, name: "beta")
    try createDirectory(at: dir, name: "Alpha")
    try createFile(at: dir, name: "zeta.txt")
    try createFile(at: dir, name: "gamma.txt")

    let syncEntries = DirectoryTreeScanner.scanSync(directory: dir)
    let asyncEntries = await DirectoryTreeScanner.scan(directory: dir)

    #expect(syncEntries.map(\.name) == ["Alpha", "beta", "gamma.txt", "zeta.txt"])
    #expect(asyncEntries == syncEntries)
    #expect(syncEntries.map(\.id) == syncEntries.map { $0.url.path })
  }

  @Test("Hidden files can be excluded")
  func hiddenFilesCanBeExcluded() throws {
    let dir = try makeTempDir()
    defer { cleanup(dir) }

    try createFile(at: dir, name: ".secret")
    try createFile(at: dir, name: "visible.txt")

    let entries = DirectoryTreeScanner.scanSync(directory: dir, showHidden: false)

    #expect(entries.map(\.name) == ["visible.txt"])
  }

  @Test("Maximum visible item limit is enforced")
  func maximumVisibleItemLimitIsEnforced() throws {
    let dir = try makeTempDir()
    defer { cleanup(dir) }

    for index in 0..<105 {
      try createFile(at: dir, name: "file-\(index).txt")
    }

    let entries = DirectoryTreeScanner.scanSync(directory: dir, maxVisibleItems: 100)

    #expect(entries.count == 100)
  }

  @Test("Scanning a file path returns no entries")
  func scanningFilePathReturnsNoEntries() throws {
    let dir = try makeTempDir()
    defer { cleanup(dir) }

    try createFile(at: dir, name: "single.txt")
    let fileURL = dir.appendingPathComponent("single.txt")

    #expect(DirectoryTreeScanner.scanSync(directory: fileURL).isEmpty)
  }
}
