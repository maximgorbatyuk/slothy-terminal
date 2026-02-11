import Foundation

/// All possible states the chat session can be in.
///
/// The session progresses through these states as users send messages
/// and the transport streams responses. The engine enforces valid
/// transitions between states.
enum ChatSessionState: Equatable {
  /// No turn in progress, no transport running. Initial state.
  case idle

  /// Transport is being initialized (process launching).
  case starting

  /// Transport running, waiting for user input.
  case ready

  /// User message written to transport, waiting for response.
  case sending

  /// Assistant response is being streamed.
  case streaming

  /// Cancel requested, waiting for transport to confirm.
  case cancelling

  /// Crash recovery in progress.
  case recovering(attempt: Int)

  /// Unrecoverable failure.
  case failed(ChatSessionError)

  /// Session ended, cleanup done.
  case terminated

  /// Whether the session is in a state where user can send messages.
  var canSendMessage: Bool {
    switch self {
    case .idle, .ready:
      return true

    default:
      return false
    }
  }

  /// Whether the session is actively processing a turn.
  var isProcessingTurn: Bool {
    switch self {
    case .sending, .streaming:
      return true

    default:
      return false
    }
  }

  /// Whether the session can be cancelled.
  var canCancel: Bool {
    switch self {
    case .sending, .streaming:
      return true

    default:
      return false
    }
  }
}
