import XCTest
@testable import SlothyTerminalLib

final class OpenCodeStreamEventParserTests: XCTestCase {

  // MARK: - step_start

  func testParseStepStart() {
    let line = """
    {"type":"step_start","timestamp":1700000000,"sessionID":"ses_abc","part":{"id":"prt_1","sessionID":"ses_abc","messageID":"msg_1","type":"step-start","snapshot":"snap"}}
    """

    let result = OpenCodeStreamEventParser.parse(line: line)
    XCTAssertNotNil(result)
    XCTAssertEqual(result?.sessionID, "ses_abc")

    if case .stepStart(let part) = result?.event {
      XCTAssertEqual(part.id, "prt_1")
      XCTAssertEqual(part.sessionID, "ses_abc")
      XCTAssertEqual(part.messageID, "msg_1")
      XCTAssertEqual(part.snapshot, "snap")
    } else {
      XCTFail("Expected stepStart, got \(String(describing: result?.event))")
    }
  }

  // MARK: - text

  func testParseText() {
    let line = """
    {"type":"text","timestamp":1700000001,"sessionID":"ses_abc","part":{"id":"prt_2","sessionID":"ses_abc","messageID":"msg_1","type":"text","text":"Hello world"}}
    """

    let result = OpenCodeStreamEventParser.parse(line: line)
    XCTAssertNotNil(result)

    if case .text(let part) = result?.event {
      XCTAssertEqual(part.text, "Hello world")
      XCTAssertEqual(part.messageID, "msg_1")
    } else {
      XCTFail("Expected text, got \(String(describing: result?.event))")
    }
  }

  // MARK: - tool_use

  func testParseToolUse() {
    let line = """
    {"type":"tool_use","timestamp":1700000002,"sessionID":"ses_abc","part":{"id":"prt_3","sessionID":"ses_abc","messageID":"msg_1","type":"tool","callID":"toolu_123","tool":"bash","state":{"status":"completed","input":{"command":"ls","description":"List files"},"output":"file1.txt\\nfile2.txt","title":"Run ls"}}}
    """

    let result = OpenCodeStreamEventParser.parse(line: line)
    XCTAssertNotNil(result)

    if case .toolUse(let part) = result?.event {
      XCTAssertEqual(part.callID, "toolu_123")
      XCTAssertEqual(part.tool, "bash")
      XCTAssertEqual(part.status, "completed")
      XCTAssertEqual(part.input["command"], "ls")
      XCTAssertEqual(part.input["description"], "List files")
      XCTAssertEqual(part.output, "file1.txt\nfile2.txt")
      XCTAssertEqual(part.title, "Run ls")
    } else {
      XCTFail("Expected toolUse, got \(String(describing: result?.event))")
    }
  }

  // MARK: - step_finish (stop)

  func testParseStepFinishStop() {
    let line = """
    {"type":"step_finish","timestamp":1700000003,"sessionID":"ses_abc","part":{"id":"prt_4","sessionID":"ses_abc","messageID":"msg_1","type":"step-finish","reason":"stop","cost":0.05,"tokens":{"input":100,"output":40,"reasoning":0,"cache":{"read":500,"write":13948}}}}
    """

    let result = OpenCodeStreamEventParser.parse(line: line)
    XCTAssertNotNil(result)

    if case .stepFinish(let part) = result?.event {
      XCTAssertEqual(part.reason, "stop")
      XCTAssertEqual(part.cost ?? 0, 0.05, accuracy: 0.001)
      XCTAssertNotNil(part.tokens)
      XCTAssertEqual(part.tokens?.input, 100)
      XCTAssertEqual(part.tokens?.output, 40)
      XCTAssertEqual(part.tokens?.reasoning, 0)
      XCTAssertEqual(part.tokens?.cacheRead, 500)
      XCTAssertEqual(part.tokens?.cacheWrite, 13948)
    } else {
      XCTFail("Expected stepFinish, got \(String(describing: result?.event))")
    }
  }

  // MARK: - step_finish (tool-calls)

  func testParseStepFinishToolCalls() {
    let line = """
    {"type":"step_finish","timestamp":1700000003,"sessionID":"ses_abc","part":{"id":"prt_5","sessionID":"ses_abc","messageID":"msg_1","type":"step-finish","reason":"tool-calls","cost":0.02,"tokens":{"input":50,"output":20,"reasoning":0,"cache":{"read":0,"write":0}}}}
    """

    let result = OpenCodeStreamEventParser.parse(line: line)
    XCTAssertNotNil(result)

    if case .stepFinish(let part) = result?.event {
      XCTAssertEqual(part.reason, "tool-calls")
    } else {
      XCTFail("Expected stepFinish, got \(String(describing: result?.event))")
    }
  }

