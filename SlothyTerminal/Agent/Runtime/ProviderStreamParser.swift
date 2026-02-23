import Foundation

/// Normalized events produced by parsing provider-specific SSE streams.
///
/// Named `ProviderStreamEvent` to avoid collision with the existing
/// `StreamEvent` in the Chat/Parser layer.
enum ProviderStreamEvent: Sendable {
  /// A text content delta.
  case textDelta(String)

  /// A thinking/reasoning content delta.
  case thinkingDelta(String)

  /// A tool use block has started.
  case toolCallStart(id: String, name: String)

  /// Incremental JSON arguments for a tool call.
  case toolCallDelta(id: String, argumentsDelta: String)

  /// A tool use block is complete.
  case toolCallEnd(id: String)

  /// Token usage information (may arrive mid-stream or at end).
  case usage(input: Int, output: Int)

  /// The message is complete (stop reason received).
  case messageComplete(stopReason: String?)

  /// An error occurred during parsing.
  case error(String)
}

/// Parses provider-specific SSE data strings into normalized `ProviderStreamEvent`s.
///
/// Handles two provider formats:
/// - **Anthropic**: `message_start`, `content_block_start/delta/stop`, `message_delta`, `message_stop`
/// - **OpenAI**: `choices[0].delta` with `content`, `tool_calls`, `finish_reason`
///
/// For Anthropic, use an instance to track per-block tool call IDs.
/// For OpenAI, the static method is sufficient (IDs come in each delta).
final class ProviderStreamParser: @unchecked Sendable {

  /// Maps Anthropic content block index → real tool call ID.
  /// Populated on `content_block_start` for tool_use blocks,
  /// consulted on `content_block_delta` and `content_block_stop`.
  private var toolCallIDByIndex: [Int: String] = [:]

  /// Resets parser state for a new message stream.
  func reset() {
    toolCallIDByIndex = [:]
  }

  /// Parse an SSE event from an Anthropic Messages API stream.
  func parseAnthropic(event: SSEEvent) -> [ProviderStreamEvent] {
    guard let json = Self.parseJSON(event.data) else {
      return []
    }

    let eventType = event.event ?? (json["type"] as? String ?? "")

    switch eventType {
    case "message_start":
      if let message = json["message"] as? [String: Any],
         let usage = message["usage"] as? [String: Any],
         let input = usage["input_tokens"] as? Int
      {
        return [.usage(input: input, output: 0)]
      }
      return []

    case "content_block_start":
      guard let block = json["content_block"] as? [String: Any],
            let blockType = block["type"] as? String
      else {
        return []
      }

      if blockType == "tool_use" {
        let id = block["id"] as? String ?? ""
        let name = block["name"] as? String ?? ""
        let index = json["index"] as? Int ?? 0
        toolCallIDByIndex[index] = id
        return [.toolCallStart(id: id, name: name)]
      }
      return []

    case "content_block_delta":
      guard let delta = json["delta"] as? [String: Any],
            let deltaType = delta["type"] as? String
      else {
        return []
      }

      switch deltaType {
      case "text_delta":
        if let text = delta["text"] as? String {
          return [.textDelta(text)]
        }

      case "thinking_delta":
        if let thinking = delta["thinking"] as? String {
          return [.thinkingDelta(thinking)]
        }

      case "input_json_delta":
        if let partial = delta["partial_json"] as? String {
          let index = json["index"] as? Int ?? 0
          let realID = toolCallIDByIndex[index] ?? "\(index)"
          return [.toolCallDelta(id: realID, argumentsDelta: partial)]
        }

      default:
        break
      }
      return []

    case "content_block_stop":
      let index = json["index"] as? Int ?? 0
      let realID = toolCallIDByIndex[index] ?? "\(index)"
      return [.toolCallEnd(id: realID)]

    case "message_delta":
      var events: [ProviderStreamEvent] = []

      if let delta = json["delta"] as? [String: Any] {
        let stopReason = delta["stop_reason"] as? String
        if stopReason != nil {
          events.append(.messageComplete(stopReason: stopReason))
        }
      }

      if let usage = json["usage"] as? [String: Any],
         let output = usage["output_tokens"] as? Int
      {
        events.append(.usage(input: 0, output: output))
      }

      return events

    case "message_stop":
      return [.messageComplete(stopReason: nil)]

    case "error":
      let errorMsg = (json["error"] as? [String: Any])?["message"] as? String
        ?? "Unknown API error"
      return [.error(errorMsg)]

    default:
      return []
    }
  }

