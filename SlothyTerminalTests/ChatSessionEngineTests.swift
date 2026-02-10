import XCTest
@testable import SlothyTerminalLib

final class ChatSessionEngineTests: XCTestCase {
  private var engine: ChatSessionEngine!

  override func setUp() {
    super.setUp()
    engine = ChatSessionEngine(
      workingDirectory: URL(fileURLWithPath: "/tmp/test")
    )
  }

  // MARK: - State Transition Tests

  func testInitialStateIsIdle() {
    XCTAssertEqual(engine.sessionState, .idle)
    XCTAssertTrue(engine.conversation.messages.isEmpty)
    XCTAssertNil(engine.sessionId)
  }

  func testSendMessageTransitionsToSending() {
    let commands = engine.handle(.userSendMessage("Hello"))

    XCTAssertEqual(engine.sessionState, .sending)
    /// Should emit startTransport (since idle) and sendMessage.
    XCTAssertEqual(commands.count, 2)
    XCTAssertTrue(containsCommand(commands, .startTransport))
    XCTAssertTrue(containsCommand(commands, .sendMessage))
  }

  func testStreamEventTransitionsToStreaming() {
    /// First send a message to get to sending state.
    _ = engine.handle(.userSendMessage("Hello"))
    XCTAssertEqual(engine.sessionState, .sending)

    /// Simulate transport ready.
    _ = engine.handle(.transportReady(sessionId: "test-session"))

    /// Start a content block, then delta transitions to streaming.
    _ = engine.handle(.transportStreamEvent(
      .contentBlockStart(index: 0, blockType: "text", id: nil, name: nil)
    ))
    _ = engine.handle(.transportStreamEvent(
      .contentBlockDelta(index: 0, deltaType: "text_delta", text: "Hi")
    ))

    XCTAssertEqual(engine.sessionState, .streaming)
  }

  func testResultTransitionsToReady() {
    /// Set up a streaming turn.
    _ = engine.handle(.userSendMessage("Hello"))
    _ = engine.handle(.transportReady(sessionId: "test-session"))
    _ = engine.handle(.transportStreamEvent(
      .contentBlockStart(index: 0, blockType: "text", id: nil, name: nil)
    ))
    _ = engine.handle(.transportStreamEvent(
      .contentBlockDelta(index: 0, deltaType: "text_delta", text: "Response")
    ))
    XCTAssertEqual(engine.sessionState, .streaming)

    /// Result event should finalize and go to ready.
    let commands = engine.handle(.transportStreamEvent(
      .result(text: "done", inputTokens: 100, outputTokens: 50)
    ))

    XCTAssertEqual(engine.sessionState, .ready)
    XCTAssertTrue(containsCommand(commands, .turnComplete))
    XCTAssertTrue(containsCommand(commands, .persistSnapshot))
  }

  func testCancelTransitionsToCancelling() {
    /// Set up a streaming turn.
    _ = engine.handle(.userSendMessage("Hello"))
    _ = engine.handle(.transportReady(sessionId: "test-session"))
    _ = engine.handle(.transportStreamEvent(
      .contentBlockStart(index: 0, blockType: "text", id: nil, name: nil)
    ))
    _ = engine.handle(.transportStreamEvent(
      .contentBlockDelta(index: 0, deltaType: "text_delta", text: "Hi")
    ))

    let commands = engine.handle(.userCancel)

    XCTAssertEqual(engine.sessionState, .cancelling)
    XCTAssertTrue(containsCommand(commands, .interruptTransport))
  }

  func testClearResetsToIdle() {
    /// Set up some state.
    _ = engine.handle(.userSendMessage("Hello"))
    _ = engine.handle(.transportReady(sessionId: "test-session"))

    let commands = engine.handle(.userClear)

    XCTAssertEqual(engine.sessionState, .idle)
    XCTAssertTrue(engine.conversation.messages.isEmpty)
    XCTAssertNil(engine.sessionId)
    XCTAssertTrue(containsCommand(commands, .terminateTransport))
  }

  // MARK: - Turn Orchestration Tests

  func testUserMessageAddedToConversation() {
    _ = engine.handle(.userSendMessage("Hello"))

    /// Should have user message + assistant placeholder.
    XCTAssertEqual(engine.conversation.messages.count, 2)
    XCTAssertEqual(engine.conversation.messages[0].role, .user)
    XCTAssertEqual(engine.conversation.messages[0].textContent, "Hello")
    XCTAssertEqual(engine.conversation.messages[1].role, .assistant)
    XCTAssertTrue(engine.conversation.messages[1].isStreaming)
  }

