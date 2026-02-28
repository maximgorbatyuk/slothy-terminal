import Foundation
import OSLog

/// Executes prompts via task runners, one at a time (FIFO).
///
/// Uses an actor to serialize concurrent execute() calls. Each call
/// waits for the previous execution to finish before starting.
actor TelegramPromptExecutor {
  private let workingDirectory: URL
  private let agentType: AgentType
  private var currentRunner: TaskRunner?
  private var isCancelled = false

  /// Continuation for the currently running execution, if any.
  /// New calls wait on this before starting their own execution.
  private var inFlightTask: Task<String, Error>?

  init(workingDirectory: URL, agentType: AgentType) {
    self.workingDirectory = workingDirectory
    self.agentType = agentType
  }

  /// Executes a prompt and returns the result summary text.
  /// If another prompt is already executing, this waits for it to finish first.
  func execute(prompt: String) async throws -> String {
    guard !isCancelled else {
      throw TaskRunError.cancelled
    }

    /// Wait for any in-flight execution to complete before starting ours.
    if let existing = inFlightTask {
      _ = try? await existing.value
    }

    guard !isCancelled else {
      throw TaskRunError.cancelled
    }

    let task = Task<String, Error> {
      try await runPrompt(prompt)
    }

    inFlightTask = task

    do {
      let result = try await task.value
      inFlightTask = nil
      return result
    } catch {
      inFlightTask = nil
      throw error
    }
  }

  /// Cancels the current and any pending executions.
  func cancel() {
    isCancelled = true
    currentRunner?.cancel()
    currentRunner = nil
    inFlightTask?.cancel()
    inFlightTask = nil
  }

  /// Returns true when an execution is currently running.
  func isBusy() -> Bool {
    inFlightTask != nil
  }

  // MARK: - Private

  private func runPrompt(_ prompt: String) async throws -> String {
    let queuedTask = QueuedTask(
      id: UUID(),
      title: "Telegram prompt",
      prompt: prompt,
      repoPath: workingDirectory.path,
      agentType: agentType,
      model: nil,
      mode: nil,
      status: .running,
      priority: .normal,
      retryCount: 0,
      maxRetries: 0,
      createdAt: Date(),
      approvalState: .none
    )

    let logCollector = TaskLogCollector(taskId: queuedTask.id, attemptId: UUID())

    let runner: TaskRunner
    switch agentType {
    case .claude:
      runner = ClaudeTaskRunner(workingDirectory: workingDirectory, selectedModel: nil)

    case .opencode:
      runner = OpenCodeTaskRunner(workingDirectory: workingDirectory, selectedModel: nil, selectedMode: nil)

    case .terminal:
      throw TaskRunError.transportNotAvailable("Terminal agent cannot execute prompts")
    }

    currentRunner = runner

    Logger.telegram.info("Executing prompt (\(prompt.count) chars) via \(self.agentType.rawValue)")

    let result = try await runner.execute(task: queuedTask, logCollector: logCollector)
    currentRunner = nil

    return result.resultSummary ?? "Completed (no summary)"
  }
}
