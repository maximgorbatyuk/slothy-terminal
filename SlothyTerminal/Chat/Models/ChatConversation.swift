import Foundation

/// Represents a multi-turn chat conversation with Claude.
@Observable
class ChatConversation {
  var messages: [ChatMessage] = []
  let workingDirectory: URL
  var totalInputTokens: Int = 0
  var totalOutputTokens: Int = 0

  init(workingDirectory: URL) {
    self.workingDirectory = workingDirectory
  }

  /// Whether the conversation has prior messages, indicating `--continue` should be used.
  var hasHistory: Bool {
    messages.contains { $0.role == .assistant }
  }

  /// Adds a new message to the conversation.
  func addMessage(_ message: ChatMessage) {
    messages.append(message)
  }

  /// Removes the last message if it matches the given message.
  func removeMessage(_ message: ChatMessage) {
    messages.removeAll { $0.id == message.id }
  }

  /// Clears all messages and resets token counts.
  func clear() {
    messages.removeAll()
    totalInputTokens = 0
    totalOutputTokens = 0
  }
}
