import Foundation

/// A reusable prompt (role instructions) that can be attached when opening a new AI agent tab.
struct SavedPrompt: Codable, Identifiable, Equatable {
  var id: UUID
  var name: String
  var promptDescription: String
  var promptText: String
  var createdAt: Date
  var updatedAt: Date

  init(
    id: UUID = UUID(),
    name: String,
    promptDescription: String = "",
    promptText: String,
    createdAt: Date = Date(),
    updatedAt: Date = Date()
  ) {
    self.id = id
    self.name = name
    self.promptDescription = promptDescription
    self.promptText = promptText
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}

// MARK: - Collection Lookup

extension [SavedPrompt] {
  /// Finds a saved prompt by ID, returning nil when the ID is nil or not found.
  func find(by id: UUID?) -> SavedPrompt? {
    guard let id else {
      return nil
    }

    return first { $0.id == id }
  }
}
