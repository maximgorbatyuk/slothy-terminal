import XCTest

@testable import SlothyTerminalLib

final class TelegramStartupStatementTests: XCTestCase {

  // MARK: - Basic Composition

  func testComposeWithRepoPath() {
    let result = TelegramStartupStatement.compose(
      repositoryPath: "/Users/dev/my-project",
      workingDirectoryPath: "/Users/dev/my-project/src",
      openTabCount: 3,
      activeTaskCount: 2
    )

    XCTAssertTrue(result.contains("Repository: /Users/dev/my-project"))
    XCTAssertTrue(result.contains("Open app tabs: 3"))
    XCTAssertTrue(result.contains("Tasks to implement: 2"))
    XCTAssertTrue(result.hasPrefix("Status"))
  }

  func testComposeWithoutRepoFallsBackToWorkingDirectory() {
    let result = TelegramStartupStatement.compose(
      repositoryPath: nil,
      workingDirectoryPath: "/tmp/no-repo",
      openTabCount: 0,
      activeTaskCount: 0
    )

    XCTAssertTrue(result.contains("Repository: /tmp/no-repo"))
  }

  // MARK: - Edge Cases

  func testComposeZeroCounts() {
    let result = TelegramStartupStatement.compose(
      repositoryPath: "/repo",
      workingDirectoryPath: "/repo",
      openTabCount: 0,
      activeTaskCount: 0
    )

    XCTAssertTrue(result.contains("Open app tabs: 0"))
    XCTAssertTrue(result.contains("Tasks to implement: 0"))
  }

  func testComposeHighCounts() {
    let result = TelegramStartupStatement.compose(
      repositoryPath: "/repo",
      workingDirectoryPath: "/repo",
      openTabCount: 42,
      activeTaskCount: 17
    )

    XCTAssertTrue(result.contains("Open app tabs: 42"))
    XCTAssertTrue(result.contains("Tasks to implement: 17"))
  }

  // MARK: - Format

  func testComposeLineCount() {
    let result = TelegramStartupStatement.compose(
      repositoryPath: "/repo",
      workingDirectoryPath: "/repo",
      openTabCount: 1,
      activeTaskCount: 1
    )

    let lines = result.components(separatedBy: "\n")
    XCTAssertEqual(lines.count, 4)
    XCTAssertEqual(lines[0], "Status")
  }

  // MARK: - Task Count Semantics

  func testActiveTaskCountIncludesPendingRunningAndWaiting() {
    /// Verify the counting logic produces the right input.
    /// Given tasks: 2 pending, 1 running, 1 waiting-approval, 1 completed, 1 failed.
    /// A task can be both running AND waiting-approval — should not be double-counted.
    let tasks: [(TaskStatus, TaskApprovalState)] = [
      (.pending, .none),
      (.pending, .none),
      (.running, .none),
      (.running, .waiting),
      (.completed, .none),
      (.failed, .none),
      (.cancelled, .none),
      (.pending, .waiting),
    ]

    /// Count using the same logic as AppState: status pending/running OR approval waiting.
    let activeCount = tasks.filter { status, approval in
      status == .pending || status == .running || approval == .waiting
    }.count

    /// pending(2) + running(1) + running+waiting(1) + pending+waiting(1) = 5 unique tasks.
    XCTAssertEqual(activeCount, 5)

    let result = TelegramStartupStatement.compose(
      repositoryPath: "/repo",
      workingDirectoryPath: "/repo",
      openTabCount: 0,
      activeTaskCount: activeCount
    )

    XCTAssertTrue(result.contains("Tasks to implement: 5"))
  }
}
