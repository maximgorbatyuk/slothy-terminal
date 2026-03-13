import Foundation
import Testing

@testable import SlothyTerminalLib

@Suite("Git Working Tree")
struct GitWorkingTreeServiceTests {
  private let service = GitWorkingTreeService.shared

  @Test("Status parsing keeps staged and unstaged columns separate")
  func parseDualColumnStatus() throws {
    let output = """
    MM Sources/App.swift
    A  Sources/NewFile.swift
     D Sources/OldFile.swift
    ?? Sources/Scratch.swift
    M  README.md
    """

    let snapshot = service.parseStatusOutput(
      output,
      scopePath: "Sources"
    )

    #expect(snapshot.changes.count == 4)

    let app = try #require(snapshot.changes.first { $0.repoRelativePath == "Sources/App.swift" })
    #expect(app.indexStatus == .modified)
    #expect(app.workTreeStatus == .modified)
    #expect(app.hasStagedEntry)
    #expect(app.hasUnstagedEntry)

    let scratch = try #require(snapshot.changes.first { $0.repoRelativePath == "Sources/Scratch.swift" })
    #expect(scratch.isUntracked)
    #expect(scratch.hasUnstagedEntry)
    #expect(!scratch.hasStagedEntry)
  }

  @Test("Status parsing keeps staged paths outside scope out of the visible snapshot")
  func parseScopeFiltering() {
    let output = """
    M  Sources/App.swift
    M  README.md
    """

    let snapshot = service.parseStatusOutput(output, scopePath: "Sources")

    #expect(snapshot.changes.count == 1)
    #expect(snapshot.changes[0].repoRelativePath == "Sources/App.swift")
    #expect(snapshot.hasStagedChangesOutsideScope)
  }
}
