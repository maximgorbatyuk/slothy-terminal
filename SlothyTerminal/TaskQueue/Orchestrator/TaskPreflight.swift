import Foundation

/// Static validation before task execution.
///
/// All preflight failures are permanent — the task will not be retried.
enum TaskPreflight {

  /// Validates that a task is ready for execution.
  ///
  /// Checks:
  /// 1. Prompt is non-empty
  /// 2. Repo path exists and is a directory
  /// 3. Agent supports chat mode
  /// 4. Agent CLI is installed
  static func validate(_ task: QueuedTask) -> TaskPreflightResult {
    guard !task.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return .failure("Task prompt is empty")
    }

    var isDirectory: ObjCBool = false
    let pathExists = FileManager.default.fileExists(
      atPath: task.repoPath,
      isDirectory: &isDirectory
    )

    guard pathExists,
          isDirectory.boolValue
    else {
      return .failure("Repo path does not exist or is not a directory: \(task.repoPath)")
    }

    guard task.agentType.supportsChatMode else {
      return .failure("Agent \(task.agentType.rawValue) does not support chat mode")
    }

    let agent = AgentFactory.createAgent(for: task.agentType)

    guard agent.isAvailable() else {
      return .failure("\(task.agentType.rawValue) CLI is not installed")
    }

    return .success
  }
}

/// Result of preflight validation.
enum TaskPreflightResult {
  case success
  case failure(String)

  var isSuccess: Bool {
    if case .success = self {
      return true
    }

    return false
  }

  var errorMessage: String? {
    if case .failure(let message) = self {
      return message
    }

    return nil
  }
}
