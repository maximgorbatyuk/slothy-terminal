import Foundation

/// Lifecycle status of an injection request.
enum InjectionStatus: String, Codable, Equatable, Sendable {
  case accepted
  case queued
  case written
  case completed
  case failed
  case cancelled
  case timeout
}

/// Where the injection request originated.
enum InjectionOrigin: String, Codable, Equatable, Sendable {
  case ui
  case automation
  case telegram
  case externalAPI
}

/// A request to inject content into one or more terminal tabs.
struct InjectionRequest: Codable, Identifiable, Equatable, Sendable {
  let id: UUID
  let payload: InjectionPayload
  let target: InjectionTarget
  let origin: InjectionOrigin
  var status: InjectionStatus
  let createdAt: Date
  let timeoutSeconds: TimeInterval?

  init(
    id: UUID = UUID(),
    payload: InjectionPayload,
    target: InjectionTarget,
    origin: InjectionOrigin = .automation,
    status: InjectionStatus = .accepted,
    createdAt: Date = Date(),
    timeoutSeconds: TimeInterval? = nil
  ) {
    self.id = id
    self.payload = payload
    self.target = target
    self.origin = origin
    self.status = status
    self.createdAt = createdAt
    self.timeoutSeconds = timeoutSeconds
  }
}