  // MARK: - Edge Cases

  func testParseEmptyLine() {
    XCTAssertNil(OpenCodeStreamEventParser.parse(line: ""))
    XCTAssertNil(OpenCodeStreamEventParser.parse(line: "   "))
    XCTAssertNil(OpenCodeStreamEventParser.parse(line: "\n"))
  }

  func testParseMalformedJSON() {
    XCTAssertNil(OpenCodeStreamEventParser.parse(line: "not json"))
    XCTAssertNil(OpenCodeStreamEventParser.parse(line: "{broken"))
    XCTAssertNil(OpenCodeStreamEventParser.parse(line: "[]"))
  }

  func testParseUnknownType() {
    let line = """
    {"type":"some_future_event","sessionID":"ses_abc","part":{}}
    """

    let result = OpenCodeStreamEventParser.parse(line: line)
    XCTAssertNotNil(result)

    if case .unknown = result?.event {
      /// Expected.
    } else {
      XCTFail("Expected unknown, got \(String(describing: result?.event))")
    }
  }

  func testParseMissingType() {
    let line = """
    {"sessionID":"ses_abc","part":{"id":"prt_1"}}
    """

    XCTAssertNil(OpenCodeStreamEventParser.parse(line: line))
  }

  func testParseSessionIDExtractedFromTopLevel() {
    let line = """
    {"type":"text","timestamp":1700000001,"sessionID":"ses_xyz","part":{"id":"prt_1","sessionID":"ses_other","messageID":"msg_1","type":"text","text":"hi"}}
    """

    let result = OpenCodeStreamEventParser.parse(line: line)

    /// Top-level sessionID should be returned.
    XCTAssertEqual(result?.sessionID, "ses_xyz")
  }

  // MARK: - Mapper: Context Management

  func testMapperStepStartResetsContext() {
    var ctx = OpenCodeMapperContext(blockIndex: 5, textBlockOpen: true)
    let event = OpenCodeStreamEvent.stepStart(OpenCodeStepStartPart(
      id: "prt_1", sessionID: "ses_1", messageID: "msg_1", snapshot: nil
    ))

    let mapped = OpenCodeEventMapper.map(event, context: &ctx)

    XCTAssertEqual(ctx.blockIndex, 0)
    XCTAssertFalse(ctx.textBlockOpen)
    XCTAssertEqual(mapped.count, 1)

    if case .messageStart(let inputTokens) = mapped[0] {
      XCTAssertEqual(inputTokens, 0)
    } else {
      XCTFail("Expected messageStart")
    }
  }

  // MARK: - Mapper: Text Block Lifecycle

  func testMapperFirstTextEmitsStartAndDelta() {
    var ctx = OpenCodeMapperContext()
    let event = OpenCodeStreamEvent.text(OpenCodeTextPart(
      id: "prt_2", sessionID: "ses_1", messageID: "msg_1", text: "Hello"
    ))

    let mapped = OpenCodeEventMapper.map(event, context: &ctx)

    /// First text should emit contentBlockStart + contentBlockDelta.
    XCTAssertEqual(mapped.count, 2)
    XCTAssertTrue(ctx.textBlockOpen)
    XCTAssertEqual(ctx.blockIndex, 0)

    if case .contentBlockStart(let index, let blockType, _, _) = mapped[0] {
      XCTAssertEqual(index, 0)
      XCTAssertEqual(blockType, "text")
    } else {
      XCTFail("Expected contentBlockStart")
    }

    if case .contentBlockDelta(let index, let deltaType, let text) = mapped[1] {
      XCTAssertEqual(index, 0)
      XCTAssertEqual(deltaType, "text_delta")
      XCTAssertEqual(text, "Hello")
    } else {
      XCTFail("Expected contentBlockDelta")
    }
  }

  func testMapperSubsequentTextEmitsOnlyDelta() {
    var ctx = OpenCodeMapperContext(blockIndex: 0, textBlockOpen: true)
    let event = OpenCodeStreamEvent.text(OpenCodeTextPart(
      id: "prt_3", sessionID: "ses_1", messageID: "msg_1", text: " world"
    ))

    let mapped = OpenCodeEventMapper.map(event, context: &ctx)

    /// Subsequent text should emit only contentBlockDelta (no start).
    XCTAssertEqual(mapped.count, 1)

    if case .contentBlockDelta(let index, _, let text) = mapped[0] {
      XCTAssertEqual(index, 0)
      XCTAssertEqual(text, " world")
    } else {
      XCTFail("Expected contentBlockDelta")
    }
  }

