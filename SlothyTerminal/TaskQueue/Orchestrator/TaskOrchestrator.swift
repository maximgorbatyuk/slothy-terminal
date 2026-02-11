import Foundation
import OSLog

/// Drives sequential headless task execution.
///
/// Picks the next pending task, validates it, creates a runner, and
/// manages the execution lifecycle including timeout, cancellation, and
/// auto-retry for transient failures.
@MainActor
class TaskOrchestrator {
  /// 30-minute execution timeout.
  static let executionTimeoutNanos: UInt64 = 30 * 60 * 1_000_000_000

  private let queueState: TaskQueueState
  private let runnerFactory: (QueuedTask) -> TaskRunner

  private var isRunning = false
  private var currentRunner: TaskRunner?
  private var currentTaskId: UUID?
  private var executionTask: Task<Void, Never>?
  private var timeoutTask: Task<Void, Never>?
  private var pendingWakeUp = false

  init(
    queueState: TaskQueueState,
    runnerFactory: @escaping (QueuedTask) -> TaskRunner
  ) {
    self.queueState = queueState
    self.runnerFactory = runnerFactory
  }

  /// Convenience initializer using default runner factory.
  convenience init(queueState: TaskQueueState) {
    self.init(queueState: queueState) { task in
      let workingDir = URL(fileURLWithPath: task.repoPath)

      switch task.agentType {
      case .claude:
        return ClaudeTaskRunner(
          workingDirectory: workingDir,
          selectedModel: task.model
        )

      case .opencode:
        return OpenCodeTaskRunner(
          workingDirectory: workingDir,
          selectedModel: task.model,
          selectedMode: task.mode
        )

      case .terminal:
        /// Terminal doesn't support headless execution.
        /// Preflight should catch this, but provide a fallback.
        return ClaudeTaskRunner(
          workingDirectory: workingDir,
          selectedModel: task.model
        )
      }
    }
  }

  /// Starts the orchestrator scheduling loop.
  func start() {
    guard !isRunning else {
      return
    }

    isRunning = true
    Logger.taskQueue.info("TaskOrchestrator started")
    scheduleNext()
  }

  /// Stops the orchestrator and cancels any running task.
  func stop() {
    guard isRunning else {
      return
    }

    isRunning = false
    timeoutTask?.cancel()
    timeoutTask = nil
    currentRunner?.cancel()
    currentRunner = nil
    executionTask?.cancel()
    executionTask = nil
    currentTaskId = nil
    Logger.taskQueue.info("TaskOrchestrator stopped")
  }

  /// Cancels the currently running task, if any.
  func cancelRunningTask() {
    guard let taskId = currentTaskId else {
      return
    }

    Logger.taskQueue.info("Cancelling running task \(taskId)")
    timeoutTask?.cancel()
    timeoutTask = nil
    currentRunner?.cancel()
    queueState.cancelRunningTask(id: taskId)
    currentRunner = nil
    currentTaskId = nil
    executionTask?.cancel()
    executionTask = nil
    scheduleNext()
  }

  /// Called by `TaskQueueState.onQueueChanged` to wake up the loop.
  func notifyQueueChanged() {
    guard isRunning else {
      return
    }

    /// If already executing, just note that we need to check again.
    if currentTaskId != nil {
      pendingWakeUp = true
      return
    }

    scheduleNext()
  }

  // MARK: - Private

  private func scheduleNext() {
    guard isRunning,
          currentTaskId == nil
    else {
      return
    }

    guard let task = selectNextTask() else {
      Logger.taskQueue.debug("No pending tasks to execute")
      return
    }

    executeTask(task)
  }

  /// Selects the next pending task: highest priority first, then FIFO by createdAt.
  private func selectNextTask() -> QueuedTask? {
    queueState.tasks
      .filter { $0.status == .pending }
      .sorted { lhs, rhs in
        if lhs.priority != rhs.priority {
          return lhs.priority < rhs.priority
        }

        return lhs.createdAt < rhs.createdAt
      }
      .first
  }

