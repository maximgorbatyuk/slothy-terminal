import Foundation
import OSLog

/// View-facing state for the task queue.
///
/// Exposes user intents (enqueue, remove, reorder, retry, cancel, edit)
/// and orchestrator mutations (markRunning, markCompleted, markFailed, etc.).
/// Persists changes via `TaskQueueStore`.
@MainActor
@Observable
class TaskQueueState {
  var tasks: [QueuedTask] = []

  /// Called after every mutation so the orchestrator can wake up.
  var onQueueChanged: (() -> Void)?

  private let store: TaskQueueStore

  init(store: TaskQueueStore = .shared) {
    self.store = store
  }

  // MARK: - Restore

  /// Loads persisted queue from disk, applying crash recovery.
  func restoreFromDisk() {
    guard let snapshot = store.load() else {
      Logger.taskQueue.info("No persisted task queue found.")
      return
    }

    tasks = snapshot.tasks
    Logger.taskQueue.info("Restored \(snapshot.tasks.count) tasks from disk.")
  }

  // MARK: - User Intents

  /// Adds a new task to the queue with `.pending` status.
  func enqueueTask(
    title: String,
    prompt: String,
    repoPath: String,
    agentType: AgentType,
    model: ChatModelSelection? = nil,
    mode: ChatMode? = nil,
    priority: TaskPriority = .normal
  ) {
    let task = QueuedTask(
      id: UUID(),
      title: title,
      prompt: prompt,
      repoPath: repoPath,
      agentType: agentType,
      model: model,
      mode: mode,
      status: .pending,
      priority: priority,
      retryCount: 0,
      maxRetries: 3,
      createdAt: Date(),
      approvalState: .none
    )
    tasks.append(task)
    Logger.taskQueue.info("Enqueued task: \(task.id) — \(title)")
    persistAndNotify()
  }

  /// Removes a pending task from the queue.
  func removeTask(id: UUID) {
    guard let index = tasks.firstIndex(where: { $0.id == id }),
          tasks[index].status == .pending
    else {
      return
    }

    tasks.remove(at: index)
    Logger.taskQueue.info("Removed task: \(id)")
    persistAndNotify()
  }

  /// Reorders pending tasks via drag-and-drop offsets.
  func reorderTasks(fromOffsets: IndexSet, toOffset: Int) {
    tasks.move(fromOffsets: fromOffsets, toOffset: toOffset)
    persistAndNotify()
  }

  /// Retries a failed task — resets to pending and increments retry count.
  func retryTask(id: UUID) {
    guard let index = tasks.firstIndex(where: { $0.id == id }),
          tasks[index].status == .failed
    else {
      return
    }

    tasks[index].status = .pending
    tasks[index].retryCount += 1
    tasks[index].startedAt = nil
    tasks[index].finishedAt = nil
    tasks[index].lastError = nil
    tasks[index].exitReason = nil
    tasks[index].failureKind = nil
    tasks[index].runAttemptId = nil
    tasks[index].interruptedNote = nil
    Logger.taskQueue.info("Retrying task: \(self.tasks[index].id) (attempt \(self.tasks[index].retryCount))")
    persistAndNotify()
  }

  /// Cancels a pending task.
  func cancelTask(id: UUID) {
    guard let index = tasks.firstIndex(where: { $0.id == id }),
          tasks[index].status == .pending
    else {
      return
    }

    tasks[index].status = .cancelled
    tasks[index].exitReason = .cancelled
    tasks[index].finishedAt = Date()
    Logger.taskQueue.info("Cancelled task: \(self.tasks[index].id)")
    persistAndNotify()
  }

  /// Edits a pending task's mutable fields.
  func editTask(
    id: UUID,
    title: String? = nil,
    prompt: String? = nil,
    priority: TaskPriority? = nil
  ) {
    guard let index = tasks.firstIndex(where: { $0.id == id }),
          tasks[index].status == .pending
    else {
      return
    }

    if let title {
      tasks[index].title = title
    }

    if let prompt {
      tasks[index].prompt = prompt
    }

    if let priority {
      tasks[index].priority = priority
    }

    Logger.taskQueue.info("Edited task: \(self.tasks[index].id)")
    persistAndNotify()
  }

