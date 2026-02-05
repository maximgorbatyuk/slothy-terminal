import Foundation

/// Errors that can occur during chat operations.
enum ChatError: LocalizedError {
  case processFailure(String)
  case claudeNotFound
  case invalidResponse(String)
  case cancelled

  var errorDescription: String? {
    switch self {
    case .processFailure(let message):
      return "Process failed: \(message)"

    case .claudeNotFound:
      return "Claude CLI not found. Install it with: npm install -g @anthropic-ai/claude-cli"

    case .invalidResponse(let message):
      return "Invalid response: \(message)"

    case .cancelled:
      return "Response was cancelled"
    }
  }
}
