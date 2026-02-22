import Foundation

/// Callback type for agent loop events sent to the UI layer.
typealias AgentEventHandler = @Sendable (AgentLoopEvent) -> Void

/// Events emitted by the agent loop for driving UI updates.
enum AgentLoopEvent: Sendable {
  case textDelta(String)
  case thinkingDelta(String)
  case toolCallStart(id: String, name: String)
  case toolCallDelta(id: String, argumentsDelta: String)
  case toolCallComplete(id: String, name: String, arguments: String)
  case toolResult(id: String, name: String, output: String, isError: Bool)
  case stepStart(index: Int)
  case stepEnd(index: Int)
  case usage(input: Int, output: Int)
  case finished
  case error(String)
}

/// The core agent execution loop.
///
/// Drives the LLM → tool → LLM cycle:
/// 1. Send messages + tools to LLM via runtime
/// 2. Stream and accumulate the response (text, thinking, tool calls)
/// 3. Execute tool calls (with permission checks)
/// 4. Append tool results to message history
/// 5. If tool calls were made → repeat from step 1
/// 6. If text-only response → return
///
/// Includes doom-loop detection (3+ identical tool calls) and
/// step limit enforcement.
final class AgentLoop: @unchecked Sendable {
  private let runtime: AgentRuntimeProtocol
  private let registry: ToolRegistry
  private let agent: AgentDefinition
  private let doomLoopThreshold: Int

  init(
    runtime: AgentRuntimeProtocol,
    registry: ToolRegistry,
    agent: AgentDefinition,
    doomLoopThreshold: Int = 3
  ) {
    self.runtime = runtime
    self.registry = registry
    self.agent = agent
    self.doomLoopThreshold = doomLoopThreshold
  }

  /// Run the agent loop, returning the final assistant text.
  ///
  /// - Parameters:
  ///   - input: Base runtime input (model, variant, etc.). Messages are built per step.
  ///   - messages: Mutable message history. Tool results are appended in place.
  ///   - context: Tool execution context (working directory, permissions).
  ///   - onEvent: Optional callback for UI updates.
  /// - Returns: The final assistant text response.
  func run(
    input: RuntimeInput,
    messages: inout [[String: JSONValue]],
    context: ToolContext,
    onEvent: AgentEventHandler? = nil
  ) async throws -> String {
    var stepIndex = 0
    var finalText = ""
    var toolCallHistory: [ToolCallSignature: Int] = [:]
    let toolDefs = registry.toolDefinitions(for: agent.mode)

    while stepIndex < agent.maxSteps {
      try Task.checkCancellation()
      onEvent?(.stepStart(index: stepIndex))

      /// Compact context if it exceeds the token budget.
      ContextCompactor.compactIfNeeded(
        messages: &messages,
        model: input.model
      )

      /// Build per-step runtime input with current messages.
      let stepInput = RuntimeInput(
        sessionID: input.sessionID,
        model: input.model,
        messages: messages,
        tools: toolDefs,
        systemPrompt: input.systemPrompt ?? agent.systemPrompt,
        selectedVariant: input.selectedVariant ?? agent.variant,
        userOptions: input.userOptions
      )

      /// Stream the LLM response and accumulate content.
      let accumulated = try await streamAndAccumulate(
        input: stepInput,
        onEvent: onEvent
      )

      /// Update final text.
      if !accumulated.text.isEmpty {
        finalText = accumulated.text
      }

      /// If no tool calls → done.
      if accumulated.toolCalls.isEmpty {
        onEvent?(.stepEnd(index: stepIndex))
        break
      }

      /// Build assistant message with text + tool calls.
      var assistantContent: [JSONValue] = []

      if !accumulated.text.isEmpty {
        assistantContent.append(.object([
          "type": .string("text"),
          "text": .string(accumulated.text),
        ]))
      }

      for call in accumulated.toolCalls {
        assistantContent.append(.object([
          "type": .string("tool_use"),
          "id": .string(call.id),
          "name": .string(call.name),
          "input": .string(call.arguments),
        ]))
      }

      messages.append([
        "role": .string("assistant"),
        "content": .array(assistantContent),
      ])

      /// Execute tool calls and collect results.
      var toolResults: [JSONValue] = []

      for call in accumulated.toolCalls {
        let result = await executeToolCall(
          call: call,
          context: context,
          toolCallHistory: &toolCallHistory,
          onEvent: onEvent
        )
        toolResults.append(.object([
          "type": .string("tool_result"),
          "tool_use_id": .string(call.id),
          "content": .string(result.output),
          "is_error": .bool(result.isError),
        ]))
      }

      /// Append tool results as a user message.
      messages.append([
        "role": .string("user"),
        "content": .array(toolResults),
      ])

      onEvent?(.stepEnd(index: stepIndex))
      stepIndex += 1
    }

    if stepIndex >= agent.maxSteps {
      onEvent?(.error("Exceeded maximum step limit (\(agent.maxSteps))"))
      throw AgentLoopError.maxStepsExceeded(limit: agent.maxSteps)
    }

    onEvent?(.finished)
    return finalText
  }

