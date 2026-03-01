import XCTest
@testable import SlothyTerminalLib

@MainActor
final class TaskInjectionRouterTests: XCTestCase {
  private var provider: MockTaskInjectionProvider!
  private var router: TaskInjectionRouter!

  override func setUp() {
    super.setUp()
    provider = MockTaskInjectionProvider()
    router = TaskInjectionRouter(provider: provider)
  }

  override func tearDown() {
    router = nil
    provider = nil
    super.tearDown()
  }

  // MARK: - Helpers

  private func makeTask(
    agentType: AgentType = .claude,
    repoPath: String = "/tmp/myrepo",
    prompt: String = "Fix the bug"
  ) -> QueuedTask {
    QueuedTask(
      id: UUID(),
      title: "Test task",
      prompt: prompt,
      repoPath: repoPath,
      agentType: agentType,
      status: .pending,
      priority: .normal,
      retryCount: 0,
      maxRetries: 3,
      createdAt: Date(),
      approvalState: .none
    )
  }

  private func makeLogCollector() -> TaskLogCollector {
    TaskLogCollector(taskId: UUID(), attemptId: UUID())
  }

  private func makeCandidate(
    tabId: UUID = UUID(),
    agentType: AgentType = .claude,
    workingDirectory: String = "/tmp/myrepo",
    isActive: Bool = false,
    isRegistered: Bool = true
  ) -> InjectableTabCandidate {
    InjectableTabCandidate(
      tabId: tabId,
      agentType: agentType,
      workingDirectory: URL(fileURLWithPath: workingDirectory),
      isActive: isActive,
      isRegistered: isRegistered
    )
  }

  // MARK: - Injection Success

  func testInjectionSuccessCompletesWithoutFallback() {
    let tabId = UUID()
    provider.candidates = [
      makeCandidate(tabId: tabId, agentType: .claude, workingDirectory: "/tmp/myrepo")
    ]
    provider.injectionResultStatus = .completed

    let task = makeTask(agentType: .claude, repoPath: "/tmp/myrepo")
    let result = router.attemptInjection(task: task, logCollector: makeLogCollector())

    guard case .injected(_, let resultTabId, let summary) = result else {
      XCTFail("Expected .injected, got \(result)")
      return
    }

    XCTAssertEqual(resultTabId, tabId)
    XCTAssertTrue(summary.contains("Claude"))
    XCTAssertTrue(summary.contains("terminal tab"))
    XCTAssertTrue(provider.submitCalled)
  }

  // MARK: - No Matching Tab Fallback

  func testNoMatchingTabFallsBackToHeadless() {
    /// No candidates at all.
    provider.candidates = []

    let task = makeTask(agentType: .claude)
    let result = router.attemptInjection(task: task, logCollector: makeLogCollector())

    guard case .noMatchingTab = result else {
      XCTFail("Expected .noMatchingTab, got \(result)")
      return
    }

    XCTAssertFalse(provider.submitCalled)
  }

  // MARK: - Injection Submission Failure

  func testInjectionSubmissionFailureFallsBack() {
    provider.candidates = [
      makeCandidate(agentType: .claude, workingDirectory: "/tmp/myrepo")
    ]
    provider.submitReturnsNil = true

    let task = makeTask(agentType: .claude, repoPath: "/tmp/myrepo")
    let result = router.attemptInjection(task: task, logCollector: makeLogCollector())

    guard case .failed(let reason) = result else {
      XCTFail("Expected .failed, got \(result)")
      return
    }

    XCTAssertTrue(reason.contains("unavailable"))
  }

  func testInjectionStatusFailedFallsBack() {
    provider.candidates = [
      makeCandidate(agentType: .claude, workingDirectory: "/tmp/myrepo")
    ]
    provider.injectionResultStatus = .failed

    let task = makeTask(agentType: .claude, repoPath: "/tmp/myrepo")
    let result = router.attemptInjection(task: task, logCollector: makeLogCollector())

    guard case .failed = result else {
      XCTFail("Expected .failed, got \(result)")
      return
    }

    XCTAssertTrue(provider.submitCalled)
  }

  func testInjectionStatusCancelledFallsBack() {
    provider.candidates = [
      makeCandidate(agentType: .claude, workingDirectory: "/tmp/myrepo")
    ]
    provider.injectionResultStatus = .cancelled

    let task = makeTask(agentType: .claude, repoPath: "/tmp/myrepo")
    let result = router.attemptInjection(task: task, logCollector: makeLogCollector())

    guard case .failed(let reason) = result else {
      XCTFail("Expected .failed, got \(result)")
      return
    }

    XCTAssertTrue(reason.contains("cancelled"))
    XCTAssertTrue(provider.submitCalled)
  }

  func testInjectionStatusTimeoutFallsBack() {
    provider.candidates = [
      makeCandidate(agentType: .claude, workingDirectory: "/tmp/myrepo")
    ]
    provider.injectionResultStatus = .timeout

    let task = makeTask(agentType: .claude, repoPath: "/tmp/myrepo")
    let result = router.attemptInjection(task: task, logCollector: makeLogCollector())

    guard case .failed(let reason) = result else {
      XCTFail("Expected .failed, got \(result)")
      return
    }

    XCTAssertTrue(reason.contains("timed out"))
  }

  // MARK: - Active Tab Preference

