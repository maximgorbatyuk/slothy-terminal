import Foundation
import OSLog

/// Provides tab information to the injection orchestrator without coupling to AppState.
@MainActor
protocol InjectionTabProvider: AnyObject {
  /// The currently active tab ID, if any.
  var activeTabId: UUID? { get }

  /// Returns tab IDs matching the given criteria (terminal-mode tabs only).
  func terminalTabs(agentType: AgentType?, mode: TabMode?) -> [UUID]
}

/// Processes injection requests with per-tab FIFO queues.
@MainActor
class InjectionOrchestrator {
  /// Default timeout for injection entries.
  static let defaultTimeout: TimeInterval = 10

  /// Maximum number of completed requests to retain for status lookup.
  static let maxHistorySize = 500

  private let registry: TerminalSurfaceRegistry
  private weak var tabProvider: InjectionTabProvider?

  /// Per-tab FIFO queues.
  private var tabQueues: [UUID: [QueueEntry]] = [:]

  /// All known requests by ID for status lookup.
  private var requests: [UUID: InjectionRequest] = [:]

  /// Ordered list of completed request IDs for history eviction.
  private var completedRequestIds: [UUID] = []

  /// Callback for lifecycle events.
  var onEvent: ((InjectionEvent) -> Void)?

  init(registry: TerminalSurfaceRegistry, tabProvider: InjectionTabProvider) {
    self.registry = registry
    self.tabProvider = tabProvider
  }

  // MARK: - Public API

  /// Submits an injection request. Returns the request with updated status.
  @discardableResult
  func submit(_ request: InjectionRequest) -> InjectionRequest {
    var req = request
    Logger.injection.info("Injection request \(req.id.uuidString): accepted")
    emitEvent(.requestAccepted(requestId: req.id))

    let tabIds = resolveTargetTabs(req.target)

    guard !tabIds.isEmpty else {
      req.status = .failed
      requests[req.id] = req
      trackCompleted(req.id)
      Logger.injection.warning("Injection request \(req.id.uuidString): no matching tabs")
      emitEvent(.requestFailed(requestId: req.id, error: "No matching tabs"))
      return req
    }

    req.status = .queued
    requests[req.id] = req

    for tabId in tabIds {
      let entry = QueueEntry(
        requestId: req.id,
        tabId: tabId,
        payload: req.payload,
        timeout: req.timeoutSeconds ?? Self.defaultTimeout,
        createdAt: req.createdAt
      )
      tabQueues[tabId, default: []].append(entry)
      emitEvent(.requestQueued(requestId: req.id, tabId: tabId))
    }

    processQueues(for: tabIds)
    return requests[req.id] ?? req
  }

  /// Cancels a pending injection request.
  func cancel(requestId: UUID) {
    guard var req = requests[requestId] else {
      return
    }

    guard req.status == .accepted || req.status == .queued else {
      return
    }

    req.status = .cancelled
    requests[requestId] = req
    trackCompleted(requestId)

    // Remove from all tab queues.
    for tabId in tabQueues.keys {
      tabQueues[tabId]?.removeAll { $0.requestId == requestId }
    }

    Logger.injection.info("Injection request \(requestId.uuidString): cancelled")
    emitEvent(.requestCancelled(requestId: requestId))
  }

  /// Returns the current status of a request.
  func status(for requestId: UUID) -> InjectionStatus? {
    requests[requestId]?.status
  }

  // MARK: - Target Resolution

  private func resolveTargetTabs(_ target: InjectionTarget) -> [UUID] {
    switch target {
    case .activeTab:
      guard let activeId = tabProvider?.activeTabId else {
        return []
      }

      return [activeId]

    case .tabId(let id):
      return [id]

    case .filtered(let agentType, let mode):
      return tabProvider?.terminalTabs(agentType: agentType, mode: mode) ?? []
    }
  }

  // MARK: - Queue Processing

