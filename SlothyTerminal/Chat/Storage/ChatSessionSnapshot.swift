import Foundation

/// Codable representation of a `ChatContentBlock` for persistence.
enum SerializedContentBlock: Codable, Equatable {
  case text(String)
  case thinking(String)
  case toolUse(id: String, name: String, input: String)
  case toolResult(toolUseId: String, content: String)

  /// Converts back to a runtime `ChatContentBlock`.
  func toContentBlock() -> ChatContentBlock {
    switch self {
    case .text(let text):
      return .text(text)

    case .thinking(let text):
      return .thinking(text)

    case .toolUse(let id, let name, let input):
      return .toolUse(id: id, name: name, input: input)

    case .toolResult(let toolUseId, let content):
      return .toolResult(toolUseId: toolUseId, content: content)
    }
  }

  /// Creates a serialized block from a runtime `ChatContentBlock`.
  static func from(_ block: ChatContentBlock) -> SerializedContentBlock {
    switch block {
    case .text(let text):
      return .text(text)

    case .thinking(let text):
      return .thinking(text)

    case .toolUse(let id, let name, let input):
      return .toolUse(id: id, name: name, input: input)

    case .toolResult(let toolUseId, let content):
      return .toolResult(toolUseId: toolUseId, content: content)
    }
  }
}

/// Codable representation of a `ChatMessage` for persistence.
struct SerializedMessage: Codable, Equatable {
  let id: UUID
  let role: String
  let contentBlocks: [SerializedContentBlock]
  let timestamp: Date
  let inputTokens: Int
  let outputTokens: Int

  /// Converts back to a runtime `ChatMessage`.
  func toMessage() -> ChatMessage {
    ChatMessage(
      id: id,
      role: role == "user" ? .user : .assistant,
      contentBlocks: contentBlocks.map { $0.toContentBlock() },
      timestamp: timestamp,
      isStreaming: false,
      inputTokens: inputTokens,
      outputTokens: outputTokens
    )
  }

  /// Creates a serialized message from a runtime `ChatMessage`.
  static func from(_ message: ChatMessage) -> SerializedMessage {
    SerializedMessage(
      id: message.id,
      role: message.role.rawValue,
      contentBlocks: message.contentBlocks.map { SerializedContentBlock.from($0) },
      timestamp: message.timestamp,
      inputTokens: message.inputTokens,
      outputTokens: message.outputTokens
    )
  }
}

/// A full snapshot of a chat session for persistence.
struct ChatSessionSnapshot: Codable, Equatable {
  let sessionId: String
  let workingDirectory: String
  let messages: [SerializedMessage]
  let totalInputTokens: Int
  let totalOutputTokens: Int
  let savedAt: Date
}

/// A single entry in the session index.
struct SessionIndexEntry: Codable, Equatable {
  let sessionId: String
  let savedAt: Date
}

/// Index mapping working directory paths to their most recent session.
struct ChatSessionIndex: Codable, Equatable {
  var entries: [String: SessionIndexEntry] = [:]
}