  func testTokensAccumulateOnResult() {
    _ = engine.handle(.userSendMessage("Hello"))
    _ = engine.handle(.transportReady(sessionId: "test-session"))

    _ = engine.handle(.transportStreamEvent(
      .result(text: "done", inputTokens: 100, outputTokens: 50)
    ))

    XCTAssertEqual(engine.conversation.totalInputTokens, 100)
    XCTAssertEqual(engine.conversation.totalOutputTokens, 50)
  }

  func testToolUseTurnContinuesAfterMessageStopUntilResult() {
    _ = engine.handle(.userSendMessage("Run pwd"))
    _ = engine.handle(.transportReady(sessionId: "test-session"))

    _ = engine.handle(.transportStreamEvent(
      .contentBlockStart(index: 0, blockType: "tool_use", id: "tool-1", name: "Bash")
    ))
    _ = engine.handle(.transportStreamEvent(
      .contentBlockDelta(index: 0, deltaType: "input_json_delta", text: "{\"command\":\"pwd\"}")
    ))

    /// Tool-use segment ends, turn should remain in progress.
    _ = engine.handle(.transportStreamEvent(.messageStop))
    XCTAssertEqual(engine.sessionState, .sending)

    /// Tool result arrives as top-level user event.
    _ = engine.handle(.transportStreamEvent(
      .userToolResult(toolUseId: "tool-1", content: "/tmp", isError: false)
    ))

    /// Assistant continues with final text in a new segment.
    _ = engine.handle(.transportStreamEvent(.messageStart(inputTokens: 3)))
    _ = engine.handle(.transportStreamEvent(
      .contentBlockStart(index: 0, blockType: "text", id: nil, name: nil)
    ))
    _ = engine.handle(.transportStreamEvent(
      .contentBlockDelta(index: 0, deltaType: "text_delta", text: "done")
    ))
    _ = engine.handle(.transportStreamEvent(.messageStop))

    let commands = engine.handle(.transportStreamEvent(
      .result(text: "done", inputTokens: 10, outputTokens: 5)
    ))

    XCTAssertEqual(engine.sessionState, .ready)
    XCTAssertTrue(containsCommand(commands, .persistSnapshot))
  }

  func testRetryRemovesLastAssistantMessage() {
    /// Complete a turn first.
    _ = engine.handle(.userSendMessage("Hello"))
    _ = engine.handle(.transportReady(sessionId: "test-session"))
    _ = engine.handle(.transportStreamEvent(
      .result(text: "done", inputTokens: 10, outputTokens: 5)
    ))

    /// Now there are 2 messages: user + assistant (finalized).
    XCTAssertEqual(engine.conversation.messages.count, 2)

    /// Retry should remove the last assistant and re-send.
    _ = engine.handle(.userRetry)

    /// Should have: user (original) + user (retry) + assistant (new placeholder).
    /// The old assistant was removed, but original user stays.
    /// Actually, retry removes last assistant then calls handleUserSendMessage
    /// which adds user message + assistant placeholder.
    XCTAssertEqual(engine.conversation.messages.count, 3)
    XCTAssertEqual(engine.conversation.messages.last?.role, .assistant)
    XCTAssertTrue(engine.conversation.messages.last?.isStreaming == true)
  }

  // MARK: - Recovery Tests

  func testCrashTriggersRecovery() {
    /// Set up a session with a session ID (needed for recovery).
    _ = engine.handle(.userSendMessage("Hello"))
    _ = engine.handle(.transportReady(sessionId: "test-session"))

    let commands = engine.handle(
      .transportTerminated(reason: .crash(exitCode: 1, stderr: "segfault"))
    )

    /// Should be in recovery state.
    if case .recovering(let attempt) = engine.sessionState {
      XCTAssertEqual(attempt, 1)
    } else {
      XCTFail("Expected recovering state, got \(engine.sessionState)")
    }

    XCTAssertTrue(containsCommand(commands, .attemptRecovery))
  }

  func testMaxRetriesExceeded() {
    /// Set up a session.
    _ = engine.handle(.userSendMessage("Hello"))
    _ = engine.handle(.transportReady(sessionId: "test-session"))

    /// First 3 crashes trigger recovery attempts.
    for i in 1...3 {
      let commands = engine.handle(
        .transportTerminated(reason: .crash(exitCode: 1, stderr: "error"))
      )

      XCTAssertTrue(
        containsCommand(commands, .attemptRecovery),
        "Crash \(i) should trigger recovery"
      )
    }

    /// 4th crash exceeds max retries — engine falls to unrecoverable state.
    let commands = engine.handle(
      .transportTerminated(reason: .crash(exitCode: 1, stderr: "error"))
    )

    if case .failed = engine.sessionState {
      XCTAssertTrue(containsCommand(commands, .surfaceError))
    } else {
      XCTFail("Expected failed state, got \(engine.sessionState)")
    }
  }

