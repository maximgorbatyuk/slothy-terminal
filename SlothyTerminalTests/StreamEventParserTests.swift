import XCTest
@testable import SlothyTerminalLib

final class StreamEventParserTests: XCTestCase {

  // MARK: - System Event

  func testParseSystemEvent() {
    let line = """
    {"type":"system","session_id":"abc-123"}
    """

    let event = StreamEventParser.parse(line: line)

    if case .system(let sessionId) = event {
      XCTAssertEqual(sessionId, "abc-123")
    } else {
      XCTFail("Expected system event, got \(String(describing: event))")
    }
  }

  // MARK: - Content Block Delta

  func testParseTextDelta() {
    let line = """
    {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello world"}}
    """

    let event = StreamEventParser.parse(line: line)

    if case .contentBlockDelta(let index, let deltaType, let text) = event {
      XCTAssertEqual(index, 0)
      XCTAssertEqual(deltaType, "text_delta")
      XCTAssertEqual(text, "Hello world")
    } else {
      XCTFail("Expected contentBlockDelta, got \(String(describing: event))")
    }
  }

  // MARK: - Result with Cached Tokens

  func testParseResultWithCachedTokens() {
    let line = """
    {"type":"result","result":"done","usage":{"input_tokens":100,"output_tokens":50,"cache_read_input_tokens":200,"cache_creation_input_tokens":30}}
    """

    let event = StreamEventParser.parse(line: line)

    if case .result(let text, let inputTokens, let outputTokens) = event {
      XCTAssertEqual(text, "done")
      /// input_tokens + cache_read + cache_creation = 100 + 200 + 30 = 330
      XCTAssertEqual(inputTokens, 330)
      XCTAssertEqual(outputTokens, 50)
    } else {
      XCTFail("Expected result event, got \(String(describing: event))")
    }
  }

  // MARK: - Edge Cases

  func testParseEmptyLine() {
    XCTAssertNil(StreamEventParser.parse(line: ""))
    XCTAssertNil(StreamEventParser.parse(line: "   "))
    XCTAssertNil(StreamEventParser.parse(line: "\n"))
  }

  func testParseMalformedJSON() {
    XCTAssertNil(StreamEventParser.parse(line: "not json at all"))
    XCTAssertNil(StreamEventParser.parse(line: "{broken json"))
    XCTAssertNil(StreamEventParser.parse(line: "[]"))
  }

  func testParseUnknownType() {
    let line = """
    {"type":"some_future_event","data":"value"}
    """

    let event = StreamEventParser.parse(line: line)

    if case .unknown = event {
      /// Expected.
    } else {
      XCTFail("Expected unknown event, got \(String(describing: event))")
    }
  }

  // MARK: - Tool Use in Assistant

  func testParseToolUseInAssistant() {
    let line = """
    {"type":"assistant","message":{"content":[{"type":"tool_use","id":"tool-1","name":"Bash","input":{"command":"ls"}}],"usage":{"input_tokens":50,"output_tokens":20}}}
    """

    let event = StreamEventParser.parse(line: line)

    if case .assistant(let content, let inputTokens, let outputTokens) = event {
      XCTAssertEqual(content.count, 1)
      XCTAssertEqual(content[0].type, "tool_use")
      XCTAssertEqual(content[0].id, "tool-1")
      XCTAssertEqual(content[0].name, "Bash")
      XCTAssertNotNil(content[0].input)
      XCTAssertEqual(inputTokens, 50)
      XCTAssertEqual(outputTokens, 20)
    } else {
      XCTFail("Expected assistant event, got \(String(describing: event))")
    }
  }

  func testParseToolUseStartIncludesName() {
    let line = """
    {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"tool-1","name":"Bash"}}
    """

    let event = StreamEventParser.parse(line: line)

    if case .contentBlockStart(let index, let blockType, let id, let name) = event {
      XCTAssertEqual(index, 0)
      XCTAssertEqual(blockType, "tool_use")
      XCTAssertEqual(id, "tool-1")
      XCTAssertEqual(name, "Bash")
    } else {
      XCTFail("Expected contentBlockStart, got \(String(describing: event))")
    }
  }

  func testParseInputJsonDeltaFromPartialJSON() {
    let line = """
    {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"abc"}}
    """

    let event = StreamEventParser.parse(line: line)

    if case .contentBlockDelta(let index, let deltaType, let text) = event {
      XCTAssertEqual(index, 0)
      XCTAssertEqual(deltaType, "input_json_delta")
      XCTAssertEqual(text, "abc")
    } else {
      XCTFail("Expected contentBlockDelta, got \(String(describing: event))")
    }
  }

  func testParseTopLevelUserToolResult() {
    let line = """
    {"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"tool-1","content":"ok","is_error":false}]}}
    """

    let event = StreamEventParser.parse(line: line)

    if case .userToolResult(let toolUseId, let content, let isError) = event {
      XCTAssertEqual(toolUseId, "tool-1")
      XCTAssertEqual(content, "ok")
      XCTAssertFalse(isError)
    } else {
      XCTFail("Expected userToolResult, got \(String(describing: event))")
    }
  }

  // MARK: - Stream Event Wrapper

  func testParseStreamEventWrapper() {
    let line = """
    {"type":"stream_event","event":{"type":"content_block_delta","index":1,"delta":{"type":"thinking_delta","text":"Let me think"}}}
    """

    let event = StreamEventParser.parse(line: line)

    if case .contentBlockDelta(let index, let deltaType, let text) = event {
      XCTAssertEqual(index, 1)
      XCTAssertEqual(deltaType, "thinking_delta")
      XCTAssertEqual(text, "Let me think")
    } else {
      XCTFail("Expected contentBlockDelta, got \(String(describing: event))")
    }
  }
}
