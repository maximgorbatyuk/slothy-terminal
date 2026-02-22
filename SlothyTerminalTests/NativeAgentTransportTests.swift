import Foundation
import Testing

@testable import SlothyTerminalLib

@Suite("NativeAgentTransport")
struct NativeAgentTransportTests {

  private func makeModel() -> ModelDescriptor {
    ModelDescriptor(
      providerID: .anthropic,
      modelID: "claude-sonnet-4-6",
      packageID: "@ai-sdk/anthropic",
      supportsReasoning: true,
      releaseDate: "2025-05-14",
      outputLimit: 16_384
    )
  }

  private func makeTransport(
    loop: MockAgentLoop = MockAgentLoop()
  ) -> NativeAgentTransport {
    NativeAgentTransport(
      loop: loop,
      model: makeModel(),
      workingDirectory: FileManager.default.temporaryDirectory,
      permissions: MockPermissionDelegate()
    )
  }

  // MARK: - Start

  @Test("start calls onReady with session ID")
  func startCallsOnReady() {
    let transport = makeTransport()

    var readySessionID: String?
    transport.start(
      onEvent: { _ in },
      onReady: { readySessionID = $0 },
      onError: { _ in },
      onTerminated: { _ in }
    )

    #expect(readySessionID != nil)
    #expect(!readySessionID!.isEmpty)
    #expect(transport.isRunning)
  }

  // MARK: - Terminate

  @Test("terminate calls onTerminated with normal reason")
  func terminateCallsOnTerminated() {
    let transport = makeTransport()

    var terminationReason: TerminationReason?
    transport.start(
      onEvent: { _ in },
      onReady: { _ in },
      onError: { _ in },
      onTerminated: { terminationReason = $0 }
    )

    transport.terminate()

    #expect(terminationReason == .normal)
    #expect(!transport.isRunning)
  }

  // MARK: - Send with text-only response

  @Test("send emits text stream events and result")
  func sendEmitsTextEvents() async throws {
    let loop = MockAgentLoop()
    loop.events = [
      .textDelta("Hello "),
      .textDelta("world!"),
      .stepEnd(index: 0),
      .usage(input: 100, output: 50),
      .finished,
    ]
    loop.result = "Hello world!"

    let transport = makeTransport(loop: loop)
    var events: [StreamEvent] = []

    let expectation = Expectation()

    transport.start(
      onEvent: { event in
        events.append(event)
        if case .result = event {
          expectation.fulfill()
        }
      },
      onReady: { _ in },
      onError: { _ in },
      onTerminated: { _ in }
    )

    transport.send(message: "Hello")

    /// Wait for async processing.
    await expectation.wait(timeout: 2.0)

    /// Should have: contentBlockStart(text), 2x contentBlockDelta, contentBlockStop, messageStop, result.
    let startEvents = events.filter {
      if case .contentBlockStart(_, let blockType, _, _) = $0,
         blockType == "text"
      {
        return true
      }
      return false
    }
    #expect(startEvents.count == 1)

    let deltaEvents = events.filter {
      if case .contentBlockDelta(_, let deltaType, _) = $0,
         deltaType == "text_delta"
      {
        return true
      }
      return false
    }
    #expect(deltaEvents.count == 2)

    let resultEvents = events.filter {
      if case .result = $0 { return true }
      return false
    }
    #expect(resultEvents.count == 1)
  }

  // MARK: - Tool call event mapping

  @Test("send emits tool use stream events")
  func sendEmitsToolEvents() async throws {
    let loop = MockAgentLoop()
    loop.events = [
      .toolCallStart(id: "toolu_1", name: "bash"),
      .toolCallDelta(id: "toolu_1", argumentsDelta: "{\"command\":\"ls\"}"),
      .toolCallComplete(id: "toolu_1", name: "bash", arguments: "{\"command\":\"ls\"}"),
      .toolResult(id: "toolu_1", name: "bash", output: "file.txt", isError: false),
      .textDelta("Done."),
      .stepEnd(index: 0),
      .finished,
    ]
    loop.result = "Done."

    let transport = makeTransport(loop: loop)
    var events: [StreamEvent] = []

    let expectation = Expectation()

    transport.start(
      onEvent: { event in
        events.append(event)
        if case .result = event {
          expectation.fulfill()
        }
      },
      onReady: { _ in },
      onError: { _ in },
      onTerminated: { _ in }
    )

    transport.send(message: "List files")

    await expectation.wait(timeout: 2.0)

    /// Verify tool_use content block start.
    let toolStarts = events.filter {
      if case .contentBlockStart(_, let blockType, _, _) = $0,
         blockType == "tool_use"
      {
        return true
      }
      return false
    }
    #expect(toolStarts.count == 1)

    /// Verify tool result event.
    let toolResults = events.filter {
      if case .userToolResult = $0 { return true }
      return false
    }
    #expect(toolResults.count == 1)
  }

