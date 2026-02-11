import Foundation

/// Parses NDJSON lines from Claude CLI's stream-json output into StreamEvent values.
enum StreamEventParser {

  /// Parses a single NDJSON line into a StreamEvent.
  /// Returns nil for empty lines or unparseable content.
  static func parse(line: String) -> StreamEvent? {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !trimmed.isEmpty else {
      return nil
    }

    guard let data = trimmed.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return nil
    }

    guard let type = json["type"] as? String else {
      return nil
    }

    switch type {
    case "stream_event":
      /// Unwrap the nested event from the stream_event wrapper.
      guard let innerEvent = json["event"] as? [String: Any] else {
        return .unknown
      }

      return dispatch(innerEvent)

    default:
      return dispatch(json)
    }
  }

  /// Dispatches a JSON object to the appropriate parser based on its type field.
  private static func dispatch(_ json: [String: Any]) -> StreamEvent? {
    guard let type = json["type"] as? String else {
      return nil
    }

    switch type {
    case "system":
      return parseSystem(json)

    case "assistant":
      return parseAssistant(json)

    case "user":
      return parseUserToolResult(json)

    case "message_start":
      return parseMessageStart(json)

    case "content_block_start":
      return parseContentBlockStart(json)

    case "content_block_delta":
      return parseContentBlockDelta(json)

    case "content_block_stop":
      return parseContentBlockStop(json)

    case "message_delta":
      return parseMessageDelta(json)

    case "message_stop":
      return .messageStop

    case "result":
      return parseResult(json)

    default:
      return .unknown
    }
  }

  // MARK: - Persistent Mode Parsers

  private static func parseSystem(_ json: [String: Any]) -> StreamEvent {
    let sessionId = json["session_id"] as? String ?? ""
    return .system(sessionId: sessionId)
  }

  private static func parseAssistant(_ json: [String: Any]) -> StreamEvent {
    var blocks: [AssistantContentBlock] = []
    var inputTokens = 0
    var outputTokens = 0

    if let message = json["message"] as? [String: Any] {
      if let usage = message["usage"] as? [String: Any] {
        inputTokens = usage["input_tokens"] as? Int ?? 0
        outputTokens = usage["output_tokens"] as? Int ?? 0

        /// Include cached tokens in input count.
        inputTokens += usage["cache_read_input_tokens"] as? Int ?? 0
        inputTokens += usage["cache_creation_input_tokens"] as? Int ?? 0
      }

      if let content = message["content"] as? [[String: Any]] {
        for item in content {
          let blockType = item["type"] as? String ?? "text"
          var block = AssistantContentBlock(type: blockType, text: "")

          switch blockType {
          case "text":
            block.text = item["text"] as? String ?? ""

          case "thinking":
            block.text = item["thinking"] as? String ?? ""

          case "tool_use":
            block.id = item["id"] as? String
            block.name = item["name"] as? String

            if let input = item["input"] {
              if let inputDict = input as? [String: Any],
                 let inputData = try? JSONSerialization.data(withJSONObject: inputDict, options: [.fragmentsAllowed]),
                 let inputStr = String(data: inputData, encoding: .utf8)
              {
                block.input = inputStr
              } else if let inputStr = input as? String {
                block.input = inputStr
              }
            }

          case "tool_result":
            block.id = item["tool_use_id"] as? String

            if let content = item["content"] as? String {
              block.text = content
            } else if let contentArray = item["content"] as? [[String: Any]] {
              let texts = contentArray.compactMap { $0["text"] as? String }
              block.text = texts.joined(separator: "\n")
            }

          default:
            break
          }

          blocks.append(block)
        }
      }
    }

    return .assistant(content: blocks, inputTokens: inputTokens, outputTokens: outputTokens)
  }

  // MARK: - Per-Message Streaming Parsers

  private static func parseMessageStart(_ json: [String: Any]) -> StreamEvent {
    var inputTokens = 0

    if let message = json["message"] as? [String: Any],
       let usage = message["usage"] as? [String: Any],
       let tokens = usage["input_tokens"] as? Int
    {
      inputTokens = tokens
    }

    return .messageStart(inputTokens: inputTokens)
  }

  private static func parseContentBlockStart(_ json: [String: Any]) -> StreamEvent {
    let index = json["index"] as? Int ?? 0
    var blockType = "text"
    var id: String?
    var name: String?

    if let contentBlock = json["content_block"] as? [String: Any] {
      blockType = contentBlock["type"] as? String ?? "text"
      id = contentBlock["id"] as? String
      name = contentBlock["name"] as? String
    }

    return .contentBlockStart(index: index, blockType: blockType, id: id, name: name)
  }

  private static func parseContentBlockDelta(_ json: [String: Any]) -> StreamEvent {
    let index = json["index"] as? Int ?? 0
    var deltaType = "text_delta"
    var text = ""

    if let delta = json["delta"] as? [String: Any] {
      deltaType = delta["type"] as? String ?? "text_delta"
      text = delta["text"] as? String ?? delta["partial_json"] as? String ?? ""
    }

    return .contentBlockDelta(index: index, deltaType: deltaType, text: text)
  }

  private static func parseContentBlockStop(_ json: [String: Any]) -> StreamEvent {
    let index = json["index"] as? Int ?? 0
    return .contentBlockStop(index: index)
  }

  private static func parseMessageDelta(_ json: [String: Any]) -> StreamEvent {
    var stopReason: String?
    var outputTokens = 0

    if let delta = json["delta"] as? [String: Any] {
      stopReason = delta["stop_reason"] as? String
    }

    if let usage = json["usage"] as? [String: Any] {
      outputTokens = usage["output_tokens"] as? Int ?? 0
    }

    return .messageDelta(stopReason: stopReason, outputTokens: outputTokens)
  }

  private static func parseResult(_ json: [String: Any]) -> StreamEvent {
    var text = ""
    var inputTokens = 0
    var outputTokens = 0

    if let result = json["result"] as? String {
      text = result
    }

    if let usage = json["usage"] as? [String: Any] {
      inputTokens = usage["input_tokens"] as? Int ?? 0
      outputTokens = usage["output_tokens"] as? Int ?? 0

      inputTokens += usage["cache_read_input_tokens"] as? Int ?? 0
      inputTokens += usage["cache_creation_input_tokens"] as? Int ?? 0
    }

    return .result(text: text, inputTokens: inputTokens, outputTokens: outputTokens)
  }

  private static func parseUserToolResult(_ json: [String: Any]) -> StreamEvent? {
    guard let message = json["message"] as? [String: Any],
          let content = message["content"] as? [[String: Any]]
    else {
      return .unknown
    }

    for item in content {
      guard (item["type"] as? String) == "tool_result" else {
        continue
      }

      let toolUseId = item["tool_use_id"] as? String ?? ""
      let isError = item["is_error"] as? Bool ?? false

      if let resultText = item["content"] as? String {
        return .userToolResult(toolUseId: toolUseId, content: resultText, isError: isError)
      }

      if let contentArray = item["content"] as? [[String: Any]] {
        let texts = contentArray.compactMap { $0["text"] as? String }
        return .userToolResult(
          toolUseId: toolUseId,
          content: texts.joined(separator: "\n"),
          isError: isError
        )
      }

      return .userToolResult(toolUseId: toolUseId, content: "", isError: isError)
    }

    return .unknown
  }
}
