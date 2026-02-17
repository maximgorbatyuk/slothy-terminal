import Foundation

/// Protocol for headless single-turn task execution.
///
/// Each runner wraps a `ChatTransport` to execute one prompt and collect
/// the result. Runners are single-use: one instance per execution attempt.
protocol TaskRunner: AnyObject {
  /// Executes the task prompt and waits for a terminal result.
  func execute(task: QueuedTask, logCollector: TaskLogCollector) async throws -> TaskRunResult

  /// Cancels the running execution (SIGINT + force-kill timer).
  func cancel()
}

/// Result of a completed task execution attempt.
struct TaskRunResult {
  let exitReason: TaskExitReason
  let resultSummary: String?
  let logArtifactPath: String?
  let sessionId: String?
  let failureKind: FailureKind?
  let errorMessage: String?
  let detectedRiskyOperations: [String]
}

/// Errors that can occur during task runner execution.
enum TaskRunError: LocalizedError, Equatable {
  case transportNotAvailable(String)
  case transportCrashed(exitCode: Int32, stderr: String)
  case timeout
  case cancelled
  case promptEmpty

  var failureKind: FailureKind {
    switch self {
    case .transportCrashed, .timeout:
      return .transient

    case .transportNotAvailable, .cancelled, .promptEmpty:
      return .permanent
    }
  }

  var errorDescription: String? {
    switch self {
    case .transportNotAvailable(let detail):
      return "CLI not found: \(detail)"

    case .transportCrashed(let exitCode, let stderr):
      if stderr.isEmpty {
        return "Process crashed (exit code \(exitCode))"
      }
      return "Process crashed: \(stderr.prefix(200))"

    case .timeout:
      return "Task timed out"

    case .cancelled:
      return "Task was cancelled"

    case .promptEmpty:
      return "Task prompt is empty"
    }
  }
}