  // MARK: - Thinking event mapping

  @Test("send emits thinking stream events")
  func sendEmitsThinkingEvents() async throws {
    let loop = MockAgentLoop()
    loop.events = [
      .thinkingDelta("Let me think..."),
      .textDelta("Answer."),
      .stepEnd(index: 0),
      .finished,
    ]
    loop.result = "Answer."

    let transport = makeTransport(loop: loop)
    var events: [StreamEvent] = []

    let expectation = Expectation()

    transport.start(
      onEvent: { event in
        events.append(event)
        if case .result = event {
          expectation.fulfill()
        }
      },
      onReady: { _ in },
      onError: { _ in },
      onTerminated: { _ in }
    )

    transport.send(message: "Think about this")

    await expectation.wait(timeout: 2.0)

    /// Should have thinking block start.
    let thinkingStarts = events.filter {
      if case .contentBlockStart(_, let blockType, _, _) = $0,
         blockType == "thinking"
      {
        return true
      }
      return false
    }
    #expect(thinkingStarts.count == 1)

    /// Should have thinking delta.
    let thinkingDeltas = events.filter {
      if case .contentBlockDelta(_, let deltaType, _) = $0,
         deltaType == "thinking_delta"
      {
        return true
      }
      return false
    }
    #expect(thinkingDeltas.count == 1)

    /// Thinking block should be closed before text block starts.
    let textStarts = events.filter {
      if case .contentBlockStart(_, let blockType, _, _) = $0,
         blockType == "text"
      {
        return true
      }
      return false
    }
    #expect(textStarts.count == 1)
  }

  // MARK: - Error handling

  @Test("send calls onError and onTerminated on loop error")
  func sendHandlesLoopError() async throws {
    let loop = MockAgentLoop()
    loop.shouldThrow = true

    let transport = makeTransport(loop: loop)

    var receivedError: Error?
    var terminationReason: TerminationReason?

    let expectation = Expectation()

    transport.start(
      onEvent: { _ in },
      onReady: { _ in },
      onError: { receivedError = $0 },
      onTerminated: { reason in
        terminationReason = reason
        expectation.fulfill()
      }
    )

    transport.send(message: "Fail")

    await expectation.wait(timeout: 2.0)

    #expect(receivedError != nil)
    #expect(terminationReason != nil)
    if case .crash = terminationReason {
      /// Expected.
    } else {
      Issue.record("Expected crash termination, got \(String(describing: terminationReason))")
    }
  }

  // MARK: - Send before start is ignored

  @Test("send before start is ignored")
  func sendBeforeStartIgnored() {
    let loop = MockAgentLoop()
    let transport = makeTransport(loop: loop)

    /// Don't call start().
    transport.send(message: "Should be ignored")

    #expect(loop.runCallCount == 0)
  }

  // MARK: - Usage accumulation

  @Test("token usage is accumulated across events")
  func usageAccumulation() async throws {
    let loop = MockAgentLoop()
    loop.events = [
      .usage(input: 100, output: 50),
      .usage(input: 200, output: 100),
      .textDelta("Done."),
      .stepEnd(index: 0),
      .finished,
    ]
    loop.result = "Done."

    let transport = makeTransport(loop: loop)
    var resultEvent: StreamEvent?

    let expectation = Expectation()

    transport.start(
      onEvent: { event in
        if case .result = event {
          resultEvent = event
          expectation.fulfill()
        }
      },
      onReady: { _ in },
      onError: { _ in },
      onTerminated: { _ in }
    )

    transport.send(message: "Count tokens")

    await expectation.wait(timeout: 2.0)

    if case .result(_, let inputTokens, let outputTokens) = resultEvent {
      #expect(inputTokens == 300)
      #expect(outputTokens == 150)
    } else {
      Issue.record("Expected result event")
    }
  }
}

// MARK: - Expectation helper

/// Simple async expectation for waiting on callback-based code in Swift Testing.
private final class Expectation: @unchecked Sendable {
  private let stream: AsyncStream<Void>
  private let continuation: AsyncStream<Void>.Continuation

  init() {
    var cont: AsyncStream<Void>.Continuation!
    stream = AsyncStream { cont = $0 }
    continuation = cont
  }

  func fulfill() {
    continuation.yield()
    continuation.finish()
  }

  func wait(timeout: TimeInterval) async {
    /// Use a task group to race the stream against a timeout.
    await withTaskGroup(of: Void.self) { group in
      group.addTask {
        for await _ in self.stream {
          return
        }
      }
      group.addTask {
        try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
      }

      /// Return as soon as either completes.
      await group.next()
      group.cancelAll()
    }
  }
}