  private func processQueues(for tabIds: [UUID]) {
    for tabId in tabIds {
      processQueue(for: tabId)
    }
  }

  private func processQueue(for tabId: UUID) {
    guard var queue = tabQueues[tabId], !queue.isEmpty else {
      return
    }

    while !queue.isEmpty {
      let entry = queue[0]

      // Check timeout.
      if Date().timeIntervalSince(entry.createdAt) > entry.timeout {
        queue.removeFirst()
        tabQueues[tabId] = queue
        escalateRequestStatus(entry.requestId, to: .timeout)
        Logger.injection.warning("Injection request \(entry.requestId.uuidString) timed out for tab \(tabId.uuidString)")
        emitEvent(.requestTimedOut(requestId: entry.requestId, tabId: tabId))
        continue
      }

      // Try to write to surface.
      guard let surface = registry.surface(for: tabId) else {
        queue.removeFirst()
        tabQueues[tabId] = queue
        escalateRequestStatus(entry.requestId, to: .failed)
        Logger.injection.warning("Injection request \(entry.requestId.uuidString): no surface for tab \(tabId.uuidString)")
        emitEvent(.requestFailed(requestId: entry.requestId, tabId: tabId, error: "No surface registered"))
        continue
      }

      let success = executePayload(entry.payload, on: surface)
      queue.removeFirst()
      tabQueues[tabId] = queue

      if success {
        escalateRequestStatus(entry.requestId, to: .completed)
        Logger.injection.info("Injection request \(entry.requestId.uuidString): written to tab \(tabId.uuidString)")
        emitEvent(.requestWritten(requestId: entry.requestId, tabId: tabId))
        emitEvent(.requestCompleted(requestId: entry.requestId, tabId: tabId))
      } else {
        escalateRequestStatus(entry.requestId, to: .failed)
        Logger.injection.warning("Injection request \(entry.requestId.uuidString): surface write failed for tab \(tabId.uuidString)")
        emitEvent(.requestFailed(requestId: entry.requestId, tabId: tabId, error: "Surface write failed"))
      }
    }
  }

  private func executePayload(_ payload: InjectionPayload, on surface: InjectableSurface) -> Bool {
    switch payload {
    case .text(let text):
      return surface.injectText(text)

    case .command(let cmd, let submit):
      return surface.injectCommand(cmd, submit: submit)

    case .paste(let text, let mode):
      return surface.injectPaste(text, mode: mode)

    case .control(let signal):
      return surface.injectControl(signal)

    case .key(let keyCode, let modifiers):
      return surface.injectKey(keyCode: keyCode, modifiers: modifiers)
    }
  }

  /// Updates request status using "worst wins" — failure/timeout is never
  /// overwritten by a later success from another tab.
  private func escalateRequestStatus(_ requestId: UUID, to newStatus: InjectionStatus) {
    guard let current = requests[requestId]?.status else {
      return
    }

    // Terminal failure states are never overwritten.
    if current == .failed || current == .timeout || current == .cancelled {
      return
    }

    requests[requestId]?.status = newStatus

    // Track completed terminal states for history eviction.
    if newStatus == .completed || newStatus == .failed || newStatus == .timeout {
      trackCompleted(requestId)
    }
  }

  private func emitEvent(_ event: InjectionEvent) {
    onEvent?(event)
  }

  // MARK: - History Management

  private func trackCompleted(_ requestId: UUID) {
    guard !completedRequestIds.contains(requestId) else {
      return
    }

    completedRequestIds.append(requestId)

    // Evict oldest entries when history exceeds limit.
    while completedRequestIds.count > Self.maxHistorySize {
      let oldId = completedRequestIds.removeFirst()
      requests.removeValue(forKey: oldId)
    }
  }
}

// MARK: - Queue Entry

private struct QueueEntry {
  let requestId: UUID
  let tabId: UUID
  let payload: InjectionPayload
  let timeout: TimeInterval
  let createdAt: Date
}