  func testPrefersActiveMatchingTab() {
    let inactiveId = UUID()
    let activeId = UUID()

    provider.candidates = [
      makeCandidate(
        tabId: inactiveId,
        agentType: .claude,
        workingDirectory: "/tmp/myrepo",
        isActive: false
      ),
      makeCandidate(
        tabId: activeId,
        agentType: .claude,
        workingDirectory: "/tmp/myrepo",
        isActive: true
      ),
    ]

    let task = makeTask(agentType: .claude, repoPath: "/tmp/myrepo")
    let result = router.attemptInjection(task: task, logCollector: makeLogCollector())

    guard case .injected(_, let resultTabId, _) = result else {
      XCTFail("Expected .injected, got \(result)")
      return
    }

    XCTAssertEqual(resultTabId, activeId)
  }

  func testFallsBackToFirstWhenNoActiveTab() {
    let firstId = UUID()
    let secondId = UUID()

    provider.candidates = [
      makeCandidate(
        tabId: firstId,
        agentType: .claude,
        workingDirectory: "/tmp/myrepo",
        isActive: false
      ),
      makeCandidate(
        tabId: secondId,
        agentType: .claude,
        workingDirectory: "/tmp/myrepo",
        isActive: false
      ),
    ]

    let task = makeTask(agentType: .claude, repoPath: "/tmp/myrepo")
    let result = router.attemptInjection(task: task, logCollector: makeLogCollector())

    guard case .injected(_, let resultTabId, _) = result else {
      XCTFail("Expected .injected, got \(result)")
      return
    }

    XCTAssertEqual(resultTabId, firstId)
  }

  // MARK: - Directory Mismatch

  func testDirectoryMismatchDoesNotInject() {
    provider.candidates = [
      makeCandidate(
        agentType: .claude,
        workingDirectory: "/tmp/other-repo"
      ),
    ]

    let task = makeTask(agentType: .claude, repoPath: "/tmp/myrepo")
    let result = router.attemptInjection(task: task, logCollector: makeLogCollector())

    guard case .noMatchingTab = result else {
      XCTFail("Expected .noMatchingTab, got \(result)")
      return
    }

    XCTAssertFalse(provider.submitCalled)
  }

  // MARK: - Agent Type Mismatch

  func testAgentTypeMismatchDoesNotInject() {
    provider.candidates = [
      makeCandidate(
        agentType: .opencode,
        workingDirectory: "/tmp/myrepo"
      ),
    ]

    let task = makeTask(agentType: .claude, repoPath: "/tmp/myrepo")
    let result = router.attemptInjection(task: task, logCollector: makeLogCollector())

    guard case .noMatchingTab = result else {
      XCTFail("Expected .noMatchingTab, got \(result)")
      return
    }
  }

  // MARK: - Unregistered Surface

  func testUnregisteredSurfaceFallsBack() {
    provider.candidates = [
      makeCandidate(
        agentType: .claude,
        workingDirectory: "/tmp/myrepo",
        isRegistered: false
      ),
    ]

    let task = makeTask(agentType: .claude, repoPath: "/tmp/myrepo")
    let result = router.attemptInjection(task: task, logCollector: makeLogCollector())

    guard case .noMatchingTab = result else {
      XCTFail("Expected .noMatchingTab, got \(result)")
      return
    }

    XCTAssertFalse(provider.submitCalled)
  }

  // MARK: - Cancellation

  func testCancelInjectionCallsProvider() {
    let requestId = UUID()
    router.cancelInjection(requestId: requestId)

    XCTAssertTrue(provider.cancelCalled)
    XCTAssertEqual(provider.lastCancelledRequestId, requestId)
  }

  // MARK: - Path Normalization

  func testNormalizePathExpandsTilde() {
    let homePath = FileManager.default.homeDirectoryForCurrentUser.path
    let result = TaskInjectionRouter.normalizePath("~/projects")

    XCTAssertEqual(result, "\(homePath)/projects")
  }

  func testNormalizePathStripsTrailingSlash() {
    let result = TaskInjectionRouter.normalizePath("/tmp/myrepo/")

    XCTAssertEqual(result, "/tmp/myrepo")
  }

  func testNormalizePathMatchesEquivalentPaths() {
    let a = TaskInjectionRouter.normalizePath("/tmp/myrepo")
    let b = TaskInjectionRouter.normalizePath("/tmp/myrepo/")

    XCTAssertEqual(a, b)
  }

  // MARK: - OpenCode Agent

  func testOpenCodeInjectionSuccess() {
    let tabId = UUID()
    provider.candidates = [
      makeCandidate(
        tabId: tabId,
        agentType: .opencode,
        workingDirectory: "/tmp/myrepo"
      ),
    ]

    let task = makeTask(agentType: .opencode, repoPath: "/tmp/myrepo")
    let result = router.attemptInjection(task: task, logCollector: makeLogCollector())

    guard case .injected(_, let resultTabId, let summary) = result else {
      XCTFail("Expected .injected, got \(result)")
      return
    }

    XCTAssertEqual(resultTabId, tabId)
    XCTAssertTrue(summary.contains("OpenCode"))
  }

  // MARK: - Injection Payload

  func testInjectionPayloadIsCommandWithExecute() {
    let tabId = UUID()
    provider.candidates = [
      makeCandidate(tabId: tabId, agentType: .claude, workingDirectory: "/tmp/myrepo")
    ]

    let prompt = "Refactor the auth module"
    let task = makeTask(agentType: .claude, repoPath: "/tmp/myrepo", prompt: prompt)
    _ = router.attemptInjection(task: task, logCollector: makeLogCollector())

    guard let submitted = provider.lastSubmittedRequest else {
      XCTFail("Expected injection request to be submitted")
      return
    }

    XCTAssertEqual(submitted.payload, .command(prompt, submit: .execute))
    XCTAssertEqual(submitted.target, .tabId(tabId))
    XCTAssertEqual(submitted.origin, .automation)
  }
}
