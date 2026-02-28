import XCTest
@testable import SlothyTerminalLib

final class TelegramMessageChunkerTests: XCTestCase {

  func testShortMessageNotChunked() {
    let text = "Hello, world!"
    let chunks = TelegramMessageChunker.chunk(text)

    XCTAssertEqual(chunks.count, 1)
    XCTAssertEqual(chunks[0], text)
  }

  func testExactLimitNotChunked() {
    let text = String(repeating: "a", count: TelegramMessageChunker.maxLength)
    let chunks = TelegramMessageChunker.chunk(text)

    XCTAssertEqual(chunks.count, 1)
  }

  func testLongMessageChunked() {
    let text = String(repeating: "a", count: TelegramMessageChunker.maxLength + 100)
    let chunks = TelegramMessageChunker.chunk(text)

    XCTAssertGreaterThan(chunks.count, 1)

    /// All content should be preserved.
    let rejoined = chunks.joined()
    XCTAssertEqual(rejoined.count, text.count)
  }

  func testChunksPreferNewlineBreaks() {
    /// Build a message that's over the limit with newlines.
    let line = String(repeating: "x", count: 100)
    var lines: [String] = []
    while lines.joined(separator: "\n").count < TelegramMessageChunker.maxLength + 500 {
      lines.append(line)
    }
    let text = lines.joined(separator: "\n")
    let chunks = TelegramMessageChunker.chunk(text)

    XCTAssertGreaterThan(chunks.count, 1)

    /// First chunk should not exceed the limit.
    XCTAssertLessThanOrEqual(chunks[0].count, TelegramMessageChunker.maxLength)
  }

  func testEmptyMessage() {
    let chunks = TelegramMessageChunker.chunk("")

    XCTAssertEqual(chunks.count, 1)
    XCTAssertEqual(chunks[0], "")
  }

  func testChunkingPreservesNewlines() {
    let text = String(repeating: "a", count: TelegramMessageChunker.maxLength - 1)
      + "\n"
      + "tail"

    let chunks = TelegramMessageChunker.chunk(text)

    XCTAssertGreaterThan(chunks.count, 1)
    XCTAssertEqual(chunks.joined(), text)
  }
}