  // MARK: - Mapper: Tool Use Closes Text Block

  func testMapperToolUseClosesOpenTextBlock() {
    var ctx = OpenCodeMapperContext(blockIndex: 0, textBlockOpen: true)
    let event = OpenCodeStreamEvent.toolUse(OpenCodeToolUsePart(
      id: "prt_4", sessionID: "ses_1", messageID: "msg_1",
      callID: "toolu_1", tool: "bash", status: "completed",
      input: ["command": "ls"], output: "file.txt", title: "List"
    ))

    let mapped = OpenCodeEventMapper.map(event, context: &ctx)

    /// Should emit: contentBlockStop(0) + tool start(1) + delta(1) + stop(1) + toolResult
    XCTAssertEqual(mapped.count, 5)
    XCTAssertFalse(ctx.textBlockOpen)
    /// blockIndex = 1 (text close) + 1 (tool) + 1 (tool result padding) = 3
    XCTAssertEqual(ctx.blockIndex, 3)

    /// First: close text block.
    if case .contentBlockStop(let index) = mapped[0] {
      XCTAssertEqual(index, 0)
    } else {
      XCTFail("Expected contentBlockStop for text, got \(mapped[0])")
    }

    /// Then: tool use at index 1.
    if case .contentBlockStart(let index, let blockType, let id, let name) = mapped[1] {
      XCTAssertEqual(index, 1)
      XCTAssertEqual(blockType, "tool_use")
      XCTAssertEqual(id, "toolu_1")
      XCTAssertEqual(name, "bash")
    } else {
      XCTFail("Expected contentBlockStart for tool")
    }

    if case .contentBlockStop(let index) = mapped[3] {
      XCTAssertEqual(index, 1)
    } else {
      XCTFail("Expected contentBlockStop for tool")
    }

    if case .userToolResult(let toolUseId, let content, let isError) = mapped[4] {
      XCTAssertEqual(toolUseId, "toolu_1")
      XCTAssertEqual(content, "file.txt")
      XCTAssertFalse(isError)
    } else {
      XCTFail("Expected userToolResult")
    }
  }

  func testMapperToolUseWithoutOpenTextBlock() {
    var ctx = OpenCodeMapperContext()
    let event = OpenCodeStreamEvent.toolUse(OpenCodeToolUsePart(
      id: "prt_3", sessionID: "ses_1", messageID: "msg_1",
      callID: "toolu_1", tool: "bash", status: "completed",
      input: ["command": "ls"], output: "file.txt", title: "List"
    ))

    let mapped = OpenCodeEventMapper.map(event, context: &ctx)

    /// No text block to close, so just 4 events for tool use.
    XCTAssertEqual(mapped.count, 4)
    /// blockIndex = 1 (tool) + 1 (tool result padding) = 2
    XCTAssertEqual(ctx.blockIndex, 2)

    if case .contentBlockStart(let index, _, _, _) = mapped[0] {
      XCTAssertEqual(index, 0)
    } else {
      XCTFail("Expected contentBlockStart at 0")
    }
  }

  // MARK: - Mapper: Step Finish Closes Text Block

  func testMapperStepFinishStopClosesTextBlock() {
    var ctx = OpenCodeMapperContext(blockIndex: 0, textBlockOpen: true)
    let event = OpenCodeStreamEvent.stepFinish(OpenCodeStepFinishPart(
      id: "prt_4", sessionID: "ses_1", messageID: "msg_1",
      reason: "stop", cost: 0.05,
      tokens: OpenCodeTokens(input: 100, output: 40, reasoning: 0, cacheRead: 500, cacheWrite: 200)
    ))

    let mapped = OpenCodeEventMapper.map(event, context: &ctx)

    /// Should emit: contentBlockStop(0) + result.
    XCTAssertEqual(mapped.count, 2)
    XCTAssertFalse(ctx.textBlockOpen)

    if case .contentBlockStop(let index) = mapped[0] {
      XCTAssertEqual(index, 0)
    } else {
      XCTFail("Expected contentBlockStop")
    }

    if case .result(let text, let inputTokens, let outputTokens) = mapped[1] {
      XCTAssertEqual(text, "")
      XCTAssertEqual(inputTokens, 800)
      XCTAssertEqual(outputTokens, 40)
    } else {
      XCTFail("Expected result")
    }
  }

