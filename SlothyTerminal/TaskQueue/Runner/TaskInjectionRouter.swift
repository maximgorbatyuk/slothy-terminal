import Foundation
import OSLog

/// Metadata about a candidate terminal tab for task prompt injection.
struct InjectableTabCandidate: Equatable, Sendable {
  let tabId: UUID
  let agentType: AgentType
  let workingDirectory: URL
  let isActive: Bool
  let isRegistered: Bool
}

/// Abstraction for app-layer injection capabilities, testable without AppState.
@MainActor
protocol TaskInjectionProvider: AnyObject {
  /// Returns terminal tabs matching the given agent type with routing metadata.
  func injectableTabCandidates(agentType: AgentType) -> [InjectableTabCandidate]

  /// Submits an injection request. Returns the request with updated status,
  /// or nil if the injection orchestrator is unavailable.
  func submitInjection(_ request: InjectionRequest) -> InjectionRequest?

  /// Cancels a pending injection request.
  func cancelInjection(requestId: UUID)
}

/// Outcome of an injection routing attempt.
enum TaskInjectionResult: Equatable {
  case injected(requestId: UUID, tabId: UUID, summary: String)
  case noMatchingTab
  case failed(reason: String)
}

/// Routes task prompts to matching terminal tabs via the injection API.
///
/// Resolves the best-matching injectable terminal tab for a task based on
/// agent type, working directory, and surface registration, then submits
/// the prompt as a command injection.
@MainActor
class TaskInjectionRouter {
  private weak var provider: TaskInjectionProvider?

  init(provider: TaskInjectionProvider) {
    self.provider = provider
  }

  /// Attempts to inject the task prompt into a matching terminal tab.
  ///
  /// Returns `.injected` on success, `.noMatchingTab` if no suitable tab
  /// exists, or `.failed` if the injection submission did not succeed.
  func attemptInjection(
    task: QueuedTask,
    logCollector: TaskLogCollector
  ) -> TaskInjectionResult {
    let shortTaskId = String(task.id.uuidString.prefix(8))
    logCollector.append("[injection] Attempting injection for task \(shortTaskId)")
    logCollector.append("[injection] Agent: \(task.agentType.rawValue), repoPath: \(task.repoPath)")

    guard let provider else {
      logCollector.append("[injection] Provider deallocated — will fall back to headless runner")
      return .failed(reason: "Injection provider unavailable")
    }

    /// Get candidate tabs matching agent type.
    let candidates = provider.injectableTabCandidates(agentType: task.agentType)
    logCollector.append("[injection] Found \(candidates.count) candidate tab(s)")

    guard !candidates.isEmpty else {
      logCollector.append("[injection] No matching tabs — will fall back to headless runner")
      return .noMatchingTab
    }

    /// Filter by working directory.
    let taskPath = Self.normalizePath(task.repoPath)
    let directoryMatched = candidates.filter { candidate in
      let tabPath = Self.normalizePath(candidate.workingDirectory.path)
      return tabPath == taskPath
    }
    logCollector.append("[injection] \(directoryMatched.count) tab(s) match working directory")

    guard !directoryMatched.isEmpty else {
      logCollector.append("[injection] No directory-matching tabs — will fall back to headless runner")
      return .noMatchingTab
    }

    /// Keep only tabs with a live surface in the registry.
    let injectable = directoryMatched.filter(\.isRegistered)
    logCollector.append("[injection] \(injectable.count) tab(s) have live surfaces")

    guard !injectable.isEmpty else {
      logCollector.append("[injection] No injectable tabs (surfaces not registered) — will fall back")
      return .noMatchingTab
    }

    /// Prefer active matching tab; otherwise pick first.
    let target = injectable.first(where: \.isActive) ?? injectable[0]
    let shortTabId = String(target.tabId.uuidString.prefix(8))
    logCollector.append("[injection] Selected tab \(shortTabId) (active: \(target.isActive))")

    /// Build and submit injection request.
    let request = InjectionRequest(
      payload: .command(task.prompt, submit: .execute),
      target: .tabId(target.tabId),
      origin: .automation
    )

    guard let result = provider.submitInjection(request) else {
      logCollector.append("[injection] Injection orchestrator unavailable — will fall back")
      return .failed(reason: "Injection orchestrator unavailable")
    }

    /// Evaluate result status.
    let agentName = task.agentType.rawValue

    switch result.status {
    case .completed, .written, .accepted, .queued:
      let summary = "Prompt injected into existing \(agentName) terminal tab \(shortTabId); continue in that tab."
      logCollector.append("[injection] Success — \(summary)")
      Logger.taskQueue.info("Task \(shortTaskId) injected into tab \(shortTabId)")
      return .injected(requestId: request.id, tabId: target.tabId, summary: summary)

    case .failed:
      logCollector.append("[injection] Injection failed — will fall back to headless runner")
      return .failed(reason: "Injection failed")

    case .cancelled:
      logCollector.append("[injection] Injection cancelled — will fall back to headless runner")
      return .failed(reason: "Injection cancelled")

    case .timeout:
      logCollector.append("[injection] Injection timed out — will fall back to headless runner")
      return .failed(reason: "Injection timed out")
    }
  }

  /// Cancels an in-flight injection request.
  func cancelInjection(requestId: UUID) {
    provider?.cancelInjection(requestId: requestId)
  }

  /// Normalizes a file path for comparison.
  ///
  /// Expands `~`, resolves symlinks via `standardizingPath`, and strips
  /// trailing slashes for consistent directory comparison.
  static func normalizePath(_ path: String) -> String {
    var normalized = NSString(string: path).expandingTildeInPath
    normalized = (normalized as NSString).standardizingPath

    while normalized.hasSuffix("/") && normalized.count > 1 {
      normalized = String(normalized.dropLast())
    }

    return normalized
  }
}
