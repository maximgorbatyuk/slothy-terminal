import Foundation

/// Serializable snapshot of the entire task queue for persistence.
struct TaskQueueSnapshot: Codable, Equatable {
  static let currentSchemaVersion = 1

  let schemaVersion: Int
  var tasks: [QueuedTask]
  let savedAt: Date

  init(tasks: [QueuedTask], savedAt: Date = Date()) {
    self.schemaVersion = Self.currentSchemaVersion
    self.tasks = tasks
    self.savedAt = savedAt
  }
}
