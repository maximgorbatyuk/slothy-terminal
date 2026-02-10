import Foundation

/// Events that drive state transitions in the session engine.
///
/// Events come from three sources: user actions, transport callbacks,
/// and internal recovery logic. The engine processes each event and
/// emits commands for the adapter to execute.
enum ChatSessionEvent {
  // MARK: - User-initiated

  /// User wants to send a message.
  case userSendMessage(String)

  /// User wants to cancel the current streaming response.
  case userCancel

  /// User wants to clear the conversation and start fresh.
  case userClear

  /// User wants to retry the last failed message.
  case userRetry

  // MARK: - Transport-originated

  /// Transport is running and reported a session ID.
  case transportReady(sessionId: String)

  /// Transport emitted a stream event (reuses existing StreamEvent enum).
  case transportStreamEvent(StreamEvent)

  /// Transport encountered an error.
  case transportError(Error)

  /// Transport terminated (normally or abnormally).
  case transportTerminated(reason: TerminationReason)

  // MARK: - Internal

  /// A recovery attempt is being made.
  case recoveryAttempt(Int)

  /// Recovery has failed after all retries.
  case recoveryFailed
}

/// Reason why the transport process terminated.
enum TerminationReason: Equatable {
  /// Normal exit (exit code 0).
  case normal

  /// Process crashed with non-zero exit code.
  case crash(exitCode: Int32, stderr: String)

  /// Terminated due to user cancel.
  case cancelled
}
