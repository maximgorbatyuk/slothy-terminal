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

  // MARK: - Snapshot serialization

  /// Creates a persistable snapshot of this conversation.
  func toSnapshot(sessionId: String) -> ChatSessionSnapshot {
    ChatSessionSnapshot(
      sessionId: sessionId,
      workingDirectory: workingDirectory.path,
      messages: messages.map { SerializedMessage.from($0) },
      totalInputTokens: totalInputTokens,
      totalOutputTokens: totalOutputTokens,
      savedAt: Date()
    )
  }

  /// Restores conversation state from a persisted snapshot.
  func restore(from snapshot: ChatSessionSnapshot) {
    messages = snapshot.messages.map { $0.toMessage() }
    totalInputTokens = snapshot.totalInputTokens
    totalOutputTokens = snapshot.totalOutputTokens
  }
}
