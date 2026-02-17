import XCTest
@testable import SlothyTerminalLib

final class RiskyToolDetectorTests: XCTestCase {

  // MARK: - Bash Risky

  func testBashGitPush() {
    let results = RiskyToolDetector.check(
      toolName: "Bash",
      input: "{\"command\":\"git push origin main\"}"
    )

    XCTAssertFalse(results.isEmpty)
    XCTAssertTrue(results.contains { $0.reason.contains("git push") })
  }

  func testBashRmRf() {
    let results = RiskyToolDetector.check(
      toolName: "bash",
      input: "{\"command\":\"rm -rf /tmp/build\"}"
    )

    XCTAssertFalse(results.isEmpty)
    XCTAssertTrue(results.contains { $0.reason.contains("rm -rf") })
  }

  // MARK: - Bash Safe

  func testBashSafeCommand() {
    let results = RiskyToolDetector.check(
      toolName: "Bash",
      input: "{\"command\":\"ls -la\"}"
    )

    XCTAssertTrue(results.isEmpty)
  }

  // MARK: - Bash Multiple Detections

  func testBashMultipleRiskyPatterns() {
    let results = RiskyToolDetector.check(
      toolName: "Bash",
      input: "{\"command\":\"git commit -m 'msg' && git push origin main\"}"
    )

    XCTAssertEqual(results.count, 2)
    XCTAssertTrue(results.contains { $0.reason.contains("git commit") })
    XCTAssertTrue(results.contains { $0.reason.contains("git push") })
  }

  // MARK: - Write Risky

  func testWriteSensitivePath() {
    let results = RiskyToolDetector.check(
      toolName: "Write",
      input: "{\"file_path\":\"/project/.env\",\"content\":\"SECRET=abc\"}"
    )

    XCTAssertFalse(results.isEmpty)
    XCTAssertTrue(results.contains { $0.reason.contains(".env") })
  }

  // MARK: - Write Safe — no false positives

  func testWriteSafePath() {
    let results = RiskyToolDetector.check(
      toolName: "Write",
      input: "{\"file_path\":\"/project/src/main.swift\",\"content\":\"print('hi')\"}"
    )

    XCTAssertTrue(results.isEmpty)
  }

  func testWriteEnvironmentFileSafe() {
    let results = RiskyToolDetector.check(
      toolName: "Write",
      input: "{\"file_path\":\"/project/src/setup.environment.swift\"}"
    )

    XCTAssertTrue(results.isEmpty)
  }

  func testWriteCredentialsHelperSafe() {
    let results = RiskyToolDetector.check(
      toolName: "Write",
      input: "{\"file_path\":\"/project/tests/TestCredentialsFactory.swift\"}"
    )

    XCTAssertTrue(results.isEmpty)
  }

  // MARK: - Unknown Tool

  func testUnknownToolReturnsEmpty() {
    let results = RiskyToolDetector.check(
      toolName: "Read",
      input: "{\"file_path\":\"/project/.env\"}"
    )

    XCTAssertTrue(results.isEmpty)
  }
}
