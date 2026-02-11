import Foundation

/// Parses NDJSON lines from `opencode run --format json` into typed events.
///
/// Uses `JSONSerialization` (same approach as `StreamEventParser`) for
/// tolerance of unknown fields and flexible structure.
enum OpenCodeStreamEventParser {

  /// Parses a single NDJSON line into an `OpenCodeStreamEvent`.
  ///
  /// Returns a tuple of the parsed event and the top-level `sessionID`
  /// so the transport can extract it without the mapper needing to know.
  /// Returns `nil` for empty lines or unparseable content.
  static func parse(line: String) -> (event: OpenCodeStreamEvent, sessionID: String?)? {
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

    let sessionID = json["sessionID"] as? String
    let part = json["part"] as? [String: Any] ?? [:]

    switch type {
    case "step_start":
      return (parseStepStart(part), sessionID)

    case "text":
      return (parseText(part), sessionID)

    case "tool_use":
      return (parseToolUse(part), sessionID)

    case "step_finish":
      return (parseStepFinish(part), sessionID)

    default:
      return (.unknown, sessionID)
    }
  }

  // MARK: - Part Parsers

  private static func parseStepStart(_ part: [String: Any]) -> OpenCodeStreamEvent {
    let parsed = OpenCodeStepStartPart(
      id: part["id"] as? String ?? "",
      sessionID: part["sessionID"] as? String ?? "",
      messageID: part["messageID"] as? String ?? "",
      snapshot: part["snapshot"] as? String
    )
    return .stepStart(parsed)
  }

  private static func parseText(_ part: [String: Any]) -> OpenCodeStreamEvent {
    let parsed = OpenCodeTextPart(
      id: part["id"] as? String ?? "",
      sessionID: part["sessionID"] as? String ?? "",
      messageID: part["messageID"] as? String ?? "",
      text: part["text"] as? String ?? ""
    )
    return .text(parsed)
  }

  private static func parseToolUse(_ part: [String: Any]) -> OpenCodeStreamEvent {
    let state = part["state"] as? [String: Any] ?? [:]

    var inputDict: [String: String] = [:]
    if let rawInput = state["input"] as? [String: Any] {
      for (key, value) in rawInput {
        inputDict[key] = "\(value)"
      }
    }

    let parsed = OpenCodeToolUsePart(
      id: part["id"] as? String ?? "",
      sessionID: part["sessionID"] as? String ?? "",
      messageID: part["messageID"] as? String ?? "",
      callID: part["callID"] as? String ?? "",
      tool: part["tool"] as? String ?? "",
      status: state["status"] as? String ?? "",
      input: inputDict,
      output: state["output"] as? String ?? "",
      title: state["title"] as? String
    )
    return .toolUse(parsed)
  }

  private static func parseStepFinish(_ part: [String: Any]) -> OpenCodeStreamEvent {
    var tokens: OpenCodeTokens?
    if let tokensDict = part["tokens"] as? [String: Any] {
      let cache = tokensDict["cache"] as? [String: Any] ?? [:]
      tokens = OpenCodeTokens(
        input: tokensDict["input"] as? Int ?? 0,
        output: tokensDict["output"] as? Int ?? 0,
        reasoning: tokensDict["reasoning"] as? Int ?? 0,
        cacheRead: cache["read"] as? Int ?? 0,
        cacheWrite: cache["write"] as? Int ?? 0
      )
    }

    let parsed = OpenCodeStepFinishPart(
      id: part["id"] as? String ?? "",
      sessionID: part["sessionID"] as? String ?? "",
      messageID: part["messageID"] as? String ?? "",
      reason: part["reason"] as? String ?? "",
      cost: part["cost"] as? Double,
      tokens: tokens
    )
    return .stepFinish(parsed)
  }
}
