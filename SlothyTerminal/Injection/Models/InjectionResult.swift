import Foundation

/// The outcome of an injection request for a specific tab.
struct InjectionResult: Codable, Equatable, Sendable {
  let requestId: UUID
  let tabId: UUID
  let status: InjectionStatus
  let error: String?
  let completedAt: Date

  init(
    requestId: UUID,
    tabId: UUID,
    status: InjectionStatus,
    error: String? = nil,
    completedAt: Date = Date()
  ) {
    self.requestId = requestId
    self.tabId = tabId
    self.status = status
    self.error = error
    self.completedAt = completedAt
  }
}
