import Testing

@testable import SlothyTerminalLib

@Suite("Terminal Command Capture Buffer")
struct TerminalCommandCaptureBufferTests {
  @Test("Inserted newline submits the current command")
  func insertedNewlineSubmitsTheCurrentCommand() {
    var buffer = TerminalCommandCaptureBuffer()

    let submitted = buffer.append("npm run dev\n")

    #expect(submitted == ["npm run dev"])
    #expect(buffer.submit() == nil)
  }

  @Test("Pasted multiline text does not submit automatically")
  func pastedMultilineTextDoesNotSubmitAutomatically() {
    var buffer = TerminalCommandCaptureBuffer()

    let submitted = buffer.append("npm run dev\npnpm test", submitOnNewline: false)

    #expect(submitted.isEmpty)
    #expect(buffer.submit() == "npm run dev\npnpm test")
  }

  @Test("Delete backward removes the last captured character")
  func deleteBackwardRemovesTheLastCapturedCharacter() {
    var buffer = TerminalCommandCaptureBuffer()

    _ = buffer.append("npmx")
    buffer.deleteBackward()

    #expect(buffer.submit() == "npm")
  }

  @Test("Clearing the buffer removes aborted input")
  func clearingTheBufferRemovesAbortedInput() {
    var buffer = TerminalCommandCaptureBuffer()

    _ = buffer.append("npm run dev")
    buffer.clear()

    #expect(buffer.submit() == nil)
  }

  @Test("Delete last word removes only the trailing word")
  func deleteLastWordRemovesOnlyTheTrailingWord() {
    var buffer = TerminalCommandCaptureBuffer()

    _ = buffer.append("npm run")
    buffer.deleteLastWord()

    #expect(buffer.submit() == "npm")
  }
}
