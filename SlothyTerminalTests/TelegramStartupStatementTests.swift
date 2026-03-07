import XCTest

@testable import SlothyTerminalLib

final class TelegramStartupStatementTests: XCTestCase {

  // MARK: - Basic Composition

  func testComposeWithRepoPath() {
    let result = TelegramStartupStatement.compose(
      repositoryPath: "/Users/dev/my-project",
      workingDirectoryPath: "/Users/dev/my-project/src",
      openTabCount: 3
    )

    XCTAssertTrue(result.contains("Repository: /Users/dev/my-project"))
    XCTAssertTrue(result.contains("Open app tabs: 3"))
    XCTAssertTrue(result.hasPrefix("Status"))
  }

  func testComposeWithoutRepoFallsBackToWorkingDirectory() {
    let result = TelegramStartupStatement.compose(
      repositoryPath: nil,
      workingDirectoryPath: "/tmp/no-repo",
      openTabCount: 0
    )

    XCTAssertTrue(result.contains("Repository: /tmp/no-repo"))
  }

  // MARK: - Edge Cases

  func testComposeZeroCounts() {
    let result = TelegramStartupStatement.compose(
      repositoryPath: "/repo",
      workingDirectoryPath: "/repo",
      openTabCount: 0
    )

    XCTAssertTrue(result.contains("Open app tabs: 0"))
  }

  func testComposeHighCounts() {
    let result = TelegramStartupStatement.compose(
      repositoryPath: "/repo",
      workingDirectoryPath: "/repo",
      openTabCount: 42
    )

    XCTAssertTrue(result.contains("Open app tabs: 42"))
  }

  // MARK: - Format

  func testComposeLineCount() {
    let result = TelegramStartupStatement.compose(
      repositoryPath: "/repo",
      workingDirectoryPath: "/repo",
      openTabCount: 1
    )

    let lines = result.components(separatedBy: "\n")
    XCTAssertEqual(lines.count, 3)
    XCTAssertEqual(lines[0], "Status")
  }
}
