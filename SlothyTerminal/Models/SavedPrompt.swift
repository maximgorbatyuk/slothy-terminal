import Foundation

/// A reusable prompt tag that can be assigned across multiple prompts.
struct PromptTag: Codable, Identifiable, Equatable, Hashable {
  var id: UUID
  var name: String

  init(
    id: UUID = UUID(),
    name: String
  ) {
    self.id = id
    self.name = name
  }
}

/// A reusable prompt (role instructions) that can be attached when opening a new AI agent tab.
struct SavedPrompt: Codable, Identifiable, Equatable {
  var id: UUID
  var name: String
  var promptDescription: String
  var promptText: String
  var tagIDs: [UUID]
  var createdAt: Date
  var updatedAt: Date

  enum CodingKeys: String, CodingKey {
    case id
    case name
    case promptDescription
    case promptText
    case tagIDs
    case createdAt
    case updatedAt
  }

  init(
    id: UUID = UUID(),
    name: String,
    promptDescription: String = "",
    promptText: String,
    tagIDs: [UUID] = [],
    createdAt: Date = Date(),
    updatedAt: Date = Date()
  ) {
    self.id = id
    self.name = name
    self.promptDescription = promptDescription
    self.promptText = promptText
    self.tagIDs = tagIDs
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    name = try container.decode(String.self, forKey: .name)
    promptDescription = try container.decodeIfPresent(String.self, forKey: .promptDescription) ?? ""
    promptText = try container.decode(String.self, forKey: .promptText)
    tagIDs = try container.decodeIfPresent([UUID].self, forKey: .tagIDs) ?? []
    createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
  }

  /// Returns a one-line preview of prompt text for menus and tables.
  func previewText(maxLength: Int = 50) -> String {
    guard maxLength > 0 else {
      return ""
    }

    let normalized = promptText
      .split(whereSeparator: \.isWhitespace)
      .joined(separator: " ")

    guard normalized.count > maxLength else {
      return normalized
    }

    return "\(normalized.prefix(maxLength))…"
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

extension [PromptTag] {
  /// Finds a prompt tag by ID, returning nil when not found.
  func find(by id: UUID) -> PromptTag? {
    first { $0.id == id }
  }
}
