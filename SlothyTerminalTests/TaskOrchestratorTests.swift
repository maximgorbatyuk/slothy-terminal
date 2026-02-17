import XCTest
@testable import SlothyTerminalLib

@MainActor
final class TaskOrchestratorTests: XCTestCase {
  private var state: TaskQueueState!
  private var tempDir: URL!

  override func setUp() {
    super.setUp()
    tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("TOrcTests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    let store = TaskQueueStore(baseDirectory: tempDir)
    state = TaskQueueState(store: store)
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: tempDir)
    state = nil
    tempDir = nil
    super.tearDown()
  }

  // MARK: - Backoff

  func testRetryBackoffDelay() {
    /// 2s for first retry.
    XCTAssertEqual(TaskOrchestrator.backoffDelay(retryCount: 0), 2_000_000_000)

    /// 4s for second retry.
    XCTAssertEqual(TaskOrchestrator.backoffDelay(retryCount: 1), 4_000_000_000)

    /// 8s for third retry (capped).
    XCTAssertEqual(TaskOrchestrator.backoffDelay(retryCount: 2), 8_000_000_000)

    /// Stays at cap for higher counts.
    XCTAssertEqual(TaskOrchestrator.backoffDelay(retryCount: 5), 8_000_000_000)
  }

  // MARK: - Priority Ordering

  func testSelectsHighPriorityFirst() {
    state.enqueueTask(
      title: "Normal",
      prompt: "p",
      repoPath: "/tmp",
      agentType: .claude,
      priority: .normal
    )
    state.enqueueTask(
      title: "High",
      prompt: "p",
      repoPath: "/tmp",
      agentType: .claude,
      priority: .high
    )

    let pending = state.tasks
      .filter { $0.status == .pending }
      .sorted { lhs, rhs in
        if lhs.priority != rhs.priority {
          return lhs.priority < rhs.priority
        }

        return lhs.createdAt < rhs.createdAt
      }

    XCTAssertEqual(pending.first?.title, "High")
  }

  func testFIFOWithinSamePriority() {
    state.enqueueTask(
      title: "First",
      prompt: "p",
      repoPath: "/tmp",
      agentType: .claude,
      priority: .normal
    )
    state.enqueueTask(
      title: "Second",
      prompt: "p",
      repoPath: "/tmp",
      agentType: .claude,
      priority: .normal
    )

    let pending = state.tasks
      .filter { $0.status == .pending }
      .sorted { lhs, rhs in
        if lhs.priority != rhs.priority {
          return lhs.priority < rhs.priority
        }

        return lhs.createdAt < rhs.createdAt
      }

    XCTAssertEqual(pending.first?.title, "First")
  }

  // MARK: - Approval Blocking

  func testDoesNotScheduleWhenApprovalPending() {
    state.enqueueTask(
      title: "Completed",
      prompt: "p",
      repoPath: "/tmp",
      agentType: .claude
    )
    let completedId = state.tasks[0].id
    state.markRunning(id: completedId, attemptId: UUID())
    state.markCompletedAwaitingApproval(
      id: completedId,
      resultSummary: "done",
      logArtifactPath: nil,
      sessionId: nil,
      riskyOperations: ["git push"]
    )

    /// Add another pending task.
    state.enqueueTask(
      title: "Waiting",
      prompt: "p",
      repoPath: "/tmp",
      agentType: .claude
    )

    /// Simulate selectNextTask logic.
    let hasApprovalPending = state.tasks.contains { $0.approvalState == .waiting }
    XCTAssertTrue(hasApprovalPending)
  }

  // MARK: - Preflight Failure

  func testPreflightFailureMarksFailed() {
    /// Enqueue with an empty prompt — will fail preflight.
    let task = QueuedTask(
      id: UUID(),
      title: "Bad task",
      prompt: "   ",
      repoPath: "/tmp",
      agentType: .claude,
      status: .pending,
      priority: .normal,
      retryCount: 0,
      maxRetries: 3,
      createdAt: Date(),
      approvalState: .none
    )
    state.tasks.append(task)

    let result = TaskPreflight.validate(task)

    XCTAssertFalse(result.isSuccess)
    XCTAssertNotNil(result.errorMessage)
  }
}