  // MARK: - Stream Accumulation

  /// Accumulated content from a single LLM response.
  struct AccumulatedResponse {
    var text: String = ""
    var thinking: String = ""
    var toolCalls: [AccumulatedToolCall] = []
  }

  /// A tool call accumulated from streaming deltas.
  struct AccumulatedToolCall {
    let id: String
    let name: String
    var arguments: String
  }

  /// Stream the LLM response and accumulate text, thinking, and tool calls.
  private func streamAndAccumulate(
    input: RuntimeInput,
    onEvent: AgentEventHandler?
  ) async throws -> AccumulatedResponse {
    let stream = try await runtime.stream(input)
    var result = AccumulatedResponse()

    /// Track tool calls by their real ID (e.g., "toolu_123").
    var toolCallsByRealID: [String: Int] = [:]
    /// Track tool calls by their stream index (e.g., "0", "1") for delta/end events.
    var toolCallsByStreamIndex: [Int: Int] = [:]
    /// Map stream index to real ID for resolving deltas.
    var streamIndexToRealID: [Int: String] = [:]

    for try await event in stream {
      switch event {
      case .textDelta(let delta):
        result.text += delta
        onEvent?(.textDelta(delta))

      case .thinkingDelta(let delta):
        result.thinking += delta
        onEvent?(.thinkingDelta(delta))

      case .toolCallStart(let id, let name):
        let arrayIndex = result.toolCalls.count
        result.toolCalls.append(AccumulatedToolCall(
          id: id, name: name, arguments: ""
        ))
        toolCallsByRealID[id] = arrayIndex
        onEvent?(.toolCallStart(id: id, name: name))

      case .toolCallDelta(let streamID, let delta):
        /// Try to resolve the stream ID to an array index.
        /// First try as real ID, then as numeric index.
        let arrayIndex: Int?
        if let idx = toolCallsByRealID[streamID] {
          arrayIndex = idx
        } else if let numericIndex = Int(streamID),
                  let idx = toolCallsByStreamIndex[numericIndex]
        {
          arrayIndex = idx
        } else {
          /// Fallback: assume sequential ordering and use numeric index directly.
          let numericIndex = Int(streamID) ?? 0
          if numericIndex < result.toolCalls.count {
            arrayIndex = numericIndex
            toolCallsByStreamIndex[numericIndex] = numericIndex
          } else {
            arrayIndex = nil
          }
        }

        if let idx = arrayIndex, idx < result.toolCalls.count {
          result.toolCalls[idx].arguments += delta
          let realID = result.toolCalls[idx].id
          onEvent?(.toolCallDelta(id: realID, argumentsDelta: delta))
        }

      case .toolCallEnd(let streamID):
        /// Resolve stream ID to array index same as delta.
        let arrayIndex: Int?
        if let idx = toolCallsByRealID[streamID] {
          arrayIndex = idx
        } else if let numericIndex = Int(streamID),
                  numericIndex < result.toolCalls.count
        {
          arrayIndex = numericIndex
        } else {
          arrayIndex = nil
        }

        if let idx = arrayIndex, idx < result.toolCalls.count {
          let call = result.toolCalls[idx]
          onEvent?(.toolCallComplete(
            id: call.id, name: call.name, arguments: call.arguments
          ))
        }

      case .usage(let input, let output):
        onEvent?(.usage(input: input, output: output))

      case .messageComplete:
        break

      case .error(let msg):
        onEvent?(.error(msg))
      }
    }

    return result
  }

