import Foundation

@testable import SlothyTerminalLib

/// A mock agent loop that emits pre-configured events and returns a fixed result.
final class MockAgentLoop: AgentLoopProtocol, @unchecked Sendable {
  /// Events to emit via `onEvent` during `run()`.
  var events: [AgentLoopEvent] = []

  /// The final text to return from `run()`.
  var result: String = ""

  /// If true, `run()` throws an error instead of returning.
  var shouldThrow: Bool = false

  /// Tracks how many times `run()` was called.
  private(set) var runCallCount = 0

  func run(
    input: RuntimeInput,
    messages: inout [[String: JSONValue]],
    context: ToolContext,
    onEvent: AgentEventHandler?
  ) async throws -> String {
    runCallCount += 1

    if shouldThrow {
      throw AgentLoopError.invalidResponse(detail: "Mock error")
    }

    for event in events {
      onEvent?(event)
    }

    return result
  }
}
