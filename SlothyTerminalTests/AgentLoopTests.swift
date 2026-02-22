import Foundation
import Testing

@testable import SlothyTerminalLib

@Suite("AgentLoop")
struct AgentLoopTests {

  /// A stub tool that returns a fixed output.
  private struct StubTool: AgentTool {
    let id: String
    let toolDescription: String
    let parameters = ToolParameterSchema(
      type: "object",
      properties: [:],
      required: []
    )
    let fixedOutput: String

    func execute(
      arguments: [String: JSONValue],
      context: ToolContext
    ) async throws -> ToolResult {
      ToolResult(output: fixedOutput)
    }
  }

  /// A tool that records its executions.
  private final class RecordingTool: AgentTool, @unchecked Sendable {
    let id: String
    let toolDescription = "Recording tool"
    let parameters = ToolParameterSchema(
      type: "object",
      properties: [:],
      required: []
    )

    private(set) var executionCount = 0

    init(id: String) {
      self.id = id
    }

    func execute(
      arguments: [String: JSONValue],
      context: ToolContext
    ) async throws -> ToolResult {
      executionCount += 1
      return ToolResult(output: "executed \(executionCount)")
    }
  }

  private func makeContext() -> ToolContext {
    ToolContext(
      sessionID: "test-session",
      workingDirectory: FileManager.default.temporaryDirectory,
      permissions: MockPermissionDelegate()
    )
  }

  private func makeInput(model: ModelDescriptor? = nil) -> RuntimeInput {
    let m = model ?? ModelDescriptor(
      providerID: .anthropic,
      modelID: "claude-sonnet-4-6",
      packageID: "@ai-sdk/anthropic",
      supportsReasoning: true,
      releaseDate: "2025-05-14",
      outputLimit: 16_384
    )
    return RuntimeInput(
      sessionID: "test-session",
      model: m,
      messages: []
    )
  }

  // MARK: - Text-only response exits loop

  @Test("Text-only response exits loop and returns text")
  func textOnlyResponse() async throws {
    let mockRuntime = MockAgentRuntime()
    mockRuntime.responses = [
      [
        .textDelta("Hello "),
        .textDelta("world!"),
        .messageComplete(stopReason: "end_turn"),
      ]
    ]

    let registry = ToolRegistry()
    let loop = AgentLoop(
      runtime: mockRuntime,
      registry: registry,
      agent: .build
    )

    var messages: [[String: JSONValue]] = []
    let result = try await loop.run(
      input: makeInput(),
      messages: &messages,
      context: makeContext()
    )

    #expect(result == "Hello world!")
    #expect(mockRuntime.receivedInputs.count == 1)
  }

  // MARK: - Tool call → execute → feed back cycle

  @Test("Tool call is executed and result fed back to LLM")
  func toolCallCycle() async throws {
    let mockRuntime = MockAgentRuntime()

    /// Step 1: LLM responds with a tool call.
    mockRuntime.responses = [
      [
        .toolCallStart(id: "toolu_1", name: "read"),
        .toolCallDelta(id: "toolu_1", argumentsDelta: "{}"),
        .toolCallEnd(id: "toolu_1"),
        .messageComplete(stopReason: "tool_use"),
      ],
      /// Step 2: After tool result, LLM responds with text.
      [
        .textDelta("Done reading."),
        .messageComplete(stopReason: "end_turn"),
      ],
    ]

    let registry = ToolRegistry()
    registry.registerBuiltIn([
      StubTool(id: "read", toolDescription: "Read", fixedOutput: "file contents")
    ])

    let loop = AgentLoop(
      runtime: mockRuntime,
      registry: registry,
      agent: .build
    )

    var messages: [[String: JSONValue]] = []
    let result = try await loop.run(
      input: makeInput(),
      messages: &messages,
      context: makeContext()
    )

    #expect(result == "Done reading.")
    /// 2 LLM calls: initial + after tool result.
    #expect(mockRuntime.receivedInputs.count == 2)

    /// Messages should have: assistant (with tool call) + user (with tool result).
    #expect(messages.count == 2)
  }

  // MARK: - Doom-loop detection

