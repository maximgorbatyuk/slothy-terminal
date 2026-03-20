import XCTest
@testable import SlothyTerminalLib

@MainActor
final class InjectionOrchestratorTests: XCTestCase {
  private var registry: TerminalSurfaceRegistry!
  private var tabProvider: MockInjectionTabProvider!
  private var orchestrator: InjectionOrchestrator!
  private var emittedEvents: [InjectionEvent]!

  override func setUp() {
    super.setUp()
    registry = TerminalSurfaceRegistry()
    tabProvider = MockInjectionTabProvider()
    orchestrator = InjectionOrchestrator(registry: registry, tabProvider: tabProvider)
    emittedEvents = []
    orchestrator.onEvent = { [weak self] event in
      self?.emittedEvents.append(event)
    }
  }

  override func tearDown() {
    orchestrator = nil
    tabProvider = nil
    registry = nil
    emittedEvents = nil
    super.tearDown()
  }

  // MARK: - Submit to Active Tab

  func testSubmitToActiveTab() {
    let tabId = UUID()
    let surface = MockInjectionSurface()
    registry.register(tabId: tabId, surface: surface)
    tabProvider.activeTabId = tabId

    let request = InjectionRequest(
      payload: .command("echo hello", submit: .execute),
      target: .activeTab
    )
    let result = orchestrator.submit(request)

    XCTAssertEqual(result.status, .completed)
    XCTAssertEqual(surface.commandCalls.count, 1)
    XCTAssertEqual(surface.commandCalls.first?.command, "echo hello")
    XCTAssertEqual(surface.commandCalls.first?.submit, .execute)
  }

  // MARK: - Submit to Specific Tab

  func testSubmitToSpecificTabId() {
    let tabId = UUID()
    let surface = MockInjectionSurface()
    registry.register(tabId: tabId, surface: surface)

    let request = InjectionRequest(
      payload: .text("test input"),
      target: .tabId(tabId)
    )
    let result = orchestrator.submit(request)

    XCTAssertEqual(result.status, .completed)
    XCTAssertEqual(surface.textCalls, ["test input"])
  }

  // MARK: - No Matching Tabs

  func testNoMatchingTabsFails() {
    let request = InjectionRequest(
      payload: .text("orphan"),
      target: .activeTab
    )
    let result = orchestrator.submit(request)

    XCTAssertEqual(result.status, .failed)
  }

  func testNoMatchingTabsEmitsFailedWithNilTabId() {
    let request = InjectionRequest(
      payload: .text("orphan"),
      target: .activeTab
    )
    _ = orchestrator.submit(request)

    let failedEvent = emittedEvents.first {
      if case .requestFailed = $0 { return true }
      return false
    }
    if case .requestFailed(let reqId, let tabId, _) = failedEvent {
      XCTAssertEqual(reqId, request.id)
      XCTAssertNil(tabId)
    } else {
      XCTFail("Expected requestFailed event")
    }
  }

  // MARK: - FIFO Order

  func testFifoOrderPerTab() {
    let tabId = UUID()
    let surface = MockInjectionSurface()
    registry.register(tabId: tabId, surface: surface)
    tabProvider.activeTabId = tabId

    let req1 = InjectionRequest(payload: .text("first"), target: .activeTab)
    let req2 = InjectionRequest(payload: .text("second"), target: .activeTab)

    _ = orchestrator.submit(req1)
    _ = orchestrator.submit(req2)

    XCTAssertEqual(surface.textCalls, ["first", "second"])
  }

  // MARK: - Cancel

  func testCancelPendingRequest() {
    let tabId = UUID()
    let surface = MockInjectionSurface()
    registry.register(tabId: tabId, surface: surface)
    tabProvider.activeTabId = tabId

    let request = InjectionRequest(
      payload: .text("will cancel"),
      target: .activeTab
    )

    // Submit completes immediately for Phase 1, so cancel after completion is a no-op.
    let result = orchestrator.submit(request)
    orchestrator.cancel(requestId: request.id)

    // Cancel after completion should be a no-op (not change status).
    XCTAssertEqual(orchestrator.status(for: request.id), .completed)
    XCTAssertEqual(result.status, .completed)
  }

  // MARK: - Surface Failure

  func testSurfaceFailureResultsInFailed() {
    let tabId = UUID()
    let surface = MockInjectionSurface()
    surface.shouldSucceed = false
    registry.register(tabId: tabId, surface: surface)
    tabProvider.activeTabId = tabId

    let request = InjectionRequest(
      payload: .text("fail me"),
      target: .activeTab
    )
    let result = orchestrator.submit(request)

    XCTAssertEqual(result.status, .failed)
    XCTAssertEqual(surface.textCalls, ["fail me"])
  }

