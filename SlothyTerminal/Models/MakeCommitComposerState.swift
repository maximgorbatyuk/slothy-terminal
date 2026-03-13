import Foundation

enum MakeCommitComposerState {
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