  @Test("Doom loop detected after threshold identical calls")
  func doomLoopDetection() async throws {
    let mockRuntime = MockAgentRuntime()

    /// Script 4 identical tool call responses (threshold is 3).
    let toolCallResponse: [ProviderStreamEvent] = [
      .toolCallStart(id: "toolu_1", name: "bash"),
      .toolCallDelta(id: "toolu_1", argumentsDelta: "{\"command\":\"ls\"}"),
      .toolCallEnd(id: "toolu_1"),
      .messageComplete(stopReason: "tool_use"),
    ]

    mockRuntime.responses = [
      toolCallResponse,
      toolCallResponse,
      toolCallResponse,
      /// After doom loop, LLM should get error result and respond with text.
      [
        .textDelta("I'll try a different approach."),
        .messageComplete(stopReason: "end_turn"),
      ],
    ]

    let registry = ToolRegistry()
    registry.registerBuiltIn([
      StubTool(id: "bash", toolDescription: "Bash", fixedOutput: "output")
    ])

    let loop = AgentLoop(
      runtime: mockRuntime,
      registry: registry,
      agent: .build,
      doomLoopThreshold: 3
    )

    var messages: [[String: JSONValue]] = []
    var events: [AgentLoopEvent] = []
    let result = try await loop.run(
      input: makeInput(),
      messages: &messages,
      context: makeContext(),
      onEvent: { events.append($0) }
    )

    #expect(result == "I'll try a different approach.")

    /// The third identical call should produce a doom-loop error result.
    let doomResults = events.compactMap { event -> String? in
      if case .toolResult(_, _, let output, let isError) = event,
         isError,
         output.contains("repeated identical")
      {
        return output
      }
      return nil
    }
    #expect(!doomResults.isEmpty)
  }

  // MARK: - Max steps enforcement

  @Test("Max steps exceeded throws error")
  func maxStepsExceeded() async throws {
    let mockRuntime = MockAgentRuntime()

    /// Keep returning tool calls forever — agent should stop at maxSteps.
    let toolCallResponse: [ProviderStreamEvent] = [
      .toolCallStart(id: "toolu_1", name: "read"),
      .toolCallDelta(id: "toolu_1", argumentsDelta: "{}"),
      .toolCallEnd(id: "toolu_1"),
      .messageComplete(stopReason: "tool_use"),
    ]

    /// Fill with enough responses.
    mockRuntime.responses = Array(repeating: toolCallResponse, count: 5)

    let registry = ToolRegistry()
    registry.registerBuiltIn([
      StubTool(id: "read", toolDescription: "Read", fixedOutput: "data")
    ])

    /// Agent with maxSteps = 2.
    let agent = AgentDefinition(name: "test", maxSteps: 2)
    let loop = AgentLoop(
      runtime: mockRuntime,
      registry: registry,
      agent: agent
    )

    var messages: [[String: JSONValue]] = []

    do {
      _ = try await loop.run(
        input: makeInput(),
        messages: &messages,
        context: makeContext()
      )
      Issue.record("Expected AgentLoopError.maxStepsExceeded")
    } catch let error as AgentLoopError {
      if case .maxStepsExceeded(let limit) = error {
        #expect(limit == 2)
      } else {
        Issue.record("Expected maxStepsExceeded, got \(error)")
      }
    }
  }

  // MARK: - Permission denied

  @Test("Permission denied produces error tool result")
  func permissionDenied() async throws {
    let mockRuntime = MockAgentRuntime()
    mockRuntime.responses = [
      [
        .toolCallStart(id: "toolu_1", name: "bash"),
        .toolCallDelta(id: "toolu_1", argumentsDelta: "{\"command\":\"rm -rf /\"}"),
        .toolCallEnd(id: "toolu_1"),
        .messageComplete(stopReason: "tool_use"),
      ],
      [
        .textDelta("OK, I won't do that."),
        .messageComplete(stopReason: "end_turn"),
      ],
    ]

    let registry = ToolRegistry()
    registry.registerBuiltIn([
      StubTool(id: "bash", toolDescription: "Bash", fixedOutput: "")
    ])

    let denyingDelegate = MockPermissionDelegate { tool, _ in
      if tool == "bash" {
        throw PermissionError.denied(tool: tool, path: nil)
      }
      return .once
    }

    let ctx = ToolContext(
      sessionID: "test",
      workingDirectory: FileManager.default.temporaryDirectory,
      permissions: denyingDelegate
    )

    let loop = AgentLoop(
      runtime: mockRuntime,
      registry: registry,
      agent: .build
    )

    var messages: [[String: JSONValue]] = []
    var events: [AgentLoopEvent] = []
    let result = try await loop.run(
      input: makeInput(),
      messages: &messages,
      context: ctx,
      onEvent: { events.append($0) }
    )

    #expect(result == "OK, I won't do that.")

    /// Verify that a permission denied error was fed back.
    let deniedResults = events.compactMap { event -> String? in
      if case .toolResult(_, _, let output, let isError) = event,
         isError,
         output.contains("Permission denied")
      {
        return output
      }
      return nil
    }
    #expect(!deniedResults.isEmpty)
  }

