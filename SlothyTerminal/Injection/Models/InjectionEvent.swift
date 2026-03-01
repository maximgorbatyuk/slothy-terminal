import Foundation

/// Observable lifecycle events emitted by the injection orchestrator.
enum InjectionEvent: Equatable, Sendable {
  case requestAccepted(requestId: UUID)
  case requestQueued(requestId: UUID, tabId: UUID)
  case requestWritten(requestId: UUID, tabId: UUID)
  case requestCompleted(requestId: UUID, tabId: UUID)
  case requestFailed(requestId: UUID, tabId: UUID? = nil, error: String)
  case requestCancelled(requestId: UUID)
  case requestTimedOut(requestId: UUID, tabId: UUID)
}