  // MARK: - Orchestrator Mutations

  /// Transitions a pending task to running with a new attempt ID.
  func markRunning(id: UUID, attemptId: UUID) {
    guard let index = tasks.firstIndex(where: { $0.id == id }),
          tasks[index].status == .pending
    else {
      Logger.taskQueue.warning("markRunning: task \(id) not found or not pending")
      return
    }

    tasks[index].status = .running
    tasks[index].runAttemptId = attemptId
    tasks[index].startedAt = Date()
    tasks[index].lastError = nil
    tasks[index].failureKind = nil
    Logger.taskQueue.info("Task \(id) → running (attempt \(attemptId))")
    persistSnapshot()
  }

  /// Transitions a running task to completed.
  func markCompleted(
    id: UUID,
    resultSummary: String?,
    logArtifactPath: String?,
    sessionId: String?
  ) {
    guard let index = tasks.firstIndex(where: { $0.id == id }),
          tasks[index].status == .running
    else {
      Logger.taskQueue.warning("markCompleted: task \(id) not found or not running")
      return
    }

    tasks[index].status = .completed
    tasks[index].exitReason = .completed
    tasks[index].finishedAt = Date()
    tasks[index].resultSummary = resultSummary
    tasks[index].logArtifactPath = logArtifactPath
    tasks[index].sessionId = sessionId
    Logger.taskQueue.info("Task \(id) → completed")
    persistAndNotify()
  }

  /// Transitions a running task to failed (terminal).
  func markFailed(
    id: UUID,
    error: String,
    exitReason: TaskExitReason,
    failureKind: FailureKind,
    logArtifactPath: String?
  ) {
    guard let index = tasks.firstIndex(where: { $0.id == id }),
          tasks[index].status == .running
    else {
      Logger.taskQueue.warning("markFailed: task \(id) not found or not running")
      return
    }

    tasks[index].status = .failed
    tasks[index].exitReason = exitReason
    tasks[index].failureKind = failureKind
    tasks[index].finishedAt = Date()
    tasks[index].lastError = error
    tasks[index].logArtifactPath = logArtifactPath
    Logger.taskQueue.info("Task \(id) → failed (\(failureKind.rawValue)): \(error)")
    persistAndNotify()
  }

  /// Transitions a running task back to pending for auto-retry.
  func markFailedForRetry(
    id: UUID,
    error: String,
    logArtifactPath: String?,
    failureKind: FailureKind
  ) {
    guard let index = tasks.firstIndex(where: { $0.id == id }),
          tasks[index].status == .running
    else {
      Logger.taskQueue.warning("markFailedForRetry: task \(id) not found or not running")
      return
    }

    tasks[index].status = .pending
    tasks[index].retryCount += 1
    tasks[index].lastError = error
    tasks[index].failureKind = failureKind
    tasks[index].logArtifactPath = logArtifactPath
    tasks[index].startedAt = nil
    tasks[index].finishedAt = nil
    tasks[index].runAttemptId = nil
    Logger.taskQueue.info(
      "Task \(id) → pending for retry (attempt \(self.tasks[index].retryCount)): \(error)"
    )
    persistAndNotify()
  }

  /// Cancels a running task.
  func cancelRunningTask(id: UUID) {
    guard let index = tasks.firstIndex(where: { $0.id == id }),
          tasks[index].status == .running
    else {
      Logger.taskQueue.warning("cancelRunningTask: task \(id) not found or not running")
      return
    }

    tasks[index].status = .cancelled
    tasks[index].exitReason = .cancelled
    tasks[index].finishedAt = Date()
    Logger.taskQueue.info("Task \(id) → cancelled (was running)")
    persistAndNotify()
  }

  /// Flushes any pending snapshot to disk immediately.
  func saveImmediately() {
    store.saveImmediately()
  }

  // MARK: - Private

  private func persistSnapshot() {
    let snapshot = TaskQueueSnapshot(tasks: tasks)
    store.save(snapshot: snapshot)
  }

  private func persistAndNotify() {
    persistSnapshot()
    onQueueChanged?()
  }
}