  // MARK: - Unknown tool

  @Test("Unknown tool produces error result")
  func unknownTool() async throws {
    let mockRuntime = MockAgentRuntime()
    mockRuntime.responses = [
      [
        .toolCallStart(id: "toolu_1", name: "nonexistent"),
        .toolCallDelta(id: "toolu_1", argumentsDelta: "{}"),
        .toolCallEnd(id: "toolu_1"),
        .messageComplete(stopReason: "tool_use"),
      ],
      [
        .textDelta("Sorry about that."),
        .messageComplete(stopReason: "end_turn"),
      ],
    ]

    let registry = ToolRegistry()
    let loop = AgentLoop(
      runtime: mockRuntime,
      registry: registry,
      agent: .build
    )

    var messages: [[String: JSONValue]] = []
    var events: [AgentLoopEvent] = []
    let result = try await loop.run(
      input: makeInput(),
      messages: &messages,
      context: makeContext(),
      onEvent: { events.append($0) }
    )

    #expect(result == "Sorry about that.")

    let unknownErrors = events.compactMap { event -> String? in
      if case .toolResult(_, _, let output, let isError) = event,
         isError,
         output.contains("Unknown tool")
      {
        return output
      }
      return nil
    }
    #expect(!unknownErrors.isEmpty)
  }

  // MARK: - Events emitted correctly

  @Test("Step start and step end events are emitted")
  func stepEvents() async throws {
    let mockRuntime = MockAgentRuntime()
    mockRuntime.responses = [
      [
        .textDelta("Hi"),
        .messageComplete(stopReason: "end_turn"),
      ]
    ]

    let registry = ToolRegistry()
    let loop = AgentLoop(
      runtime: mockRuntime,
      registry: registry,
      agent: .build
    )

    var messages: [[String: JSONValue]] = []
    var events: [AgentLoopEvent] = []
    _ = try await loop.run(
      input: makeInput(),
      messages: &messages,
      context: makeContext(),
      onEvent: { events.append($0) }
    )

    let hasStepStart = events.contains { e in
      if case .stepStart(let idx) = e { return idx == 0 }
      return false
    }
    let hasStepEnd = events.contains { e in
      if case .stepEnd(let idx) = e { return idx == 0 }
      return false
    }
    let hasFinished = events.contains { e in
      if case .finished = e { return true }
      return false
    }

    #expect(hasStepStart)
    #expect(hasStepEnd)
    #expect(hasFinished)
  }

  // MARK: - Multi-step tool calls

  @Test("Multiple tool calls in a single response are all executed")
  func multipleToolCallsInResponse() async throws {
    let mockRuntime = MockAgentRuntime()
    mockRuntime.responses = [
      [
        .toolCallStart(id: "toolu_1", name: "read"),
        .toolCallDelta(id: "toolu_1", argumentsDelta: "{}"),
        .toolCallEnd(id: "toolu_1"),
        .toolCallStart(id: "toolu_2", name: "glob"),
        .toolCallDelta(id: "toolu_2", argumentsDelta: "{}"),
        .toolCallEnd(id: "toolu_2"),
        .messageComplete(stopReason: "tool_use"),
      ],
      [
        .textDelta("All done."),
        .messageComplete(stopReason: "end_turn"),
      ],
    ]

    let readTool = RecordingTool(id: "read")
    let globTool = RecordingTool(id: "glob")

    let registry = ToolRegistry()
    registry.registerBuiltIn([readTool, globTool])

    let loop = AgentLoop(
      runtime: mockRuntime,
      registry: registry,
      agent: .build
    )

    var messages: [[String: JSONValue]] = []
    let result = try await loop.run(
      input: makeInput(),
      messages: &messages,
      context: makeContext()
    )

    #expect(result == "All done.")
    #expect(readTool.executionCount == 1)
    #expect(globTool.executionCount == 1)
  }
}
