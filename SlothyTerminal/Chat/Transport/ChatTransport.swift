import Foundation

/// Protocol for communicating with a Claude backend.
///
/// Implementations handle process lifecycle, stdin/stdout, and NDJSON parsing.
/// The adapter (`ChatState`) creates a transport and feeds its callbacks
/// into the engine as `ChatSessionEvent`s.
protocol ChatTransport: AnyObject {
  /// Start the transport. Calls back with events on the provided closures.
  ///
  /// - Parameters:
  ///   - onEvent: Called for each parsed `StreamEvent` from stdout.
  ///   - onReady: Called when a session ID is received (transport is ready).
  ///   - onError: Called when the transport encounters an error.
  ///   - onTerminated: Called when the transport process ends.
  func start(
    onEvent: @escaping (StreamEvent) -> Void,
    onReady: @escaping (String) -> Void,
    onError: @escaping (Error) -> Void,
    onTerminated: @escaping (TerminationReason) -> Void
  )

  /// Send a user message (text will be serialized to NDJSON internally).
  func send(message: String)

  /// Interrupt the current operation (SIGINT).
  func interrupt()

  /// Terminate the transport completely.
  func terminate()

  /// Whether the transport is currently running.
  var isRunning: Bool { get }
}
