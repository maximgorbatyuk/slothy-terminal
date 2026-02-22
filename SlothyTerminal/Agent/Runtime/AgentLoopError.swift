import Foundation

/// Errors that can occur during agent loop execution.
enum AgentLoopError: Error, Sendable {
  /// The agent exceeded its maximum allowed steps.
  case maxStepsExceeded(limit: Int)

  /// The agent made 3+ identical tool calls (same tool + same arguments).
  case doomLoopDetected(toolID: String)

  /// The LLM returned a response that could not be parsed.
  case invalidResponse(detail: String)

  /// The loop was cancelled externally.
  case cancelled

  /// No adapter registered for the requested provider.
  case noAdapter(provider: ProviderID)
}

extension AgentLoopError: LocalizedError {
  var errorDescription: String? {
    switch self {
    case .maxStepsExceeded(let limit):
      return "Agent exceeded maximum step limit (\(limit))"

    case .doomLoopDetected(let toolID):
      return "Detected repeated identical calls to tool '\(toolID)'"

    case .invalidResponse(let detail):
      return "Invalid LLM response: \(detail)"

    case .cancelled:
      return "Agent loop was cancelled"

    case .noAdapter(let provider):
      return "No adapter registered for provider '\(provider.rawValue)'"
    }
  }
}