  func testMapperStepFinishWithoutOpenTextBlock() {
    var ctx = OpenCodeMapperContext()
    let event = OpenCodeStreamEvent.stepFinish(OpenCodeStepFinishPart(
      id: "prt_4", sessionID: "ses_1", messageID: "msg_1",
      reason: "stop", cost: 0.05, tokens: nil
    ))

    let mapped = OpenCodeEventMapper.map(event, context: &ctx)

    XCTAssertEqual(mapped.count, 1)

    if case .result = mapped[0] {
      /// Expected.
    } else {
      XCTFail("Expected result")
    }
  }

  func testMapperStepFinishToolCallsEmitsMessageStop() {
    var ctx = OpenCodeMapperContext()
    let event = OpenCodeStreamEvent.stepFinish(OpenCodeStepFinishPart(
      id: "prt_5", sessionID: "ses_1", messageID: "msg_1",
      reason: "tool-calls", cost: 0.02, tokens: nil
    ))

    let mapped = OpenCodeEventMapper.map(event, context: &ctx)

    XCTAssertEqual(mapped.count, 1)

    if case .messageStop = mapped[0] {
      /// Expected.
    } else {
      XCTFail("Expected messageStop")
    }
  }

  // MARK: - Mapper: Full Turn Scenarios

  func testMapperPlainTextTurn() {
    /// Simulates: step_start → text("Hello ") → text("world") → step_finish(stop)
    var ctx = OpenCodeMapperContext()

    let e1 = OpenCodeEventMapper.map(
      .stepStart(OpenCodeStepStartPart(
        id: "1", sessionID: "s", messageID: "m", snapshot: nil
      )),
      context: &ctx
    )
    XCTAssertEqual(e1.count, 1)

    let e2 = OpenCodeEventMapper.map(
      .text(OpenCodeTextPart(id: "2", sessionID: "s", messageID: "m", text: "Hello ")),
      context: &ctx
    )
    XCTAssertEqual(e2.count, 2)

    let e3 = OpenCodeEventMapper.map(
      .text(OpenCodeTextPart(id: "3", sessionID: "s", messageID: "m", text: "world")),
      context: &ctx
    )
    XCTAssertEqual(e3.count, 1)

    let e4 = OpenCodeEventMapper.map(
      .stepFinish(OpenCodeStepFinishPart(
        id: "4", sessionID: "s", messageID: "m",
        reason: "stop", cost: nil, tokens: nil
      )),
      context: &ctx
    )
    XCTAssertEqual(e4.count, 2)

    /// Total: messageStart, blockStart(0,text), delta(0,"Hello "), delta(0,"world"),
    ///        blockStop(0), result
    let all = e1 + e2 + e3 + e4
    XCTAssertEqual(all.count, 6)
  }

  func testMapperTextThenToolThenTextTurn() {
    /// Simulates: step_start → text("I'll check") → tool_use(bash,ls) →
    ///            text("Here are files") → step_finish(stop)
    var ctx = OpenCodeMapperContext()

    /// step_start
    let _ = OpenCodeEventMapper.map(
      .stepStart(OpenCodeStepStartPart(
        id: "1", sessionID: "s", messageID: "m", snapshot: nil
      )),
      context: &ctx
    )

    /// text → opens text block at index 0
    let e2 = OpenCodeEventMapper.map(
      .text(OpenCodeTextPart(id: "2", sessionID: "s", messageID: "m", text: "I'll check")),
      context: &ctx
    )
    XCTAssertEqual(e2.count, 2)
    XCTAssertTrue(ctx.textBlockOpen)
    XCTAssertEqual(ctx.blockIndex, 0)

    /// tool_use → closes text(0), opens tool at index 1
    let e3 = OpenCodeEventMapper.map(
      .toolUse(OpenCodeToolUsePart(
        id: "3", sessionID: "s", messageID: "m",
        callID: "t1", tool: "bash", status: "completed",
        input: ["command": "ls"], output: "files", title: nil
      )),
      context: &ctx
    )
    XCTAssertEqual(e3.count, 5)
    XCTAssertFalse(ctx.textBlockOpen)
    /// blockIndex = 1 (text close) + 1 (tool) + 1 (tool result) = 3
    XCTAssertEqual(ctx.blockIndex, 3)

    /// text → opens new text block at index 3
    let e4 = OpenCodeEventMapper.map(
      .text(OpenCodeTextPart(id: "4", sessionID: "s", messageID: "m", text: "Here are files")),
      context: &ctx
    )
    XCTAssertEqual(e4.count, 2)
    XCTAssertTrue(ctx.textBlockOpen)
    XCTAssertEqual(ctx.blockIndex, 3)

    /// step_finish → closes text(2), emits result
    let e5 = OpenCodeEventMapper.map(
      .stepFinish(OpenCodeStepFinishPart(
        id: "5", sessionID: "s", messageID: "m",
        reason: "stop", cost: nil, tokens: nil
      )),
      context: &ctx
    )
    XCTAssertEqual(e5.count, 2)
    XCTAssertFalse(ctx.textBlockOpen)
  }

