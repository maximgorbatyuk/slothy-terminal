import Foundation
import Testing

@testable import SlothyTerminalLib

@Suite("SSEParser")
struct SSEParserTests {

  // MARK: - Basic parsing

  @Test("Parses a simple data-only event")
  func simpleDataEvent() {
    let parser = SSEParser()
    let events = parser.feed("data: hello world\n\n")

    #expect(events.count == 1)
    #expect(events[0].event == nil)
    #expect(events[0].data == "hello world")
  }

  @Test("Parses event with event field")
  func eventField() {
    let parser = SSEParser()
    let events = parser.feed("event: message_start\ndata: {\"type\":\"message_start\"}\n\n")

    #expect(events.count == 1)
    #expect(events[0].event == "message_start")
    #expect(events[0].data.contains("message_start"))
  }

  @Test("Parses multi-line data fields joined by newlines")
  func multiLineData() {
    let parser = SSEParser()
    let events = parser.feed("data: line1\ndata: line2\ndata: line3\n\n")

    #expect(events.count == 1)
    #expect(events[0].data == "line1\nline2\nline3")
  }

  @Test("Parses multiple events in a single chunk")
  func multipleEvents() {
    let parser = SSEParser()
    let chunk = """
      event: first
      data: {"a":1}

      event: second
      data: {"b":2}


      """
    let events = parser.feed(chunk)

    #expect(events.count == 2)
    #expect(events[0].event == "first")
    #expect(events[1].event == "second")
  }

  // MARK: - Partial chunks

  @Test("Buffers partial data across multiple feed calls")
  func partialChunks() {
    let parser = SSEParser()

    let events1 = parser.feed("data: hel")
    #expect(events1.isEmpty)

    let events2 = parser.feed("lo\n")
    #expect(events2.isEmpty)

    let events3 = parser.feed("\n")
    #expect(events3.count == 1)
    #expect(events3[0].data == "hello")
  }

  @Test("Handles event split across chunks")
  func eventSplitAcrossChunks() {
    let parser = SSEParser()

    let e1 = parser.feed("event: content_block_delta\n")
    #expect(e1.isEmpty)

    let e2 = parser.feed("data: {\"delta\":\"text\"}\n")
    #expect(e2.isEmpty)

    let e3 = parser.feed("\n")
    #expect(e3.count == 1)
    #expect(e3[0].event == "content_block_delta")
  }

  // MARK: - Edge cases

  @Test("Skips comment lines")
  func commentLines() {
    let parser = SSEParser()
    let events = parser.feed(": this is a comment\ndata: actual\n\n")

    #expect(events.count == 1)
    #expect(events[0].data == "actual")
  }

  @Test("Skips id and retry fields")
  func idAndRetryFields() {
    let parser = SSEParser()
    let events = parser.feed("id: 123\nretry: 5000\ndata: payload\n\n")

    #expect(events.count == 1)
    #expect(events[0].data == "payload")
  }

  @Test("Empty data lines produce empty event only with delimiter")
  func emptyData() {
    let parser = SSEParser()

    /// Two consecutive empty lines — no data fields means no event.
    let events = parser.feed("\n\n")
    #expect(events.isEmpty)
  }

  @Test("Data with no space after colon")
  func noSpaceAfterColon() {
    let parser = SSEParser()
    let events = parser.feed("data:nospace\n\n")

    #expect(events.count == 1)
    #expect(events[0].data == "nospace")
  }

  @Test("Reset clears buffered state")
  func reset() {
    let parser = SSEParser()
    _ = parser.feed("data: partial")
    parser.reset()

    let events = parser.feed("data: fresh\n\n")
    #expect(events.count == 1)
    #expect(events[0].data == "fresh")
  }

  // MARK: - Anthropic-style stream

  @Test("Parses Anthropic-style SSE sequence")
  func anthropicStream() {
    let parser = SSEParser()
    let stream = """
      event: message_start
      data: {"type":"message_start","message":{"usage":{"input_tokens":100}}}

      event: content_block_start
      data: {"type":"content_block_start","index":0,"content_block":{"type":"text"}}

      event: content_block_delta
      data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}

      event: content_block_stop
      data: {"type":"content_block_stop","index":0}

      event: message_delta
      data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":50}}

      event: message_stop
      data: {"type":"message_stop"}


      """
    let events = parser.feed(stream)

    #expect(events.count == 6)
    #expect(events[0].event == "message_start")
    #expect(events[1].event == "content_block_start")
    #expect(events[2].event == "content_block_delta")
    #expect(events[3].event == "content_block_stop")
    #expect(events[4].event == "message_delta")
    #expect(events[5].event == "message_stop")
  }
}