  // MARK: - Event Emission

  func testEventEmissionSequence() {
    let tabId = UUID()
    let surface = MockInjectionSurface()
    registry.register(tabId: tabId, surface: surface)
    tabProvider.activeTabId = tabId

    let request = InjectionRequest(
      payload: .control(.ctrlC),
      target: .activeTab
    )
    _ = orchestrator.submit(request)

    // Expected sequence: accepted → queued → written → completed.
    XCTAssertEqual(emittedEvents.count, 4)

    guard emittedEvents.count == 4 else {
      return
    }

    XCTAssertEqual(emittedEvents[0], .requestAccepted(requestId: request.id))
    XCTAssertEqual(emittedEvents[1], .requestQueued(requestId: request.id, tabId: tabId))
    XCTAssertEqual(emittedEvents[2], .requestWritten(requestId: request.id, tabId: tabId))
    XCTAssertEqual(emittedEvents[3], .requestCompleted(requestId: request.id, tabId: tabId))
  }

  // MARK: - Multi-Tab Independence

  func testMultiTabIndependence() {
    let tab1 = UUID()
    let tab2 = UUID()
    let surface1 = MockInjectionSurface()
    let surface2 = MockInjectionSurface()
    surface1.shouldSucceed = false

    registry.register(tabId: tab1, surface: surface1)
    registry.register(tabId: tab2, surface: surface2)
    tabProvider.tabIds = [tab1, tab2]

    let request = InjectionRequest(
      payload: .text("multi"),
      target: .filtered(agentType: nil, mode: nil)
    )
    _ = orchestrator.submit(request)

    // Both surfaces should receive the injection.
    XCTAssertEqual(surface1.textCalls, ["multi"])
    XCTAssertEqual(surface2.textCalls, ["multi"])
  }

  func testMultiTabFailureStatusPreserved() {
    let tab1 = UUID()
    let tab2 = UUID()
    let surface1 = MockInjectionSurface()
    let surface2 = MockInjectionSurface()
    surface1.shouldSucceed = false

    registry.register(tabId: tab1, surface: surface1)
    registry.register(tabId: tab2, surface: surface2)
    tabProvider.tabIds = [tab1, tab2]

    let request = InjectionRequest(
      payload: .text("multi"),
      target: .filtered(agentType: nil, mode: nil)
    )
    let result = orchestrator.submit(request)

    // Tab1 fails first — status should stay .failed even though tab2 succeeds.
    XCTAssertEqual(result.status, .failed)
    XCTAssertEqual(orchestrator.status(for: request.id), .failed)
  }

  // MARK: - Status Query

  func testStatusQuery() {
    let tabId = UUID()
    let surface = MockInjectionSurface()
    registry.register(tabId: tabId, surface: surface)
    tabProvider.activeTabId = tabId

    let request = InjectionRequest(
      payload: .text("status check"),
      target: .activeTab
    )
    _ = orchestrator.submit(request)

    XCTAssertEqual(orchestrator.status(for: request.id), .completed)
    XCTAssertNil(orchestrator.status(for: UUID()))
  }

  // MARK: - Filtered Target

  func testFilteredTargetResolution() {
    let tab1 = UUID()
    let tab2 = UUID()
    let surface1 = MockInjectionSurface()
    let surface2 = MockInjectionSurface()
    registry.register(tabId: tab1, surface: surface1)
    registry.register(tabId: tab2, surface: surface2)
    tabProvider.tabIds = [tab1, tab2]
    tabProvider.tabModes = [tab1: .terminal, tab2: .terminal]

    let request = InjectionRequest(
      payload: .paste("filtered paste", mode: .plain),
      target: .filtered(agentType: nil, mode: .terminal)
    )
    _ = orchestrator.submit(request)

    XCTAssertEqual(surface1.pasteCalls.count, 1)
    XCTAssertEqual(surface2.pasteCalls.count, 1)
    XCTAssertEqual(surface1.pasteCalls.first?.text, "filtered paste")
    XCTAssertEqual(surface1.pasteCalls.first?.mode, .plain)
  }

