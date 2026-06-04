import Foundation
import Testing

@testable import SlothyTerminalLib

@Suite("Directory Tree Expansion Store")
struct DirectoryTreeExpansionStoreTests {
  /// Returns a unique temp file URL so tests do not interfere with each other.
  private func makeTempFileURL() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("DirectoryTreeExpansionStoreTests", isDirectory: true)
      .appendingPathComponent("\(UUID().uuidString).json")
  }

  @Test("Unknown root returns an empty set")
  func unknownRootReturnsEmptySet() {
    let store = DirectoryTreeExpansionStore(fileURL: makeTempFileURL())

    #expect(store.expandedPaths(forRoot: "/tmp/project").isEmpty)
  }

  @Test("Expanding folders records their paths under the root")
  func expandRecordsPaths() {
    let store = DirectoryTreeExpansionStore(fileURL: makeTempFileURL())

    store.setExpanded(true, path: "/tmp/project/Sources", rootPath: "/tmp/project")
    store.setExpanded(true, path: "/tmp/project/Sources/App", rootPath: "/tmp/project")

    #expect(store.expandedPaths(forRoot: "/tmp/project") == [
      "/tmp/project/Sources",
      "/tmp/project/Sources/App",
    ])
  }

  @Test("Collapsing a folder removes only that folder's path")
  func collapseRemovesOnlyThatPath() {
    let store = DirectoryTreeExpansionStore(fileURL: makeTempFileURL())

    store.setExpanded(true, path: "/tmp/project/Sources", rootPath: "/tmp/project")
    store.setExpanded(true, path: "/tmp/project/Sources/App", rootPath: "/tmp/project")
    store.setExpanded(false, path: "/tmp/project/Sources", rootPath: "/tmp/project")

    /// The descendant stays remembered so re-expanding the parent restores it.
    #expect(store.expandedPaths(forRoot: "/tmp/project") == ["/tmp/project/Sources/App"])
  }

  @Test("Roots are isolated from each other")
  func rootsAreIsolated() {
    let store = DirectoryTreeExpansionStore(fileURL: makeTempFileURL())

    store.setExpanded(true, path: "/tmp/a/src", rootPath: "/tmp/a")
    store.setExpanded(true, path: "/tmp/b/lib", rootPath: "/tmp/b")

    #expect(store.expandedPaths(forRoot: "/tmp/a") == ["/tmp/a/src"])
    #expect(store.expandedPaths(forRoot: "/tmp/b") == ["/tmp/b/lib"])
  }

  @Test("Collapsing the last folder removes the root entry")
  func collapsingLastFolderRemovesRoot() {
    let store = DirectoryTreeExpansionStore(fileURL: makeTempFileURL())

    store.setExpanded(true, path: "/tmp/project/Sources", rootPath: "/tmp/project")
    store.setExpanded(false, path: "/tmp/project/Sources", rootPath: "/tmp/project")

    #expect(store.expandedPaths(forRoot: "/tmp/project").isEmpty)
  }

  @Test("State persists across store instances")
  func statePersistsAcrossInstances() {
    let fileURL = makeTempFileURL()

    let store = DirectoryTreeExpansionStore(fileURL: fileURL)
    store.setExpanded(true, path: "/tmp/project/Sources", rootPath: "/tmp/project")
    store.setExpanded(true, path: "/tmp/other/docs", rootPath: "/tmp/other")
    store.saveNow()

    let reloaded = DirectoryTreeExpansionStore(fileURL: fileURL)

    #expect(reloaded.expandedPaths(forRoot: "/tmp/project") == ["/tmp/project/Sources"])
    #expect(reloaded.expandedPaths(forRoot: "/tmp/other") == ["/tmp/other/docs"])
  }

  @Test("Missing file loads as empty state")
  func missingFileLoadsEmpty() {
    let store = DirectoryTreeExpansionStore(fileURL: makeTempFileURL())

    #expect(store.expandedPaths(forRoot: "/tmp/project").isEmpty)
  }

  @Test("Corrupt file loads as empty state without crashing")
  func corruptFileLoadsEmpty() throws {
    let fileURL = makeTempFileURL()
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data("not json".utf8).write(to: fileURL)

    let store = DirectoryTreeExpansionStore(fileURL: fileURL)

    #expect(store.expandedPaths(forRoot: "/tmp/project").isEmpty)
  }
}
