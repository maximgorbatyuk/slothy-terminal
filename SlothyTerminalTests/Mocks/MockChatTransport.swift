import Foundation
@testable import SlothyTerminalLib

/// Mock transport that records calls and replays pre-recorded events.
/// Used in engine integration tests.
class MockChatTransport: ChatTransport {
  private(set) var isRunning: Bool = false

  /// Recorded calls for assertions.
  private(set) var sentMessages: [String] = []
  private(set) var interruptCalled: Bool = false
  private(set) var terminateCalled: Bool = false
  private(set) var startCalled: Bool = false

  /// Stored callbacks for simulating events.
  private var onEvent: ((StreamEvent) -> Void)?
  private var onReady: ((String) -> Void)?
  private var onError: ((Error) -> Void)?
  private var onTerminated: ((TerminationReason) -> Void)?

  func start(
    onEvent: @escaping (StreamEvent) -> Void,
    onReady: @escaping (String) -> Void,
    onError: @escaping (Error) -> Void,
    onTerminated: @escaping (TerminationReason) -> Void
  ) {
    self.onEvent = onEvent
    self.onReady = onReady
    self.onError = onError
    self.onTerminated = onTerminated
    self.isRunning = true
    self.startCalled = true
  }

  func send(message: String) {
    sentMessages.append(message)
  }

  func interrupt() {
    interruptCalled = true
  }

  func terminate() {
    terminateCalled = true
    isRunning = false
  }

  // MARK: - Test helpers

  /// Simulate the transport becoming ready with a session ID.
  func simulateReady(sessionId: String) {
    onReady?(sessionId)
  }

  /// Simulate a stream event arriving from the transport.
  func simulateEvent(_ event: StreamEvent) {
    onEvent?(event)
  }

  /// Simulate a transport error.
  func simulateError(_ error: Error) {
    onError?(error)
  }

  /// Simulate the transport terminating.
  func simulateTerminated(_ reason: TerminationReason) {
    onTerminated?(reason)
  }

  /// Reset all recorded state.
  func reset() {
    sentMessages.removeAll()
    interruptCalled = false
    terminateCalled = false
    startCalled = false
  }
}
