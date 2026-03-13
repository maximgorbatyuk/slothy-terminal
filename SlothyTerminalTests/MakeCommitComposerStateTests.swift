import Testing

@testable import SlothyTerminalLib

@Suite("Make Commit Composer")
struct MakeCommitComposerStateTests {
  @Test("Commit message normalization keeps only the first line")
  func normalizesMessageToSingleLine() {
    #expect(
      MakeCommitComposerState.normalizedCommitMessage(
        "Fix flaky test\n\nDetailed explanation"
      ) == "Fix flaky test"
    )
  }

  @Test("Commit message normalization trims a single-line message")
  func trimsSingleLineMessage() {
    #expect(
      MakeCommitComposerState.normalizedCommitMessage("  Tighten git tab layout  ")
        == "Tighten git tab layout"
    )
  }

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