  // MARK: - Cancel Tests

  func testCancelIgnoresSubsequentStreamEvents() {
    /// Set up a streaming turn.
    _ = engine.handle(.userSendMessage("Hello"))
    _ = engine.handle(.transportReady(sessionId: "test-session"))
    _ = engine.handle(.transportStreamEvent(
      .contentBlockStart(index: 0, blockType: "text", id: nil, name: nil)
    ))
    _ = engine.handle(.transportStreamEvent(
      .contentBlockDelta(index: 0, deltaType: "text_delta", text: "Hi")
    ))

    /// Cancel the response.
    _ = engine.handle(.userCancel)
    XCTAssertEqual(engine.sessionState, .cancelling)

    /// Stream events arriving after cancel should be ignored.
    let commands = engine.handle(.transportStreamEvent(
      .contentBlockDelta(index: 0, deltaType: "text_delta", text: " more text")
    ))
    XCTAssertTrue(commands.isEmpty)
    XCTAssertEqual(engine.sessionState, .cancelling)
  }

  func testCancelThenTerminatedTransitionsToReady() {
    /// Set up streaming.
    _ = engine.handle(.userSendMessage("Hello"))
    _ = engine.handle(.transportReady(sessionId: "test-session"))
    _ = engine.handle(.transportStreamEvent(
      .contentBlockStart(index: 0, blockType: "text", id: nil, name: nil)
    ))
    _ = engine.handle(.transportStreamEvent(
      .contentBlockDelta(index: 0, deltaType: "text_delta", text: "Hi")
    ))

    /// Cancel and then transport confirms termination.
    _ = engine.handle(.userCancel)
    let commands = engine.handle(.transportTerminated(reason: .cancelled))

    XCTAssertEqual(engine.sessionState, .ready)
    XCTAssertTrue(containsCommand(commands, .persistSnapshot))
  }

  func testCancelPersistsPartialResponse() {
    /// Set up streaming with content.
    _ = engine.handle(.userSendMessage("Hello"))
    _ = engine.handle(.transportReady(sessionId: "test-session"))
    _ = engine.handle(.transportStreamEvent(
      .contentBlockStart(index: 0, blockType: "text", id: nil, name: nil)
    ))
    _ = engine.handle(.transportStreamEvent(
      .contentBlockDelta(index: 0, deltaType: "text_delta", text: "Partial response")
    ))

    /// Cancel should emit persistSnapshot.
    let commands = engine.handle(.userCancel)
    XCTAssertTrue(containsCommand(commands, .persistSnapshot))

    /// Partial content should be preserved.
    let lastAssistant = engine.conversation.messages.last(where: { $0.role == .assistant })
    XCTAssertEqual(lastAssistant?.textContent, "Partial response")
    XCTAssertFalse(lastAssistant?.isStreaming ?? true)
  }

  // MARK: - Invalid Transition Tests

  func testSendInStreamingStateIsRejected() {
    /// Get to streaming state.
    _ = engine.handle(.userSendMessage("Hello"))
    _ = engine.handle(.transportReady(sessionId: "test-session"))
    _ = engine.handle(.transportStreamEvent(
      .contentBlockStart(index: 0, blockType: "text", id: nil, name: nil)
    ))
    _ = engine.handle(.transportStreamEvent(
      .contentBlockDelta(index: 0, deltaType: "text_delta", text: "Hi")
    ))
    XCTAssertEqual(engine.sessionState, .streaming)

    /// Second send should be rejected.
    let commands = engine.handle(.userSendMessage("Another"))
    XCTAssertTrue(containsCommand(commands, .surfaceError))
  }

  // MARK: - Helpers

  private func containsCommand(
    _ commands: [ChatSessionCommand],
    _ expected: CommandKind
  ) -> Bool {
    commands.contains { command in
      switch (command, expected) {
      case (.startTransport, .startTransport):
        return true

      case (.sendMessage, .sendMessage):
        return true

      case (.interruptTransport, .interruptTransport):
        return true

      case (.terminateTransport, .terminateTransport):
        return true

      case (.attemptRecovery, .attemptRecovery):
        return true

      case (.persistSnapshot, .persistSnapshot):
        return true

      case (.turnComplete, .turnComplete):
        return true

      case (.surfaceError, .surfaceError):
        return true

      default:
        return false
      }
    }
  }
}

/// Simplified command kinds for test assertions.
private enum CommandKind {
  case startTransport
  case sendMessage
  case interruptTransport
  case terminateTransport
  case attemptRecovery
  case persistSnapshot
  case turnComplete
  case surfaceError
}
