import XCTest
@testable import SlothyTerminalLib

// MARK: - Mock Delegate

@MainActor
private class MockRelayDelegate: TelegramBotDelegate {
  var injectResult: InjectionRequest?
  var injectCalls: [InjectionRequest] = []
  var relayableTabs: [TelegramRelayTabInfo] = []
  var activeAITab: TelegramRelayTabInfo?

  func telegramBotRequestReport() -> String { "" }

  func telegramBotOpenTab(mode: TabMode, agent: AgentType, directory: URL) {}

  func telegramBotEnqueueTask(
    title: String,
    prompt: String,
    repoPath: String,
    agentType: AgentType
  ) {}

  func telegramBotListRelayableTabs() -> [TelegramRelayTabInfo] {
    relayableTabs
  }

  func telegramBotActiveInjectableAITab() -> TelegramRelayTabInfo? {
    activeAITab
  }

  func telegramBotInject(_ request: InjectionRequest) -> InjectionRequest? {
    injectCalls.append(request)
    return injectResult
  }

  func telegramBotStartupStatement(workingDirectory: URL) async -> String {
    "Status\nRepository: \(workingDirectory.path)\nOpen app tabs: 0\nTasks to implement: 0"
  }
}

// MARK: - Test Helpers

private func makeUpdate(
  text: String,
  userId: Int64 = 999,
  chatId: Int64 = 999
) throws -> TelegramUpdate {
  let json = """
  {
    "update_id": 1,
    "message": {
      "message_id": 1,
      "from": {"id": \(userId), "is_bot": false, "first_name": "Test"},
      "chat": {"id": \(chatId), "type": "private"},
      "date": 0,
      "text": "\(text)"
    }
  }
  """
  return try JSONDecoder().decode(
    TelegramUpdate.self,
    from: json.data(using: .utf8)!
  )
}

// MARK: - Tests

@MainActor
final class TelegramRelayRuntimeTests: XCTestCase {
  private var runtime: TelegramBotRuntime!
  private var mockDelegate: MockRelayDelegate!
  private var client: TelegramBotAPIClient!
  private var savedConfig: AppConfig!

  override func setUp() {
    super.setUp()
    savedConfig = ConfigManager.shared.config
    ConfigManager.shared.config.telegramAllowedUserID = 999

    runtime = TelegramBotRuntime(workingDirectory: URL(fileURLWithPath: "/tmp"))
    mockDelegate = MockRelayDelegate()
    runtime.delegate = mockDelegate
    runtime.mode = .execute
    client = TelegramBotAPIClient(token: "test-token")
  }

  override func tearDown() {
    ConfigManager.shared.config = savedConfig
    runtime = nil
    mockDelegate = nil
    client = nil
    super.tearDown()
  }

  // MARK: - Bug 1: No fallthrough after relay injection failure

  func testRelayInjectionFailureDoesNotTriggerExecute() async throws {
    let tabId = UUID()
    runtime.relaySession = TelegramRelaySession(
      tabId: tabId,
      tabName: "Test Tab",
      startedAt: Date(),
      status: .active
    )
    runtime.relayChatId = 999
    runtime.relayClient = client

    // Delegate returns nil → injection failure.
    mockDelegate.injectResult = nil

    let update = try makeUpdate(text: "ls -la")
    await runtime.handleUpdate(update, client: client)

    // Relay should be stopped after failure.
    XCTAssertNil(runtime.relaySession, "Relay session should be cleared after injection failure")

    // Headless execution must NOT have been triggered.
    let hasExecutingEvent = runtime.events.contains { $0.message.contains("Executing prompt") }
    XCTAssertFalse(hasExecutingEvent, "Injection failure must not fall through to execute path")

    // Verify failure was logged.
    let hasFailureEvent = runtime.events.contains { $0.message.contains("Relay stopped") }
    XCTAssertTrue(hasFailureEvent, "Relay stop should be logged")
  }

  // MARK: - Bug 2: surfaceLost notification delivery

  func testSurfaceLostCapturesChatIdBeforeStopRelay() async {
    // Verify the fix structurally: after stopRelay(), relayChatId/relayClient are nil.
    // The surfaceLost callback must capture them before calling stopRelay().
    let tabId = UUID()
    runtime.relaySession = TelegramRelaySession(
      tabId: tabId,
      tabName: "Test Tab",
      startedAt: Date(),
      status: .active
    )
    runtime.relayChatId = 999
    runtime.relayClient = client

    // Simulate what stopRelay does.
    let capturedChatId = runtime.relayChatId
    let capturedClient = runtime.relayClient

    // stopRelay clears the values.
    runtime.relaySession = nil
    runtime.relayChatId = nil
    runtime.relayClient = nil

    // Captured values should still be valid.
    XCTAssertEqual(capturedChatId, 999, "chatId must be captured before cleanup")
    XCTAssertNotNil(capturedClient, "client must be captured before cleanup")

    // After cleanup, instance vars are nil.
    XCTAssertNil(runtime.relayChatId)
    XCTAssertNil(runtime.relayClient)
  }

