import Foundation

@testable import SlothyTerminalLib

/// A mock agent runtime that returns pre-configured event sequences.
///
/// Each call to `stream(_:)` pops the next response from the queue.
/// This allows tests to script multi-step agent loop interactions.
final class MockAgentRuntime: AgentRuntimeProtocol, @unchecked Sendable {
  /// Queue of responses. Each entry is a sequence of events for one LLM call.
  var responses: [[ProviderStreamEvent]] = []

  /// Tracks all inputs received.
  private(set) var receivedInputs: [RuntimeInput] = []

  /// Index into the response queue.
  private var callIndex = 0

  func stream(
    _ input: RuntimeInput
  ) async throws -> AsyncThrowingStream<ProviderStreamEvent, Error> {
    receivedInputs.append(input)

    guard callIndex < responses.count else {
      return AsyncThrowingStream { $0.finish() }
    }

    let events = responses[callIndex]
    callIndex += 1

    return AsyncThrowingStream { continuation in
      for event in events {
        continuation.yield(event)
      }
      continuation.finish()
    }
  }

  /// Reset the call index for reuse.
  func reset() {
    callIndex = 0
    receivedInputs = []
  }
}
