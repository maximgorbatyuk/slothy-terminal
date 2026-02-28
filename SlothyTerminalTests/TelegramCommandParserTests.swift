import XCTest
@testable import SlothyTerminalLib

final class TelegramCommandParserTests: XCTestCase {

  // MARK: - Recognized Commands

  func testParseHelp() {
    XCTAssertEqual(TelegramCommandParser.parse("/help"), .help)
  }

  func testParseStart() {
    XCTAssertEqual(TelegramCommandParser.parse("/start"), .help)
  }

  func testParseReport() {
    XCTAssertEqual(TelegramCommandParser.parse("/report"), .report)
  }

  func testParseOpenDirectoryHyphen() {
    XCTAssertEqual(TelegramCommandParser.parse("/open-directory"), .openDirectory)
  }

  func testParseOpenDirectoryUnderscore() {
    XCTAssertEqual(TelegramCommandParser.parse("/open_directory"), .openDirectory)
  }

  func testParseNewTaskHyphen() {
    XCTAssertEqual(TelegramCommandParser.parse("/new-task"), .newTask)
  }

  func testParseNewTaskUnderscore() {
    XCTAssertEqual(TelegramCommandParser.parse("/new_task"), .newTask)
  }

  // MARK: - Unknown Commands

  func testParseUnknownCommand() {
    XCTAssertEqual(TelegramCommandParser.parse("/foobar"), .unknown("/foobar"))
  }

  // MARK: - Non-Commands

  func testParseNonCommandReturnsNil() {
    XCTAssertNil(TelegramCommandParser.parse("hello world"))
  }

  func testParseEmptyStringReturnsNil() {
    XCTAssertNil(TelegramCommandParser.parse(""))
  }

  func testParseWhitespaceReturnsNil() {
    XCTAssertNil(TelegramCommandParser.parse("   "))
  }

  // MARK: - Case Insensitivity

  func testParseCaseInsensitive() {
    XCTAssertEqual(TelegramCommandParser.parse("/HELP"), .help)
    XCTAssertEqual(TelegramCommandParser.parse("/Report"), .report)
  }

  // MARK: - Bot Username Suffix

  func testParseBotSuffix() {
    XCTAssertEqual(TelegramCommandParser.parse("/help@MyBot"), .help)
    XCTAssertEqual(TelegramCommandParser.parse("/report@SomeBot"), .report)
  }

  // MARK: - Trailing Text

  func testParseCommandWithTrailingText() {
    XCTAssertEqual(TelegramCommandParser.parse("/help extra args"), .help)
  }

  // MARK: - Leading Whitespace

  func testParseLeadingWhitespace() {
    XCTAssertEqual(TelegramCommandParser.parse("  /help"), .help)
  }
}