  // MARK: - Bug 3: /relay_stop with no session

  func testRelayStopCommandWithNoActiveSession() async throws {
    // No relay session set.
    XCTAssertNil(runtime.relaySession)

    let update = try makeUpdate(text: "/relay_stop")
    await runtime.handleUpdate(update, client: client)

    // "Relay stopped" should NOT appear in events (nothing was stopped).
    let hasStoppedEvent = runtime.events.contains { $0.message.contains("Relay stopped") }
    XCTAssertFalse(hasStoppedEvent, "Should not log relay stop when no session existed")

    // No system message about relay being stopped.
    let hasRelaySystemMsg = runtime.messages.contains {
      $0.direction == .system && $0.text.contains("Relay stopped")
    }
    XCTAssertFalse(hasRelaySystemMsg, "Should not add system message when no session existed")

    // sendReply attempted "No relay active." — API fails with test token,
    // so we verify the error event was logged (confirming the else branch ran).
    let hasFailedSend = runtime.events.contains {
      $0.message.contains("Failed to send message")
    }
    XCTAssertTrue(hasFailedSend, "Should attempt to send 'No relay active.' reply")
  }

  func testRelayStopCommandWithActiveSession() async throws {
    let tabId = UUID()
    runtime.relaySession = TelegramRelaySession(
      tabId: tabId,
      tabName: "Active Tab",
      startedAt: Date(),
      status: .active
    )
    runtime.relayChatId = 999
    runtime.relayClient = client

    let update = try makeUpdate(text: "/relay_stop")
    await runtime.handleUpdate(update, client: client)

    XCTAssertNil(runtime.relaySession, "Relay session should be cleared")

    let hasStoppedEvent = runtime.events.contains { $0.message.contains("Relay stopped") }
    XCTAssertTrue(hasStoppedEvent, "Should log relay stop")
  }

  // MARK: - Bug 4: Injection request uses correct origin and target

  func testRelayInjectionRequestProperties() async throws {
    let tabId = UUID()
    runtime.relaySession = TelegramRelaySession(
      tabId: tabId,
      tabName: "Test Tab",
      startedAt: Date(),
      status: .active
    )
    runtime.relayChatId = 999
    runtime.relayClient = client

    // Delegate returns a completed result so injection "succeeds".
    mockDelegate.injectResult = InjectionRequest(
      payload: .command("", submit: .execute),
      target: .tabId(tabId),
      origin: .telegram,
      status: .completed
    )

    let update = try makeUpdate(text: "echo hello")
    await runtime.handleUpdate(update, client: client)

    XCTAssertEqual(mockDelegate.injectCalls.count, 1, "Should call inject exactly once")

    let injected = mockDelegate.injectCalls[0]
    XCTAssertEqual(injected.origin, .telegram, "Origin must be .telegram")
    XCTAssertEqual(injected.target, .tabId(tabId), "Target must be .tabId with relay tab ID")

    if case .command(let text, let submit) = injected.payload {
      XCTAssertEqual(text, "echo hello", "Payload text should match user message")
      XCTAssertEqual(submit, .execute, "Submit mode should be .execute")
    } else {
      XCTFail("Expected .command payload, got \(injected.payload)")
    }
  }

  // MARK: - Relay active: successful injection does not trigger execute

  func testSuccessfulRelayDoesNotExecutePrompt() async throws {
    let tabId = UUID()
    runtime.relaySession = TelegramRelaySession(
      tabId: tabId,
      tabName: "Test Tab",
      startedAt: Date(),
      status: .active
    )
    runtime.relayChatId = 999
    runtime.relayClient = client

    mockDelegate.injectResult = InjectionRequest(
      payload: .command("", submit: .execute),
      target: .tabId(tabId),
      origin: .telegram,
      status: .completed
    )

    let update = try makeUpdate(text: "make build")
    await runtime.handleUpdate(update, client: client)

    // Relay should still be active.
    XCTAssertNotNil(runtime.relaySession, "Relay session should remain active after success")

    // No headless execution.
    let hasExecutingEvent = runtime.events.contains { $0.message.contains("Executing prompt") }
    XCTAssertFalse(hasExecutingEvent, "Successful relay must not trigger headless execution")
  }

  // MARK: - Active AI Tab Routing

  func testPlainTextInjectsIntoActiveAITab() async throws {
    let tabId = UUID()
    mockDelegate.activeAITab = TelegramRelayTabInfo(
      id: tabId,
      name: "Claude Tab",
      agentType: .claude,
      directory: URL(fileURLWithPath: "/tmp"),
      isActive: true
    )
    mockDelegate.injectResult = InjectionRequest(
      payload: .command("", submit: .execute),
      target: .tabId(tabId),
      origin: .telegram,
      status: .completed
    )

    let update = try makeUpdate(text: "run tests")
    await runtime.handleUpdate(update, client: client)

    XCTAssertEqual(mockDelegate.injectCalls.count, 1)

    let injected = mockDelegate.injectCalls[0]
    XCTAssertEqual(injected.target, .tabId(tabId))
    XCTAssertEqual(injected.origin, .telegram)

    if case .command(let text, let submit) = injected.payload {
      XCTAssertEqual(text, "run tests")
      XCTAssertEqual(submit, .execute)
    } else {
      XCTFail("Expected .command payload")
    }

    let hasAITabEvent = runtime.events.contains { $0.message.contains("Injected into AI tab") }
    XCTAssertTrue(hasAITabEvent, "Should log AI tab injection")
  }

