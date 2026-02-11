import Foundation

/// Commands emitted by the engine for the adapter (ChatState) to execute.
///
/// The engine never does I/O itself. It tells the adapter what to do
/// via these commands after processing each event.
enum ChatSessionCommand {
  /// Start (or restart) the transport process.
  case startTransport(workingDirectory: URL, resumeSessionId: String?)

  /// Send a user message through the transport.
  case sendMessage(String)

  /// Send SIGINT to interrupt the current generation.
  case interruptTransport

  /// Fully terminate the transport process.
  case terminateTransport

  /// Attempt crash recovery with the given session ID.
  case attemptRecovery(sessionId: String, attempt: Int)

  /// Tell the storage layer to persist a snapshot.
  case persistSnapshot

  /// Signal that a turn has completed (UI can update).
  case turnComplete

  /// Surface an error to the UI layer.
  case surfaceError(ChatSessionError)
}
