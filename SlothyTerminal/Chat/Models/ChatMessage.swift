import Foundation

/// The role of a chat message sender.
enum ChatRole: String {
  case user
  case assistant
}

/// A single content block within a chat message.
enum ChatContentBlock: Identifiable {
  case text(String)
  case thinking(String)
  case toolUse(id: String, name: String, input: String)
  case toolResult(toolUseId: String, content: String)

  var id: String {
    switch self {
    case .text(let text):
      return "text-\(text.hashValue)"

    case .thinking(let text):
      return "thinking-\(text.hashValue)"

    case .toolUse(let id, _, _):
      return "tool-use-\(id)"

    case .toolResult(let toolUseId, _):
      return "tool-result-\(toolUseId)"
    }
  }
}

/// A single message in a chat conversation.
@Observable
class ChatMessage: Identifiable {
  let id: UUID
  let role: ChatRole
  var contentBlocks: [ChatContentBlock]
  let timestamp: Date
  var isStreaming: Bool
  var inputTokens: Int
  var outputTokens: Int

  init(
    id: UUID = UUID(),
    role: ChatRole,
    contentBlocks: [ChatContentBlock] = [],
    timestamp: Date = Date(),
    isStreaming: Bool = false,
    inputTokens: Int = 0,
    outputTokens: Int = 0
  ) {
    self.id = id
    self.role = role
    self.contentBlocks = contentBlocks
    self.timestamp = timestamp
    self.isStreaming = isStreaming
    self.inputTokens = inputTokens
    self.outputTokens = outputTokens
  }

  /// Combined text content from all text blocks.
  var textContent: String {
    contentBlocks.compactMap { block in
      if case .text(let text) = block {
        return text
      }
      return nil
    }.joined()
  }

}
