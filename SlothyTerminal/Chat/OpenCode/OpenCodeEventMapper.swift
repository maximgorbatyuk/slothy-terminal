import Foundation

/// Mutable context for tracking block state across mapper calls within a turn.
///
/// Reset on each `stepStart`. The transport owns one instance and passes
/// it by reference to each `map()` call.
struct OpenCodeMapperContext {
  /// Next available content block index.
  var blockIndex: Int = 0

  /// Whether a text content block is currently open (started but not stopped).
  var textBlockOpen: Bool = false
}

/// Maps `OpenCodeStreamEvent` values to existing `StreamEvent` values
/// so the `ChatSessionEngine` can process them without modification.
///
/// Key difference from Claude: OpenCode tool use events arrive **complete**
/// (input + output + status in one event), so the mapper emits the full
/// sequence (`contentBlockStart` → `contentBlockDelta` → `contentBlockStop`
/// → `userToolResult`) at once.
///
/// Text events require explicit `contentBlockStart` / `contentBlockStop`
/// bracketing so the engine creates the block entry before appending deltas.
enum OpenCodeEventMapper {

  /// Maps an OpenCode event to zero or more `StreamEvent` values.
  static func map(
    _ event: OpenCodeStreamEvent,
    context: inout OpenCodeMapperContext
  ) -> [StreamEvent] {
    switch event {
    case .stepStart:
      context = OpenCodeMapperContext()
      return [.messageStart(inputTokens: 0)]

    case .text(let part):
      return mapText(part, context: &context)

    case .toolUse(let part):
      return mapToolUse(part, context: &context)

    case .stepFinish(let part):
      return mapStepFinish(part, context: &context)

    case .unknown:
      return []
    }
  }

  // MARK: - Event mappers

  private static func mapText(
    _ part: OpenCodeTextPart,
    context: inout OpenCodeMapperContext
  ) -> [StreamEvent] {
    var events: [StreamEvent] = []

    /// Open a text block if one isn't already open.
    if !context.textBlockOpen {
      events.append(.contentBlockStart(
        index: context.blockIndex,
        blockType: "text",
        id: nil,
        name: nil
      ))
      context.textBlockOpen = true
    }

    events.append(.contentBlockDelta(
      index: context.blockIndex,
      deltaType: "text_delta",
      text: part.text
    ))

    return events
  }

  private static func mapToolUse(
    _ part: OpenCodeToolUsePart,
    context: inout OpenCodeMapperContext
  ) -> [StreamEvent] {
    var events: [StreamEvent] = []

    /// Close any open text block before starting tool use.
    if context.textBlockOpen {
      events.append(.contentBlockStop(index: context.blockIndex))
      context.blockIndex += 1
      context.textBlockOpen = false
    }

    let toolIndex = context.blockIndex
    context.blockIndex += 1

    let inputJSON = serializeInput(part.input)

    events.append(contentsOf: [
      .contentBlockStart(
        index: toolIndex,
        blockType: "tool_use",
        id: part.callID,
        name: part.tool
      ),
      .contentBlockDelta(
        index: toolIndex,
        deltaType: "input_json_delta",
        text: inputJSON
      ),
      .contentBlockStop(index: toolIndex),
      .userToolResult(
        toolUseId: part.callID,
        content: part.output,
        isError: part.status != "completed"
      ),
    ])

    /// The engine's appendToolResult adds one more element to contentBlocks.
    /// Advance blockIndex past it so subsequent blocks don't collide.
    context.blockIndex += 1

    return events
  }

  private static func mapStepFinish(
    _ part: OpenCodeStepFinishPart,
    context: inout OpenCodeMapperContext
  ) -> [StreamEvent] {
    var events: [StreamEvent] = []

    /// Close any open text block.
    if context.textBlockOpen {
      events.append(.contentBlockStop(index: context.blockIndex))
      context.blockIndex += 1
      context.textBlockOpen = false
    }

    let inputTokens = totalInputTokens(from: part.tokens)
    let outputTokens = part.tokens?.output ?? 0

    if part.reason == "stop" {
      events.append(.result(
        text: "",
        inputTokens: inputTokens,
        outputTokens: outputTokens
      ))
    } else {
      /// Intermediate finish (e.g. "tool-calls") — not the final result.
      events.append(.messageStop)
    }

    return events
  }

  // MARK: - Private helpers

  private static func serializeInput(_ input: [String: String]) -> String {
    guard !input.isEmpty,
          let data = try? JSONSerialization.data(withJSONObject: input, options: [.fragmentsAllowed]),
          let str = String(data: data, encoding: .utf8)
    else {
      return "{}"
    }

    return str
  }

  private static func totalInputTokens(from tokens: OpenCodeTokens?) -> Int {
    guard let tokens else {
      return 0
    }

    return tokens.input + tokens.cacheRead + tokens.cacheWrite
  }
}
