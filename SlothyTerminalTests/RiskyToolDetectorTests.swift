import XCTest
@testable import SlothyTerminalLib

final class RiskyToolDetectorTests: XCTestCase {

  // MARK: - Bash Risky

  func testBashGitPush() {
    let result = RiskyToolDetector.check(
      toolName: "Bash",
      input: "{\"command\":\"git push origin main\"}"
    )

    XCTAssertNotNil(result)
    XCTAssertTrue(result?.reason.contains("git push") == true)
  }

  func testBashRmRf() {
    let result = RiskyToolDetector.check(
      toolName: "bash",
      input: "{\"command\":\"rm -rf /tmp/build\"}"
    )

    XCTAssertNotNil(result)
    XCTAssertTrue(result?.reason.contains("rm -rf") == true)
  }

  // MARK: - Bash Safe

  func testBashSafeCommand() {
    let result = RiskyToolDetector.check(
      toolName: "Bash",
      input: "{\"command\":\"ls -la\"}"
    )

    XCTAssertNil(result)
  }

  // MARK: - Write Risky

  func testWriteSensitivePath() {
    let result = RiskyToolDetector.check(
      toolName: "Write",
      input: "{\"file_path\":\"/project/.env\",\"content\":\"SECRET=abc\"}"
    )

    XCTAssertNotNil(result)
    XCTAssertTrue(result?.reason.contains(".env") == true)
  }

  // MARK: - Write Safe

  func testWriteSafePath() {
    let result = RiskyToolDetector.check(
      toolName: "Write",
      input: "{\"file_path\":\"/project/src/main.swift\",\"content\":\"print('hi')\"}"
    )

    XCTAssertNil(result)
  }

  // MARK: - Unknown Tool

  func testUnknownToolReturnsNil() {
    let result = RiskyToolDetector.check(
      toolName: "Read",
      input: "{\"file_path\":\"/project/.env\"}"
    )

    XCTAssertNil(result)
  }
}
