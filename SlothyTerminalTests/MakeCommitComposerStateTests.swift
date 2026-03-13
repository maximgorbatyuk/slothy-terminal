import Testing

@testable import SlothyTerminalLib

@Suite("Make Commit Composer")
struct MakeCommitComposerStateTests {
  @Test("Loaded amend message is ignored when amend mode is no longer active")
  func ignoresLoadedMessageAfterAmendDisabled() {
    #expect(
      MakeCommitComposerState.shouldApplyLoadedAmendMessage(
        requestID: "req-1",
        activeRequestID: nil,
        isAmending: false,
        initialMessage: "",
        currentMessage: ""
      ) == false
    )
  }

  @Test("Loaded amend message is ignored after the user edits the composer")
  func ignoresLoadedMessageAfterUserEdit() {
    #expect(
      MakeCommitComposerState.shouldApplyLoadedAmendMessage(
        requestID: "req-1",
        activeRequestID: "req-1",
        isAmending: true,
        initialMessage: "",
        currentMessage: "typed before request finished"
      ) == false
    )
  }

  @Test("Loaded amend message applies only to the current active request")
  func appliesLoadedMessageOnlyToCurrentRequest() {
    #expect(
      MakeCommitComposerState.shouldApplyLoadedAmendMessage(
        requestID: "req-1",
        activeRequestID: "req-1",
        isAmending: true,
        initialMessage: "",
        currentMessage: ""
      ) == true
    )
    #expect(
      MakeCommitComposerState.shouldApplyLoadedAmendMessage(
        requestID: "req-1",
        activeRequestID: "req-2",
        isAmending: true,
        initialMessage: "",
        currentMessage: ""
      ) == false
    )
  }
}