  // MARK: - Tool Execution

  /// Execute a single tool call with permission checks and doom-loop detection.
  private func executeToolCall(
    call: AccumulatedToolCall,
    context: ToolContext,
    toolCallHistory: inout [ToolCallSignature: Int],
    onEvent: AgentEventHandler?
  ) async -> ToolResult {
    let signature = ToolCallSignature(toolID: call.name, arguments: call.arguments)
    toolCallHistory[signature, default: 0] += 1

    /// Doom-loop detection.
    if toolCallHistory[signature]! >= doomLoopThreshold {
      let output = "Detected repeated identical calls to '\(call.name)'. Stopping to prevent infinite loop."
      onEvent?(.toolResult(
        id: call.id, name: call.name, output: output, isError: true
      ))
      return ToolResult(output: output, isError: true)
    }

    /// Permission check.
    let toolPath = extractPath(from: call.arguments)
    do {
      let reply = try await context.permissions.check(
        tool: call.name, path: toolPath
      )

      if case .reject = reply {
        let output = "User rejected tool: \(call.name)"
        onEvent?(.toolResult(
          id: call.id, name: call.name, output: output, isError: true
        ))
        return ToolResult(output: output, isError: true)
      }

      if case .corrected(let feedback) = reply {
        let output = "User correction: \(feedback)"
        onEvent?(.toolResult(
          id: call.id, name: call.name, output: output, isError: true
        ))
        return ToolResult(output: output, isError: true)
      }
    } catch let error as PermissionError {
      let output: String
      switch error {
      case .denied(let tool, _):
        output = "Permission denied for tool: \(tool)"

      case .rejected(let tool, _):
        output = "User rejected tool: \(tool)"

      case .corrected(_, let feedback):
        output = "User correction: \(feedback)"
      }
      onEvent?(.toolResult(
        id: call.id, name: call.name, output: output, isError: true
      ))
      return ToolResult(output: output, isError: true)
    } catch {
      let output = "Permission error: \(error.localizedDescription)"
      onEvent?(.toolResult(
        id: call.id, name: call.name, output: output, isError: true
      ))
      return ToolResult(output: output, isError: true)
    }

    /// Look up and execute the tool.
    guard let tool = registry.tool(byID: call.name) else {
      let output = "Unknown tool: \(call.name)"
      onEvent?(.toolResult(
        id: call.id, name: call.name, output: output, isError: true
      ))
      return ToolResult(output: output, isError: true)
    }

    do {
      let args = try decodeArguments(call.arguments)
      let result = try await tool.execute(arguments: args, context: context)
      onEvent?(.toolResult(
        id: call.id, name: call.name,
        output: result.output, isError: result.isError
      ))
      return result
    } catch {
      let output = "Tool execution error: \(error.localizedDescription)"
      onEvent?(.toolResult(
        id: call.id, name: call.name, output: output, isError: true
      ))
      return ToolResult(output: output, isError: true)
    }
  }

  // MARK: - Helpers

  private func decodeArguments(_ json: String) throws -> [String: JSONValue] {
    guard let data = json.data(using: .utf8) else {
      return [:]
    }
    return try JSONDecoder().decode([String: JSONValue].self, from: data)
  }

  private func extractPath(from argumentsJSON: String) -> String? {
    guard let data = argumentsJSON.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return nil
    }
    return obj["file_path"] as? String
      ?? obj["path"] as? String
      ?? obj["command"] as? String
  }
}

/// Tracks repeated identical tool calls for doom-loop detection.
private struct ToolCallSignature: Hashable {
  let toolID: String
  let arguments: String
}
