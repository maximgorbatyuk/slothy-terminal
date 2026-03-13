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

  @Test("Status parsing unquotes porcelain paths")
  func parseQuotedPorcelainPath() throws {
    let output = #"""
    ?? "dir with space/file name.txt"
    """#

    let snapshot = service.parseStatusOutput(output)

    let change = try #require(snapshot.changes.first)
    #expect(change.repoRelativePath == "dir with space/file name.txt")
    #expect(change.displayPath == "dir with space/file name.txt")
    #expect(change.filename == "file name.txt")
    #expect(change.isUntracked)
  }

  @Test("Push uses set-upstream when no upstream exists")
  func pushArgumentsWithoutUpstream() {
    let arguments = GitWorkingTreeService.shared.pushArguments(
      currentBranch: "feature/make-commit",
      upstreamBranch: nil
    )

    #expect(arguments == ["push", "--set-upstream", "origin", "feature/make-commit"])
  }

  @Test("Push uses plain push when upstream exists")
  func pushArgumentsWithUpstream() {
    let arguments = GitWorkingTreeService.shared.pushArguments(
      currentBranch: "feature/make-commit",
      upstreamBranch: "origin/feature/make-commit"
    )

    #expect(arguments == ["push"])
  }

  @Test("Commit is blocked when staged changes exist outside scope")
  func commitBlockedOutsideScope() {
    let snapshot = GitWorkingTreeSnapshot(
      changes: [],
      hasStagedChangesOutsideScope: true
    )

    #expect(snapshot.canCommit(message: "Ship it") == false)
  }

  @Test("Branch names must not be blank")
  func blankBranchNameIsInvalid() {
    #expect(GitWorkingTreeService.shared.isValidBranchName("") == false)
    #expect(GitWorkingTreeService.shared.isValidBranchName("   ") == false)
  }
}
