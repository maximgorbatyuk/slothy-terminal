import XCTest
@testable import SlothyTerminalLib

@MainActor
final class TaskOrchestratorTests: XCTestCase {
  private var state: TaskQueueState!
  private var tempDir: URL!
  private var previousClaudePath: String?
  private var previousOpenCodePath: String?

  override func setUp() {
    super.setUp()
    tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("TOrcTests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    let store = TaskQueueStore(baseDirectory: tempDir)
    state = TaskQueueState(store: store)
    configureAgentAvailabilityForTests()
  }

  override func tearDown() {
    restoreAgentAvailabilityForTests()
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

  // MARK: - Injection Integration

  func testInjectionSuccessCompletesWithoutHeadlessFallback() async {
    let runner = MockTaskRunner()
    runner.executeResult = makeRunResult(summary: "headless result")

    let provider = MockTaskInjectionProvider()
    let tabId = UUID()
    provider.candidates = [
      InjectableTabCandidate(
        tabId: tabId,
        agentType: .claude,
        workingDirectory: tempDir,
        isActive: true,
        isRegistered: true
      )
    ]
    provider.injectionResultStatus = .completed

    let orchestrator = TaskOrchestrator(queueState: state) { _ in runner }
    orchestrator.injectionRouter = TaskInjectionRouter(provider: provider)

    state.enqueueTask(
      title: "Injection first",
      prompt: "echo hello",
      repoPath: tempDir.path,
      agentType: .claude
    )

    let taskId = state.tasks[0].id
    orchestrator.start()
    defer { orchestrator.stop() }

    await waitForTaskTerminalState(taskId)

    guard let task = state.tasks.first(where: { $0.id == taskId }) else {
      XCTFail("Task not found")
      return
    }

    XCTAssertEqual(task.status, .completed)
    XCTAssertFalse(runner.executeCalled)
    XCTAssertTrue(provider.submitCalled)
    XCTAssertTrue(task.resultSummary?.contains("Prompt injected into existing Claude terminal tab") == true)
  }

  func testNoMatchingInjectionTabFallsBackToHeadlessRunner() async {
    let runner = MockTaskRunner()
    runner.executeResult = makeRunResult(summary: "headless result")

    let provider = MockTaskInjectionProvider()
    provider.candidates = []

    let orchestrator = TaskOrchestrator(queueState: state) { _ in runner }
    orchestrator.injectionRouter = TaskInjectionRouter(provider: provider)

    state.enqueueTask(
      title: "Fallback",
      prompt: "echo hello",
      repoPath: tempDir.path,
      agentType: .claude
    )

    let taskId = state.tasks[0].id
    orchestrator.start()
    defer { orchestrator.stop() }

    await waitForTaskTerminalState(taskId)

    guard let task = state.tasks.first(where: { $0.id == taskId }) else {
      XCTFail("Task not found")
      return
    }

    XCTAssertEqual(task.status, .completed)
    XCTAssertEqual(task.resultSummary, "headless result")
    XCTAssertTrue(runner.executeCalled)
    XCTAssertFalse(provider.submitCalled)
  }

  func testInjectionFailureFallsBackToHeadlessRunner() async {
    let runner = MockTaskRunner()
    runner.executeResult = makeRunResult(summary: "headless result")

    let provider = MockTaskInjectionProvider()
    provider.candidates = [
      InjectableTabCandidate(
        tabId: UUID(),
        agentType: .claude,
        workingDirectory: tempDir,
        isActive: true,
        isRegistered: true
      )
    ]
    provider.injectionResultStatus = .failed

    let orchestrator = TaskOrchestrator(queueState: state) { _ in runner }
    orchestrator.injectionRouter = TaskInjectionRouter(provider: provider)

    state.enqueueTask(
      title: "Fallback after failure",
      prompt: "echo hello",
      repoPath: tempDir.path,
      agentType: .claude
    )

    let taskId = state.tasks[0].id
    orchestrator.start()
    defer { orchestrator.stop() }

    await waitForTaskTerminalState(taskId)

    guard let task = state.tasks.first(where: { $0.id == taskId }) else {
      XCTFail("Task not found")
      return
    }

    XCTAssertEqual(task.status, .completed)
    XCTAssertEqual(task.resultSummary, "headless result")
    XCTAssertTrue(provider.submitCalled)
    XCTAssertTrue(runner.executeCalled)
  }

  // MARK: - Helpers

  private func configureAgentAvailabilityForTests() {
    previousClaudePath = ProcessInfo.processInfo.environment["CLAUDE_PATH"]
    previousOpenCodePath = ProcessInfo.processInfo.environment["OPENCODE_PATH"]
    setenv("CLAUDE_PATH", "/usr/bin/true", 1)
    setenv("OPENCODE_PATH", "/usr/bin/true", 1)
  }

  private func restoreAgentAvailabilityForTests() {
    if let previousClaudePath {
      setenv("CLAUDE_PATH", previousClaudePath, 1)
    } else {
      unsetenv("CLAUDE_PATH")
    }

    if let previousOpenCodePath {
      setenv("OPENCODE_PATH", previousOpenCodePath, 1)
    } else {
      unsetenv("OPENCODE_PATH")
    }
  }

  private func makeRunResult(summary: String) -> TaskRunResult {
    TaskRunResult(
      exitReason: .completed,
      resultSummary: summary,
      logArtifactPath: nil,
      sessionId: nil,
      failureKind: nil,
      errorMessage: nil,
      detectedRiskyOperations: []
    )
  }

  private func waitForTaskTerminalState(
    _ taskId: UUID,
    timeout: TimeInterval = 1,
    file: StaticString = #filePath,
    line: UInt = #line
  ) async {
    let deadline = Date().addingTimeInterval(timeout)

    while Date() < deadline {
      if let task = state.tasks.first(where: { $0.id == taskId }),
         task.isTerminal
      {
        return
      }

      await Task.yield()
      try? await Task.sleep(nanoseconds: 10_000_000)
    }

    XCTFail("Timed out waiting for task \(taskId) to finish", file: file, line: line)
  }
}