  func testFilteredByModeFiltersCorrectly() {
    let terminalTab = UUID()
    let chatTab = UUID()
    let surface1 = MockInjectionSurface()
    let surface2 = MockInjectionSurface()
    registry.register(tabId: terminalTab, surface: surface1)
    registry.register(tabId: chatTab, surface: surface2)
    tabProvider.tabIds = [terminalTab, chatTab]
    tabProvider.tabModes = [terminalTab: .terminal, chatTab: .git]

    let request = InjectionRequest(
      payload: .text("terminal only"),
      target: .filtered(agentType: nil, mode: .terminal)
    )
    _ = orchestrator.submit(request)

    XCTAssertEqual(surface1.textCalls, ["terminal only"])
    XCTAssertEqual(surface2.textCalls, [])
  }

  func testFilteredByAgentTypeFiltersCorrectly() {
    let claudeTab = UUID()
    let openCodeTab = UUID()
    let surface1 = MockInjectionSurface()
    let surface2 = MockInjectionSurface()
    registry.register(tabId: claudeTab, surface: surface1)
    registry.register(tabId: openCodeTab, surface: surface2)
    tabProvider.tabIds = [claudeTab, openCodeTab]
    tabProvider.tabAgentTypes = [claudeTab: .claude, openCodeTab: .opencode]

    let request = InjectionRequest(
      payload: .text("claude only"),
      target: .filtered(agentType: .claude, mode: nil)
    )
    _ = orchestrator.submit(request)

    // Only the claude tab should receive the injection.
    XCTAssertEqual(surface1.textCalls, ["claude only"])
    XCTAssertEqual(surface2.textCalls, [])
  }

  // MARK: - Timeout

  func testTimeoutEntryIsSkipped() {
    let tabId = UUID()
    let surface = MockInjectionSurface()
    registry.register(tabId: tabId, surface: surface)
    tabProvider.activeTabId = tabId

    // Create request with createdAt far in the past so it times out immediately.
    let request = InjectionRequest(
      payload: .text("expired"),
      target: .activeTab,
      createdAt: Date(timeIntervalSinceNow: -20),
      timeoutSeconds: 5
    )
    let result = orchestrator.submit(request)

    XCTAssertEqual(result.status, .timeout)
    // Surface should NOT have received any injection.
    XCTAssertEqual(surface.textCalls, [])

    // Verify timeout event was emitted.
    let timeoutEvent = emittedEvents.contains {
      if case .requestTimedOut(let reqId, _) = $0, reqId == request.id {
        return true
      }
      return false
    }
    XCTAssertTrue(timeoutEvent)
  }

  // MARK: - All Payload Types

  func testAllPayloadTypes() {
    let tabId = UUID()
    let surface = MockInjectionSurface()
    registry.register(tabId: tabId, surface: surface)
    tabProvider.activeTabId = tabId

    let payloads: [InjectionPayload] = [
      .text("raw text"),
      .command("cmd", submit: .insert),
      .paste("paste", mode: .bracketed),
      .control(.ctrlD),
      .key(keyCode: 36, modifiers: 0),
    ]

    for payload in payloads {
      let request = InjectionRequest(payload: payload, target: .activeTab)
      let result = orchestrator.submit(request)
      XCTAssertEqual(result.status, .completed)
    }

    XCTAssertEqual(surface.textCalls, ["raw text"])
    XCTAssertEqual(surface.commandCalls.count, 1)
    XCTAssertEqual(surface.pasteCalls.count, 1)
    XCTAssertEqual(surface.controlCalls, [.ctrlD])
    XCTAssertEqual(surface.keyCalls.count, 1)
  }

  // MARK: - No Surface Registered

  func testNoSurfaceRegisteredFails() {
    let tabId = UUID()
    tabProvider.activeTabId = tabId

    // Tab exists in provider but no surface registered.
    let request = InjectionRequest(
      payload: .text("no surface"),
      target: .activeTab
    )
    let result = orchestrator.submit(request)

    XCTAssertEqual(result.status, .failed)
  }

  // MARK: - History Eviction

  func testHistoryEvictsOldEntries() {
    let tabId = UUID()
    let surface = MockInjectionSurface()
    registry.register(tabId: tabId, surface: surface)
    tabProvider.activeTabId = tabId

    var firstRequestId: UUID?
    for i in 0...(InjectionOrchestrator.maxHistorySize) {
      let request = InjectionRequest(
        payload: .text("msg \(i)"),
        target: .activeTab
      )
      _ = orchestrator.submit(request)
      if i == 0 { firstRequestId = request.id }
    }

    // The very first request should have been evicted from history.
    XCTAssertNil(orchestrator.status(for: firstRequestId!))
  }
}
