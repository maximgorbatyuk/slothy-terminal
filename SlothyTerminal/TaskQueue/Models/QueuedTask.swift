import Foundation

/// Status of a queued task in its lifecycle.
enum TaskStatus: String, Codable, CaseIterable {
  case pending
  case running
  case completed
  case failed
  case cancelled
}

/// Priority level for queue ordering.
enum TaskPriority: String, Codable, CaseIterable, Comparable {
  case high
  case normal
  case low

  private var sortOrder: Int {
    switch self {
    case .high:
      return 0

    case .normal:
      return 1

    case .low:
      return 2
    }
  }

  static func < (lhs: TaskPriority, rhs: TaskPriority) -> Bool {
    lhs.sortOrder < rhs.sortOrder
  }
}

/// Why a task exited — provides more detail than `TaskStatus`.
enum TaskExitReason: String, Codable {
  case completed
  case failed
  case cancelled
  case timeout
  case approvalRejected
}

/// Approval state for tasks that require human confirmation.
enum TaskApprovalState: String, Codable {
  case none
  case waiting
  case approved
  case rejected
}

/// Classification of failures for retry decisions.
enum FailureKind: String, Codable {
  case transient
  case permanent
}

/// A single task in the background execution queue.
struct QueuedTask: Codable, Identifiable, Equatable {
  let id: UUID
  var title: String
  var prompt: String
  var repoPath: String
  var agentType: AgentType
  var model: ChatModelSelection?
  var mode: ChatMode?
  var status: TaskStatus
  var priority: TaskPriority
  var retryCount: Int
  var maxRetries: Int
  var runAttemptId: UUID?
  var createdAt: Date
  var startedAt: Date?
  var finishedAt: Date?
  var lastError: String?
  var resultSummary: String?
  var exitReason: TaskExitReason?
  var sessionId: String?
  var approvalState: TaskApprovalState
  var logArtifactPath: String?
  var failureKind: FailureKind?

  /// Set on crash recovery when a running task is found during restore.
  var interruptedNote: String?

  /// Whether this task is in a terminal state (no further transitions).
  var isTerminal: Bool {
    switch status {
    case .completed, .failed, .cancelled:
      return true

    case .pending, .running:
      return false
    }
  }

  /// Whether this task can be retried (failed and under retry limit).
  var isRetryable: Bool {
    status == .failed && retryCount < maxRetries
  }

  /// Whether this task's title, prompt, and priority can be edited.
  var canEdit: Bool {
    status == .pending
  }
}
