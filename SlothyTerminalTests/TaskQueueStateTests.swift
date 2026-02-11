import XCTest
@testable import SlothyTerminalLib

@MainActor
final class TaskQueueStateTests: XCTestCase {
  private var state: TaskQueueState!
  private var tempDir: URL!

  override func setUp() {
    super.setUp()
    tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("TQStateTests-\(UUID().uuidString)", isDirectory: true)
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

  // MARK: - Enqueue

  func testEnqueueAddsTask() {
    state.enqueueTask(
      title: "Test",
      prompt: "Do something",
      repoPath: "/tmp",
      agentType: .claude
    )

    XCTAssertEqual(state.tasks.count, 1)
    XCTAssertEqual(state.tasks[0].title, "Test")
    XCTAssertEqual(state.tasks[0].status, .pending)
  }

  // MARK: - Remove

  func testRemovePendingTask() {
    state.enqueueTask(
      title: "Remove me",
      prompt: "prompt",
      repoPath: "/tmp",
      agentType: .claude
    )
    let id = state.tasks[0].id

    state.removeTask(id: id)

    XCTAssertTrue(state.tasks.isEmpty)
  }

  func testRemoveRunningTaskIsNoOp() {
    state.enqueueTask(
      title: "Running task",
      prompt: "prompt",
      repoPath: "/tmp",
      agentType: .claude
    )
    let id = state.tasks[0].id
    state.markRunning(id: id, attemptId: UUID())

    state.removeTask(id: id)

    XCTAssertEqual(state.tasks.count, 1)
    XCTAssertEqual(state.tasks[0].status, .running)
  }

  // MARK: - Retry

  func testRetryFailedTask() {
    state.enqueueTask(
      title: "Fail",
      prompt: "prompt",
      repoPath: "/tmp",
      agentType: .claude
    )
    let id = state.tasks[0].id
    state.markRunning(id: id, attemptId: UUID())
    state.markFailed(
      id: id,
      error: "oops",
      exitReason: .failed,
      failureKind: .transient,
      logArtifactPath: nil
    )

    state.retryTask(id: id)

    XCTAssertEqual(state.tasks[0].status, .pending)
    XCTAssertEqual(state.tasks[0].retryCount, 1)
    XCTAssertNil(state.tasks[0].startedAt)
  }

  // MARK: - Cancel

  func testCancelPendingTask() {
    state.enqueueTask(
      title: "Cancel me",
      prompt: "prompt",
      repoPath: "/tmp",
      agentType: .claude
    )
    let id = state.tasks[0].id

    state.cancelTask(id: id)

    XCTAssertEqual(state.tasks[0].status, .cancelled)
    XCTAssertEqual(state.tasks[0].exitReason, .cancelled)
  }

  // MARK: - Mark Running

  func testMarkRunning() {
    state.enqueueTask(
      title: "Run me",
      prompt: "prompt",
      repoPath: "/tmp",
      agentType: .claude
    )
    let id = state.tasks[0].id
    let attemptId = UUID()

    state.markRunning(id: id, attemptId: attemptId)

    XCTAssertEqual(state.tasks[0].status, .running)
    XCTAssertEqual(state.tasks[0].runAttemptId, attemptId)
    XCTAssertNotNil(state.tasks[0].startedAt)
  }

  // MARK: - Mark Completed

  func testMarkCompleted() {
    state.enqueueTask(
      title: "Complete me",
      prompt: "prompt",
      repoPath: "/tmp",
      agentType: .claude
    )
    let id = state.tasks[0].id
    state.markRunning(id: id, attemptId: UUID())

    state.markCompleted(
      id: id,
      resultSummary: "Done!",
      logArtifactPath: "/tmp/log",
      sessionId: "s1"
    )

    XCTAssertEqual(state.tasks[0].status, .completed)
    XCTAssertEqual(state.tasks[0].resultSummary, "Done!")
    XCTAssertEqual(state.tasks[0].exitReason, .completed)
    XCTAssertNotNil(state.tasks[0].finishedAt)
  }

  // MARK: - Mark Failed

  func testMarkFailed() {
    state.enqueueTask(
      title: "Fail me",
      prompt: "prompt",
      repoPath: "/tmp",
      agentType: .claude
    )
    let id = state.tasks[0].id
    state.markRunning(id: id, attemptId: UUID())

    state.markFailed(
      id: id,
      error: "crash",
      exitReason: .failed,
      failureKind: .permanent,
      logArtifactPath: nil
    )

    XCTAssertEqual(state.tasks[0].status, .failed)
    XCTAssertEqual(state.tasks[0].lastError, "crash")
    XCTAssertEqual(state.tasks[0].failureKind, .permanent)
  }

  // MARK: - Mark Failed for Retry

  func testMarkFailedForRetry() {
    state.enqueueTask(
      title: "Retry me",
      prompt: "prompt",
      repoPath: "/tmp",
      agentType: .claude
    )
    let id = state.tasks[0].id
    state.markRunning(id: id, attemptId: UUID())

    state.markFailedForRetry(
      id: id,
      error: "transient",
      logArtifactPath: nil,
      failureKind: .transient
    )

    XCTAssertEqual(state.tasks[0].status, .pending)
    XCTAssertEqual(state.tasks[0].retryCount, 1)
    XCTAssertEqual(state.tasks[0].lastError, "transient")
  }

  // MARK: - Approval

  func testApproveTask() {
    state.enqueueTask(
      title: "Approve me",
      prompt: "prompt",
      repoPath: "/tmp",
      agentType: .claude
    )
    let id = state.tasks[0].id
    state.markRunning(id: id, attemptId: UUID())
    state.markCompletedAwaitingApproval(
      id: id,
      resultSummary: "done",
      logArtifactPath: nil,
      sessionId: nil,
      riskyOperations: ["git push"]
    )

    XCTAssertEqual(state.tasks[0].approvalState, .waiting)

    state.approveTask(id: id)

    XCTAssertEqual(state.tasks[0].approvalState, .approved)
    XCTAssertEqual(state.tasks[0].status, .completed)
  }

  func testRejectTask() {
    state.enqueueTask(
      title: "Reject me",
      prompt: "prompt",
      repoPath: "/tmp",
      agentType: .claude
    )
    let id = state.tasks[0].id
    state.markRunning(id: id, attemptId: UUID())
    state.markCompletedAwaitingApproval(
      id: id,
      resultSummary: "done",
      logArtifactPath: nil,
      sessionId: nil,
      riskyOperations: ["rm -rf /"]
    )

    state.rejectTask(id: id)

    XCTAssertEqual(state.tasks[0].approvalState, .rejected)
    XCTAssertEqual(state.tasks[0].status, .failed)
    XCTAssertEqual(state.tasks[0].exitReason, .approvalRejected)
  }

  // MARK: - Queue Changed Callback

  func testEnqueueDoesNotFireCallback() {
    var callbackCount = 0
    state.onQueueChanged = { callbackCount += 1 }

    state.enqueueTask(
      title: "T1",
      prompt: "p",
      repoPath: "/tmp",
      agentType: .claude
    )

    XCTAssertEqual(callbackCount, 0)
  }

  func testRetryFiresCallback() {
    state.enqueueTask(
      title: "T1",
      prompt: "p",
      repoPath: "/tmp",
      agentType: .claude
    )
    let id = state.tasks[0].id
    state.markRunning(id: id, attemptId: UUID())
    state.markFailed(
      id: id,
      error: "err",
      exitReason: .failed,
      failureKind: .transient,
      logArtifactPath: nil
    )

    var callbackCount = 0
    state.onQueueChanged = { callbackCount += 1 }

    state.retryTask(id: id)

    XCTAssertEqual(callbackCount, 1)
  }
}
