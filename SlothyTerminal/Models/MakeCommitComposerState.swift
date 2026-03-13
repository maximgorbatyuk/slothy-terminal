import Foundation

enum MakeCommitComposerState {
  static func singleLineMessageInput(_ message: String) -> String {
    String(message.prefix { !$0.isNewline })
  }

  static func normalizedCommitMessage(_ message: String) -> String {
    singleLineMessageInput(message).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func shouldApplyLoadedAmendMessage(
    requestID: String,
    activeRequestID: String?,
    isAmending: Bool,
    initialMessage: String,
    currentMessage: String
  ) -> Bool {
    guard isAmending, requestID == activeRequestID else {
      return false
    }

    return currentMessage == initialMessage
  }
}