  /// Parse an SSE event from an OpenAI Chat Completions API stream.
  static func parseOpenAI(event: SSEEvent) -> [ProviderStreamEvent] {
    guard let json = parseJSON(event.data) else {
      return []
    }

    var events: [ProviderStreamEvent] = []

    /// Check for error response.
    if let error = json["error"] as? [String: Any] {
      let msg = error["message"] as? String ?? "Unknown API error"
      return [.error(msg)]
    }

    guard let choices = json["choices"] as? [[String: Any]],
          let choice = choices.first
    else {
      /// Check for usage-only events (OpenAI stream_options).
      if let usage = json["usage"] as? [String: Any] {
        let input = usage["prompt_tokens"] as? Int ?? 0
        let output = usage["completion_tokens"] as? Int ?? 0
        events.append(.usage(input: input, output: output))
      }
      return events
    }

    let delta = choice["delta"] as? [String: Any] ?? [:]
    let finishReason = choice["finish_reason"] as? String

    /// Text content.
    if let content = delta["content"] as? String, !content.isEmpty {
      events.append(.textDelta(content))
    }

    /// Reasoning content (OpenAI o-series models).
    if let reasoning = delta["reasoning_content"] as? String, !reasoning.isEmpty {
      events.append(.thinkingDelta(reasoning))
    }

    /// Tool calls.
    if let toolCalls = delta["tool_calls"] as? [[String: Any]] {
      for tc in toolCalls {
        let index = tc["index"] as? Int ?? 0
        let id = tc["id"] as? String

        if let function = tc["function"] as? [String: Any] {
          /// If `id` is present, this is a new tool call.
          if let id {
            let name = function["name"] as? String ?? ""
            events.append(.toolCallStart(id: id, name: name))
          }

          /// Argument deltas.
          if let args = function["arguments"] as? String, !args.isEmpty {
            let callID = id ?? "tool_\(index)"
            events.append(.toolCallDelta(id: callID, argumentsDelta: args))
          }
        }
      }
    }

    /// Finish reason.
    if let reason = finishReason {
      events.append(.messageComplete(stopReason: reason))
    }

    /// Usage in the final chunk.
    if let usage = json["usage"] as? [String: Any] {
      let input = usage["prompt_tokens"] as? Int ?? 0
      let output = usage["completion_tokens"] as? Int ?? 0
      events.append(.usage(input: input, output: output))
    }

    return events
  }

  /// Parse an SSE event from the OpenAI Responses API stream
  /// (used by Codex subscription endpoint).
  ///
  /// Event types:
  /// - `response.output_text.delta` → textDelta
  /// - `response.function_call_arguments.delta` → toolCallDelta
  /// - `response.output_item.added` (function_call) → toolCallStart
  /// - `response.output_item.done` (function_call) → toolCallEnd
  /// - `response.completed` → usage + messageComplete
  /// - `response.reasoning_summary_text.delta` → thinkingDelta
  static func parseCodexResponses(event: SSEEvent) -> [ProviderStreamEvent] {
    guard let json = parseJSON(event.data) else {
      return []
    }

    let eventType = event.event ?? (json["type"] as? String ?? "")

    switch eventType {
    case "response.output_text.delta":
      if let delta = json["delta"] as? String {
        return [.textDelta(delta)]
      }
      return []

    case "response.reasoning_summary_text.delta":
      if let delta = json["delta"] as? String {
        return [.thinkingDelta(delta)]
      }
      return []

    case "response.output_item.added":
      guard let item = json["item"] as? [String: Any],
            let itemType = item["type"] as? String
      else {
        return []
      }

      if itemType == "function_call" {
        let callID = item["call_id"] as? String ?? item["id"] as? String ?? ""
        let name = item["name"] as? String ?? ""
        return [.toolCallStart(id: callID, name: name)]
      }
      return []

    case "response.function_call_arguments.delta":
      let callID = json["call_id"] as? String ?? json["item_id"] as? String ?? ""
      let delta = json["delta"] as? String ?? ""
      if !delta.isEmpty {
        return [.toolCallDelta(id: callID, argumentsDelta: delta)]
      }
      return []

    case "response.function_call_arguments.done":
      let callID = json["call_id"] as? String ?? json["item_id"] as? String ?? ""
      return [.toolCallEnd(id: callID)]

    case "response.output_item.done":
      guard let item = json["item"] as? [String: Any],
            let itemType = item["type"] as? String
      else {
        return []
      }

      if itemType == "function_call" {
        let callID = item["call_id"] as? String ?? item["id"] as? String ?? ""
        return [.toolCallEnd(id: callID)]
      }
      return []

    case "response.completed":
      var events: [ProviderStreamEvent] = []

      if let response = json["response"] as? [String: Any] {
        if let usage = response["usage"] as? [String: Any] {
          let input = usage["input_tokens"] as? Int ?? 0
          let output = usage["output_tokens"] as? Int ?? 0
          events.append(.usage(input: input, output: output))
        }

        let status = response["status"] as? String
        events.append(.messageComplete(stopReason: status))
      } else {
        events.append(.messageComplete(stopReason: nil))
      }

      return events

    case "response.failed":
      if let response = json["response"] as? [String: Any],
         let error = response["error"] as? [String: Any]
      {
        let msg = error["message"] as? String ?? "Unknown Codex API error"
        return [.error(msg)]
      }
      return [.error("Codex API request failed")]

    case "error":
      let msg = (json["error"] as? [String: Any])?["message"] as? String
        ?? json["detail"] as? String
        ?? "Unknown API error"
      return [.error(msg)]

    default:
      return []
    }
  }

  // MARK: - Private

  fileprivate static func parseJSON(_ string: String) -> [String: Any]? {
    guard let data = string.data(using: .utf8) else {
      return nil
    }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
  }
}