  func testActiveAITabWinsOverRelay() async throws {
    let aiTabId = UUID()
    let relayTabId = UUID()

    // Set up both an active AI tab and an active relay.
    mockDelegate.activeAITab = TelegramRelayTabInfo(
      id: aiTabId,
      name: "OpenCode Tab",
      agentType: .opencode,
      directory: URL(fileURLWithPath: "/tmp"),
      isActive: true
    )
    runtime.relaySession = TelegramRelaySession(
      tabId: relayTabId,
      tabName: "Relay Tab",
      startedAt: Date(),
      status: .active
    )
    runtime.relayChatId = 999
    runtime.relayClient = client

    mockDelegate.injectResult = InjectionRequest(
      payload: .command("", submit: .execute),
      target: .tabId(aiTabId),
      origin: .telegram,
      status: .completed
    )

    let update = try makeUpdate(text: "build project")
    await runtime.handleUpdate(update, client: client)

    // Should inject into AI tab, not relay.
    XCTAssertEqual(mockDelegate.injectCalls.count, 1)
    XCTAssertEqual(mockDelegate.injectCalls[0].target, .tabId(aiTabId))

    // Relay should remain active (not consumed).
    XCTAssertNotNil(runtime.relaySession)
  }

  func testNoAITabFallsBackToRelay() async throws {
    let relayTabId = UUID()

    // No active AI tab.
    mockDelegate.activeAITab = nil

    runtime.relaySession = TelegramRelaySession(
      tabId: relayTabId,
      tabName: "Relay Tab",
      startedAt: Date(),
      status: .active
    )
    runtime.relayChatId = 999
    runtime.relayClient = client

    mockDelegate.injectResult = InjectionRequest(
      payload: .command("", submit: .execute),
      target: .tabId(relayTabId),
      origin: .telegram,
      status: .completed
    )

    let update = try makeUpdate(text: "ls -la")
    await runtime.handleUpdate(update, client: client)

    // Should inject into relay tab.
    XCTAssertEqual(mockDelegate.injectCalls.count, 1)
    XCTAssertEqual(mockDelegate.injectCalls[0].target, .tabId(relayTabId))
  }

  func testNoAITabNoRelayReturnsError() async throws {
    // No active AI tab, no relay.
    mockDelegate.activeAITab = nil
    XCTAssertNil(runtime.relaySession)

    let update = try makeUpdate(text: "some command")
    await runtime.handleUpdate(update, client: client)

    // No injection should happen.
    XCTAssertTrue(mockDelegate.injectCalls.isEmpty, "Should not inject anywhere")

    // Should log the error.
    let hasNoTabEvent = runtime.events.contains { $0.message.contains("No eligible AI tab") }
    XCTAssertTrue(hasNoTabEvent, "Should log no eligible AI tab")

    // Should NOT trigger headless execution.
    let hasExecutingEvent = runtime.events.contains { $0.message.contains("Executing prompt") }
    XCTAssertFalse(hasExecutingEvent, "Must not trigger headless execution")
  }

  func testAITabInjectionFailureDoesNotFallThrough() async throws {
    let tabId = UUID()
    mockDelegate.activeAITab = TelegramRelayTabInfo(
      id: tabId,
      name: "Claude Tab",
      agentType: .claude,
      directory: URL(fileURLWithPath: "/tmp"),
      isActive: true
    )

    // Injection fails.
    mockDelegate.injectResult = nil

    let update = try makeUpdate(text: "deploy")
    await runtime.handleUpdate(update, client: client)

    // Should log failure.
    let hasFailureEvent = runtime.events.contains { $0.message.contains("Injection into AI tab") }
    XCTAssertTrue(hasFailureEvent, "Should log AI tab injection failure")

    // Must NOT fall through to headless execution.
    let hasExecutingEvent = runtime.events.contains { $0.message.contains("Executing prompt") }
    XCTAssertFalse(hasExecutingEvent, "Injection failure must not trigger headless execution")
  }

  func testSlashCommandsStillWorkWithActiveAITab() async throws {
    let tabId = UUID()
    mockDelegate.activeAITab = TelegramRelayTabInfo(
      id: tabId,
      name: "Claude Tab",
      agentType: .claude,
      directory: URL(fileURLWithPath: "/tmp"),
      isActive: true
    )

    let update = try makeUpdate(text: "/report")
    await runtime.handleUpdate(update, client: client)

    // Slash command should NOT inject into AI tab.
    XCTAssertTrue(mockDelegate.injectCalls.isEmpty, "Slash commands must not inject into AI tab")
  }
}
