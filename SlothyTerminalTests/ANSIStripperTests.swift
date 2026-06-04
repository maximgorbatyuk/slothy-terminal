import Testing

@testable import SlothyTerminalLib

@Suite("ANSI Stripper")
struct ANSIStripperTests {
  @Test("Plain text without escape sequences is returned unchanged")
  func plainTextUnchanged() {
    let text = "total 24\ndrwxr-xr-x  3 user  staff  96 Jan  1 file.txt"

    #expect(ANSIStripper.strip(text) == text)
  }

  @Test("Empty string is returned unchanged")
  func emptyStringUnchanged() {
    #expect(ANSIStripper.strip("") == "")
  }

  @Test("CSI color sequences are removed")
  func csiColorSequencesRemoved() {
    let text = "\u{1B}[31mred\u{1B}[0m normal \u{1B}[1;32mbold green\u{1B}[0m"

    #expect(ANSIStripper.strip(text) == "red normal bold green")
  }

  @Test("OSC sequences are removed")
  func oscSequencesRemoved() {
    /// OSC 0 (set window title) terminated by BEL.
    let text = "\u{1B}]0;my title\u{07}prompt$ "

    #expect(ANSIStripper.strip(text) == "prompt$ ")
  }

  @Test("Cursor movement sequences are removed but surrounding text is kept")
  func cursorMovementRemoved() {
    let text = "line one\u{1B}[2Kline two"

    #expect(ANSIStripper.strip(text) == "line oneline two")
  }

  @Test("Text containing only escape sequences strips to empty")
  func onlyEscapesStripsToEmpty() {
    let text = "\u{1B}[0m\u{1B}[2J"

    #expect(ANSIStripper.strip(text) == "")
  }
}
