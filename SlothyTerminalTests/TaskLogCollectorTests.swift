import XCTest
@testable import SlothyTerminalLib

final class TaskLogCollectorTests: XCTestCase {

  // MARK: - Append and Flush

  func testAppendAndFlush() {
    let collector = TaskLogCollector(taskId: UUID(), attemptId: UUID())
    collector.append("Line 1")
    collector.append("Line 2")

    let path = collector.flush()

    XCTAssertNotNil(path)

    /// Verify file contents.
    if let path {
      let content = try? String(contentsOfFile: path, encoding: .utf8)
      XCTAssertNotNil(content)
      XCTAssertTrue(content?.contains("Line 1") == true)
      XCTAssertTrue(content?.contains("Line 2") == true)

      /// Clean up.
      try? FileManager.default.removeItem(atPath: path)
    }
  }

  // MARK: - Truncation

  func testTruncationAt5MB() {
    let collector = TaskLogCollector(taskId: UUID(), attemptId: UUID())

    /// Each line ~100 bytes, need ~50K lines to exceed 5MB.
    let longLine = String(repeating: "x", count: 90)
    for _ in 0..<60_000 {
      collector.append(longLine)
    }

    let path = collector.flush()
    XCTAssertNotNil(path)

    if let path {
      let data = FileManager.default.contents(atPath: path)
      XCTAssertNotNil(data)

      /// Content should include the truncation marker.
      let content = String(data: data ?? Data(), encoding: .utf8)
      XCTAssertTrue(content?.contains("LOG TRUNCATED") == true)

      /// File size should not vastly exceed 5MB.
      let size = data?.count ?? 0
      XCTAssertLessThan(size, 6 * 1024 * 1024)

      try? FileManager.default.removeItem(atPath: path)
    }
  }

  // MARK: - Empty Flush

  func testEmptyFlushReturnsNil() {
    let collector = TaskLogCollector(taskId: UUID(), attemptId: UUID())
    let path = collector.flush()
    XCTAssertNil(path)
  }

  // MARK: - Callback

  func testOnLogLineCallback() {
    let collector = TaskLogCollector(taskId: UUID(), attemptId: UUID())
    var received: [String] = []
    collector.onLogLine = { line in
      received.append(line)
    }

    collector.append("Hello")
    collector.append("World")

    XCTAssertEqual(received.count, 2)
    XCTAssertTrue(received[0].contains("Hello"))
    XCTAssertTrue(received[1].contains("World"))
  }
}