  private func executeTask(_ task: QueuedTask) {
    Logger.taskQueue.info("Executing task \(task.id): \(task.title)")

    /// Preflight validation.
    let preflightResult = TaskPreflight.validate(task)

    guard preflightResult.isSuccess else {
      let errorMessage = preflightResult.errorMessage ?? "Preflight validation failed"
      Logger.taskQueue.error("Preflight failed for \(task.id): \(errorMessage)")

      /// Mark as pending first so markFailed can transition from running.
      /// Actually preflight failures go straight to failed — mark running then failed.
      let attemptId = UUID()
      queueState.markRunning(id: task.id, attemptId: attemptId)
      queueState.markFailed(
        id: task.id,
        error: errorMessage,
        exitReason: .failed,
        failureKind: .permanent,
        logArtifactPath: nil
      )
      scheduleNext()
      return
    }

    let attemptId = UUID()
    queueState.markRunning(id: task.id, attemptId: attemptId)
    currentTaskId = task.id

    let runner = runnerFactory(task)
    currentRunner = runner

    let logCollector = TaskLogCollector(taskId: task.id, attemptId: attemptId)

    /// Start timeout timer.
    timeoutTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: Self.executionTimeoutNanos)

      guard !Task.isCancelled,
            let self,
            self.currentTaskId == task.id
      else {
        return
      }

      Logger.taskQueue.warning("Task \(task.id) timed out after 30 minutes")
      logCollector.append("TIMEOUT: Task exceeded 30-minute limit")
      runner.cancel()

      let logPath = logCollector.flush()
      self.handleFailure(
        taskId: task.id,
        task: task,
        error: TaskRunError.timeout,
        logArtifactPath: logPath
      )
    }

    /// Execute in background.
    executionTask = Task { [weak self] in
      do {
        let result = try await runner.execute(task: task, logCollector: logCollector)

        guard !Task.isCancelled,
              let self
        else {
          return
        }

        self.timeoutTask?.cancel()
        self.timeoutTask = nil

        self.queueState.markCompleted(
          id: task.id,
          resultSummary: result.resultSummary,
          logArtifactPath: result.logArtifactPath,
          sessionId: result.sessionId
        )

        self.finishExecution()
      } catch {
        guard !Task.isCancelled,
              let self
        else {
          return
        }

        self.timeoutTask?.cancel()
        self.timeoutTask = nil

        let logPath = logCollector.flush()
        self.handleFailure(
          taskId: task.id,
          task: task,
          error: error,
          logArtifactPath: logPath
        )
      }
    }
  }

  private func handleFailure(
    taskId: UUID,
    task: QueuedTask,
    error: Error,
    logArtifactPath: String?
  ) {
    let errorMessage = error.localizedDescription

    let failureKind: FailureKind
    let exitReason: TaskExitReason

    if let runError = error as? TaskRunError {
      failureKind = runError.failureKind

      switch runError {
      case .timeout:
        exitReason = .timeout

      case .cancelled:
        exitReason = .cancelled

      default:
        exitReason = .failed
      }
    } else {
      failureKind = .transient
      exitReason = .failed
    }

    /// Auto-retry transient failures under the retry limit.
    if failureKind == .transient,
       task.retryCount < task.maxRetries
    {
      Logger.taskQueue.info(
        "Auto-retrying task \(taskId) (transient failure, attempt \(task.retryCount + 1)/\(task.maxRetries))"
      )
      queueState.markFailedForRetry(
        id: taskId,
        error: errorMessage,
        logArtifactPath: logArtifactPath,
        failureKind: failureKind
      )
    } else {
      queueState.markFailed(
        id: taskId,
        error: errorMessage,
        exitReason: exitReason,
        failureKind: failureKind,
        logArtifactPath: logArtifactPath
      )
    }

    finishExecution()
  }

  private func finishExecution() {
    currentRunner = nil
    currentTaskId = nil
    executionTask = nil
    pendingWakeUp = false
    scheduleNext()
  }
}