  // MARK: - Engine Integration: Full OpenCode Turn

  func testEngineProcessesPlainTextTurn() {
    let engine = ChatSessionEngine(
      workingDirectory: URL(fileURLWithPath: "/tmp")
    )

    /// Start transport and send message.
    let _ = engine.handle(.transportReady(sessionId: "ses_1"))
    let _ = engine.handle(.userSendMessage("Hello"))

    /// Simulate OpenCode events mapped to StreamEvents.
    var ctx = OpenCodeMapperContext()

    let events = [
      OpenCodeStreamEvent.stepStart(OpenCodeStepStartPart(
        id: "1", sessionID: "s", messageID: "m", snapshot: nil
      )),
      OpenCodeStreamEvent.text(OpenCodeTextPart(
        id: "2", sessionID: "s", messageID: "m", text: "Hi there! "
      )),
      OpenCodeStreamEvent.text(OpenCodeTextPart(
        id: "3", sessionID: "s", messageID: "m", text: "How can I help?"
      )),
      OpenCodeStreamEvent.stepFinish(OpenCodeStepFinishPart(
        id: "4", sessionID: "s", messageID: "m",
        reason: "stop", cost: 0.01,
        tokens: OpenCodeTokens(input: 50, output: 20, reasoning: 0, cacheRead: 0, cacheWrite: 0)
      )),
    ]

    for event in events {
      let streamEvents = OpenCodeEventMapper.map(event, context: &ctx)
      for se in streamEvents {
        let _ = engine.handle(.transportStreamEvent(se))
      }
    }

    /// Verify engine state.
    XCTAssertEqual(engine.sessionState, .ready)
    XCTAssertNil(engine.currentToolName)

    /// Verify conversation: 1 user + 1 assistant.
    XCTAssertEqual(engine.conversation.messages.count, 2)

    let assistant = engine.conversation.messages[1]
    XCTAssertEqual(assistant.role, .assistant)
    XCTAssertFalse(assistant.isStreaming)

    /// Verify text content was assembled correctly.
    XCTAssertEqual(assistant.contentBlocks.count, 1)

    if case .text(let content) = assistant.contentBlocks[0] {
      XCTAssertEqual(content, "Hi there! How can I help?")
    } else {
      XCTFail("Expected text block, got \(assistant.contentBlocks[0])")
    }
  }

