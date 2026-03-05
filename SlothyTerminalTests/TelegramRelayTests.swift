import XCTest
@testable import SlothyTerminalLib

final class TelegramRelayTests: XCTestCase {

  // MARK: - Command Parsing

  func testParseRelayStartUnderscore() {
    XCTAssertEqual(TelegramCommandParser.parse("/relay_start"), .relayStart)
  }

  func testParseRelayStartHyphen() {
    XCTAssertEqual(TelegramCommandParser.parse("/relay-start"), .relayStart)
  }

  func testParseRelayStopUnderscore() {
    XCTAssertEqual(TelegramCommandParser.parse("/relay_stop"), .relayStop)
  }

  func testParseRelayStopHyphen() {
    XCTAssertEqual(TelegramCommandParser.parse("/relay-stop"), .relayStop)
  }

  func testParseRelayStatusUnderscore() {
    XCTAssertEqual(TelegramCommandParser.parse("/relay_status"), .relayStatus)
  }

  func testParseRelayStatusHyphen() {
    XCTAssertEqual(TelegramCommandParser.parse("/relay-status"), .relayStatus)
  }

  func testParseRelayTabsUnderscore() {
    XCTAssertEqual(TelegramCommandParser.parse("/relay_tabs"), .relayTabs)
  }

  func testParseRelayTabsHyphen() {
    XCTAssertEqual(TelegramCommandParser.parse("/relay-tabs"), .relayTabs)
  }

  func testParseRelayInterruptUnderscore() {
    XCTAssertEqual(TelegramCommandParser.parse("/relay_interrupt"), .relayInterrupt)
  }

  func testParseRelayInterruptHyphen() {
    XCTAssertEqual(TelegramCommandParser.parse("/relay-interrupt"), .relayInterrupt)
  }

  func testParseRelayCommandsCaseInsensitive() {
    XCTAssertEqual(TelegramCommandParser.parse("/RELAY_START"), .relayStart)
    XCTAssertEqual(TelegramCommandParser.parse("/Relay_Stop"), .relayStop)
  }

  func testParseRelayCommandsWithBotSuffix() {
    XCTAssertEqual(TelegramCommandParser.parse("/relay_start@MyBot"), .relayStart)
    XCTAssertEqual(TelegramCommandParser.parse("/relay_tabs@SomeBot"), .relayTabs)
  }

  // MARK: - Relay Session Model

  func testRelaySessionCreation() {
    let tabId = UUID()
    let session = TelegramRelaySession(
      tabId: tabId,
      tabName: "Terminal 1",
      startedAt: Date(),
      status: .active
    )

    XCTAssertEqual(session.tabId, tabId)
    XCTAssertEqual(session.tabName, "Terminal 1")
    XCTAssertNil(session.lastOutputTimestamp)
  }

  // MARK: - TelegramRelayTabInfo

  func testRelayTabInfoConstruction() {
    let id = UUID()
    let dir = URL(fileURLWithPath: "/tmp")
    let info = TelegramRelayTabInfo(
      id: id,
      name: "Claude",
      agentType: .claude,
      directory: dir,
      isActive: true
    )

    XCTAssertEqual(info.id, id)
    XCTAssertEqual(info.name, "Claude")
    XCTAssertEqual(info.agentType, .claude)
    XCTAssertTrue(info.isActive)
  }

  func testRelayTabInfoEquatable() {
    let id = UUID()
    let a = TelegramRelayTabInfo(
      id: id,
      name: "Tab A",
      agentType: .claude,
      directory: URL(fileURLWithPath: "/a"),
      isActive: false
    )
    let b = TelegramRelayTabInfo(
      id: id,
      name: "Tab B",
      agentType: .opencode,
      directory: URL(fileURLWithPath: "/b"),
      isActive: true
    )

    XCTAssertEqual(a, b, "Equatable should compare by ID only")
  }

  // MARK: - ANSI Stripping

  func testStripPlainText() {
    XCTAssertEqual(ANSIStripper.strip("hello world"), "hello world")
  }

  func testStripColorCodes() {
    let input = "\u{1B}[32mhello\u{1B}[0m world"
    XCTAssertEqual(ANSIStripper.strip(input), "hello world")
  }

  func testStripBoldAndUnderline() {
    let input = "\u{1B}[1mbold\u{1B}[0m \u{1B}[4munderline\u{1B}[0m"
    XCTAssertEqual(ANSIStripper.strip(input), "bold underline")
  }

  func testStripOSCSequences() {
    let input = "\u{1B}]0;title\u{07}content"
    XCTAssertEqual(ANSIStripper.strip(input), "content")
  }

  func testStripCursorVisibility() {
    let input = "\u{1B}[?25hvisible\u{1B}[?25l"
    XCTAssertEqual(ANSIStripper.strip(input), "visible")
  }

  func testStripOSCWithST() {
    let input = "\u{1B}]0;title\u{1B}\\content"
    XCTAssertEqual(ANSIStripper.strip(input), "content")
  }

  func testStripCharsetSelection() {
    let input = "\u{1B}(Btext"
    XCTAssertEqual(ANSIStripper.strip(input), "text")
  }

  func testStripEmptyString() {
    XCTAssertEqual(ANSIStripper.strip(""), "")
  }

  // MARK: - Output Diffing

  func testDiffNewLinesAppended() {
    let previous = ["line1", "line2"]
    let current = ["line1", "line2", "line3", "line4"]
    let result = ViewportDiffer.diffLines(previous: previous, current: current)
    XCTAssertEqual(result, "line3\nline4")
  }

  func testDiffIdenticalViewport() {
    let lines = ["line1", "line2", "line3"]
    let result = ViewportDiffer.diffLines(previous: lines, current: lines)
    XCTAssertEqual(result, "")
  }

  func testDiffCompletelyDifferent() {
    let previous = ["old1", "old2"]
    let current = ["new1", "new2", "new3"]
    let result = ViewportDiffer.diffLines(previous: previous, current: current)
    XCTAssertEqual(result, "new1\nnew2\nnew3")
  }

  func testDiffEmptyPrevious() {
    let current = ["line1", "line2"]
    let result = ViewportDiffer.diffLines(previous: [], current: current)
    XCTAssertEqual(result, "line1\nline2")
  }

  func testDiffEmptyCurrent() {
    let previous = ["line1", "line2"]
    let result = ViewportDiffer.diffLines(previous: previous, current: [])
    XCTAssertEqual(result, "")
  }

  func testDiffMiddleLineChanged() {
    let previous = ["line1", "line2", "line3"]
    let current = ["line1", "changed", "line3"]
    let result = ViewportDiffer.diffLines(previous: previous, current: current)
    XCTAssertEqual(result, "changed\nline3")
  }

  // MARK: - Interaction State

  func testAwaitingRelayTabChoiceEquatable() {
    let tabs = [
      TelegramRelayTabInfo(
        id: UUID(),
        name: "Tab",
        agentType: .claude,
        directory: URL(fileURLWithPath: "/tmp"),
        isActive: false
      )
    ]
    let state = TelegramInteractionState.awaitingRelayTabChoice(tabs: tabs)
    XCTAssertEqual(state, state)
  }

  // MARK: - Existing Commands Still Work

  func testExistingCommandsNotBroken() {
    XCTAssertEqual(TelegramCommandParser.parse("/help"), .help)
    XCTAssertEqual(TelegramCommandParser.parse("/report"), .report)
    XCTAssertEqual(TelegramCommandParser.parse("/new_task"), .newTask)
    XCTAssertEqual(TelegramCommandParser.parse("/open_directory"), .openDirectory)
  }
}
