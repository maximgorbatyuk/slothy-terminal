import Foundation

/// Errors surfaced by the session engine.
///
/// Replaces `ChatError` for engine-level concerns with more specific
/// error cases covering transport failures and recovery.
enum ChatSessionError: LocalizedError, Equatable {
  /// Chat CLI was not found at any expected path.
  case transportNotAvailable(String)

  /// Process failed to launch.
  case transportStartFailed(String)

  /// Process crashed with non-zero exit code.
  case transportCrashed(exitCode: Int32, stderr: String)

  /// Recovery failed after maximum retry attempts.
  case maxRetriesExceeded(Int)

  /// Invalid state transition (programming error).
  case invalidState(String)

  var errorDescription: String? {
    switch self {
    case .transportNotAvailable(let detail):
      return "Chat CLI not found: \(detail)"

    case .transportStartFailed(let detail):
      return "Failed to start chat transport: \(detail)"

    case .transportCrashed(let exitCode, let stderr):
      if stderr.isEmpty {
        return "Chat process crashed (exit code \(exitCode))"
      }
      return "Chat process crashed: \(stderr)"

    case .maxRetriesExceeded(let attempts):
      return "Recovery failed after \(attempts) attempts"

    case .invalidState(let detail):
      return "Internal error: \(detail)"
    }
  }
}
