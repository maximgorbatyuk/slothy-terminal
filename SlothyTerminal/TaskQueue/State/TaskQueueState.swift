import Foundation
import OSLog

/// View-facing state for the task queue.
///
/// Exposes user intents (enqueue, remove, reorder, retry, cancel, edit)
/// and persists changes via `TaskQueueStore`. No execution capability yet.
@MainActor
@Observable
class TaskQueueState {
  var tasks: [QueuedTask] = []

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
    persistSnapshot()
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
    persistSnapshot()
  }

  /// Reorders pending tasks via drag-and-drop offsets.
  func reorderTasks(fromOffsets: IndexSet, toOffset: Int) {
    tasks.move(fromOffsets: fromOffsets, toOffset: toOffset)
    persistSnapshot()
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
    tasks[index].runAttemptId = nil
    tasks[index].interruptedNote = nil
    Logger.taskQueue.info("Retrying task: \(self.tasks[index].id) (attempt \(self.tasks[index].retryCount))")
    persistSnapshot()
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
    persistSnapshot()
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
    persistSnapshot()
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
}