  func testEngineProcessesToolUseTurn() {
    let engine = ChatSessionEngine(
      workingDirectory: URL(fileURLWithPath: "/tmp")
    )

    let _ = engine.handle(.transportReady(sessionId: "ses_1"))
    let _ = engine.handle(.userSendMessage("list files"))

    var ctx = OpenCodeMapperContext()

    let events: [OpenCodeStreamEvent] = [
      .stepStart(OpenCodeStepStartPart(
        id: "1", sessionID: "s", messageID: "m", snapshot: nil
      )),
      .text(OpenCodeTextPart(
        id: "2", sessionID: "s", messageID: "m", text: "I'll list the files."
      )),
      .toolUse(OpenCodeToolUsePart(
        id: "3", sessionID: "s", messageID: "m",
        callID: "toolu_1", tool: "bash", status: "completed",
        input: ["command": "ls"], output: "README.md\nPackage.swift", title: nil
      )),
      .text(OpenCodeTextPart(
        id: "4", sessionID: "s", messageID: "m", text: "Here are your files."
      )),
      .stepFinish(OpenCodeStepFinishPart(
        id: "5", sessionID: "s", messageID: "m",
        reason: "stop", cost: 0.03,
        tokens: OpenCodeTokens(input: 100, output: 50, reasoning: 0, cacheRead: 0, cacheWrite: 0)
      )),
    ]

    for event in events {
      let streamEvents = OpenCodeEventMapper.map(event, context: &ctx)
      for se in streamEvents {
        let _ = engine.handle(.transportStreamEvent(se))
      }
    }

    XCTAssertEqual(engine.sessionState, .ready)

    let assistant = engine.conversation.messages[1]
    XCTAssertFalse(assistant.isStreaming)

    /// Should have: text(0), toolUse(1), toolResult, text(2)
    /// Block layout: text "I'll list" at 0, tool at 1, toolResult, text "Here are" at 2
    XCTAssertGreaterThanOrEqual(assistant.contentBlocks.count, 3)

    /// Verify text block 0.
    if case .text(let t) = assistant.contentBlocks[0] {
      XCTAssertEqual(t, "I'll list the files.")
    } else {
      XCTFail("Expected text at index 0")
    }

    /// Verify tool use block.
    if case .toolUse(let id, let name, _) = assistant.contentBlocks[1] {
      XCTAssertEqual(id, "toolu_1")
      XCTAssertEqual(name, "bash")
    } else {
      XCTFail("Expected toolUse at index 1")
    }

    /// Verify tool result was appended.
    let hasToolResult = assistant.contentBlocks.contains { block in
      if case .toolResult(let toolUseId, _) = block {
        return toolUseId == "toolu_1"
      }
      return false
    }
    XCTAssertTrue(hasToolResult, "Should contain tool result for toolu_1")
  }

  func testEngineProcessesMultiStepToolTurn() {
    let engine = ChatSessionEngine(
      workingDirectory: URL(fileURLWithPath: "/tmp")
    )

    let _ = engine.handle(.transportReady(sessionId: "ses_1"))
    let _ = engine.handle(.userSendMessage("build and test"))

    var ctx = OpenCodeMapperContext()

    /// Step 1: tool use + intermediate finish.
    let step1Events: [OpenCodeStreamEvent] = [
      .stepStart(OpenCodeStepStartPart(
        id: "1", sessionID: "s", messageID: "m", snapshot: nil
      )),
      .text(OpenCodeTextPart(
        id: "2", sessionID: "s", messageID: "m", text: "Running build."
      )),
      .toolUse(OpenCodeToolUsePart(
        id: "3", sessionID: "s", messageID: "m",
        callID: "toolu_1", tool: "bash", status: "completed",
        input: ["command": "swift build"], output: "Build succeeded", title: nil
      )),
      .stepFinish(OpenCodeStepFinishPart(
        id: "4", sessionID: "s", messageID: "m",
        reason: "tool-calls", cost: 0.02, tokens: nil
      )),
    ]

    for event in step1Events {
      let streamEvents = OpenCodeEventMapper.map(event, context: &ctx)
      for se in streamEvents {
        let _ = engine.handle(.transportStreamEvent(se))
      }
    }

    /// After intermediate step_finish, engine stays active.
    XCTAssertTrue(engine.sessionState.isProcessingTurn)

    /// Step 2: final text + stop.
    let step2Events: [OpenCodeStreamEvent] = [
      .stepStart(OpenCodeStepStartPart(
        id: "5", sessionID: "s", messageID: "m2", snapshot: nil
      )),
      .text(OpenCodeTextPart(
        id: "6", sessionID: "s", messageID: "m2", text: "Build succeeded!"
      )),
      .stepFinish(OpenCodeStepFinishPart(
        id: "7", sessionID: "s", messageID: "m2",
        reason: "stop", cost: 0.01,
        tokens: OpenCodeTokens(input: 200, output: 80, reasoning: 0, cacheRead: 0, cacheWrite: 0)
      )),
    ]

    for event in step2Events {
      let streamEvents = OpenCodeEventMapper.map(event, context: &ctx)
      for se in streamEvents {
        let _ = engine.handle(.transportStreamEvent(se))
      }
    }

    /// After final step_finish(stop), engine is ready.
    XCTAssertEqual(engine.sessionState, .ready)

    /// Should have user message + 2 assistant messages (one per step).
    XCTAssertGreaterThanOrEqual(engine.conversation.messages.count, 3)

    /// Second assistant message should have the final text.
    let lastAssistant = engine.conversation.messages.last { $0.role == .assistant }
    XCTAssertNotNil(lastAssistant)
    XCTAssertFalse(lastAssistant?.isStreaming ?? true)
  }
}
