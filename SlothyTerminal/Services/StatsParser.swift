import Foundation

/// Represents a parsed usage update from agent output.
struct UsageUpdate {
  var tokensIn: Int?
  var tokensOut: Int?
  var totalTokens: Int?
  var cost: Double?
  var messageCount: Int?
  var contextWindowUsed: Int?
  var contextWindowLimit: Int?
}

/// Parses agent terminal output to extract usage statistics.
class StatsParser {
  static let shared = StatsParser()

  private init() {}

  /// Parses output from Claude CLI to extract usage information.
  /// Claude CLI may output stats in various formats including JSON status updates.
  func parseClaudeOutput(_ text: String) -> UsageUpdate? {
    var update = UsageUpdate()
    var hasUpdates = false

    /// Try to parse JSON status updates (Claude CLI outputs JSON for status).
    if let jsonUpdate = parseJSONStatus(text) {
      return jsonUpdate
    }

    /// Pattern: "Tokens: 1234 in / 567 out"
    if let (tokensIn, tokensOut) = matchTokensInOut(text) {
      update.tokensIn = tokensIn
      update.tokensOut = tokensOut
      update.totalTokens = tokensIn + tokensOut
      hasUpdates = true
    }

    /// Pattern: "Total tokens: 1234"
    if let total = matchPattern(text, pattern: "[Tt]otal\\s+[Tt]okens?:\\s*(\\d[\\d,]*)") {
      update.totalTokens = parseNumber(total)
      hasUpdates = true
    }

    /// Pattern: "Input: 1234 tokens" or "Input tokens: 1234"
    if let input = matchPattern(text, pattern: "[Ii]nput(?:\\s+[Tt]okens?)?:\\s*(\\d[\\d,]*)") {
      update.tokensIn = parseNumber(input)
      hasUpdates = true
    }

    /// Pattern: "Output: 567 tokens" or "Output tokens: 567"
    if let output = matchPattern(text, pattern: "[Oo]utput(?:\\s+[Tt]okens?)?:\\s*(\\d[\\d,]*)") {
      update.tokensOut = parseNumber(output)
      hasUpdates = true
    }

    /// Pattern: "Cost: $0.0123" or "Estimated cost: $0.0123"
    if let costStr = matchPattern(text, pattern: "[Cc]ost:\\s*\\$?([\\d.]+)") {
      update.cost = Double(costStr)
      hasUpdates = true
    }

    /// Pattern: "Context: 12345 / 200000" or "Context window: 12345/200000"
    if let (used, limit) = matchContextWindow(text) {
      update.contextWindowUsed = used
      update.contextWindowLimit = limit
      hasUpdates = true
    }

    /// Pattern: "Messages: 24" or "Message count: 24"
    if let messages = matchPattern(text, pattern: "[Mm]essages?(?:\\s+[Cc]ount)?:\\s*(\\d+)") {
      update.messageCount = Int(messages)
      hasUpdates = true
    }

    return hasUpdates ? update : nil
  }

  /// Parses output from GLM to extract usage information.
  func parseGLMOutput(_ text: String) -> UsageUpdate? {
    /// GLM may have different output format - implement when known.
    /// For now, try the same patterns as Claude.
    return parseClaudeOutput(text)
  }

  /// Attempts to parse JSON status updates from the output.
  private func parseJSONStatus(_ text: String) -> UsageUpdate? {
    /// Look for JSON objects in the text.
    guard let jsonPattern = try? NSRegularExpression(
      pattern: "\\{[^{}]*\"tokens?\"[^{}]*\\}",
      options: []
    ) else {
      return nil
    }

    let range = NSRange(text.startIndex..., in: text)
    guard let match = jsonPattern.firstMatch(in: text, options: [], range: range) else {
      return nil
    }

    guard let matchRange = Range(match.range, in: text) else {
      return nil
    }

    let jsonString = String(text[matchRange])
    guard let data = jsonString.data(using: .utf8) else {
      return nil
    }

    do {
      if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
        var update = UsageUpdate()
        var hasUpdates = false

        if let tokensIn = json["input_tokens"] as? Int ?? json["tokens_in"] as? Int {
          update.tokensIn = tokensIn
          hasUpdates = true
        }

        if let tokensOut = json["output_tokens"] as? Int ?? json["tokens_out"] as? Int {
          update.tokensOut = tokensOut
          hasUpdates = true
        }

        if let total = json["total_tokens"] as? Int ?? json["tokens"] as? Int {
          update.totalTokens = total
          hasUpdates = true
        }

        if let cost = json["cost"] as? Double {
          update.cost = cost
          hasUpdates = true
        }

        if let messages = json["messages"] as? Int ?? json["message_count"] as? Int {
          update.messageCount = messages
          hasUpdates = true
        }

        return hasUpdates ? update : nil
      }
    } catch {
      /// JSON parsing failed, return nil.
    }

    return nil
  }

  /// Matches a single capture group pattern.
  private func matchPattern(_ text: String, pattern: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
      return nil
    }

    let range = NSRange(text.startIndex..., in: text)
    guard let match = regex.firstMatch(in: text, options: [], range: range),
          match.numberOfRanges >= 2,
          let captureRange = Range(match.range(at: 1), in: text)
    else {
      return nil
    }

    return String(text[captureRange])
  }

  /// Matches "Tokens: X in / Y out" pattern.
  private func matchTokensInOut(_ text: String) -> (Int, Int)? {
    let pattern = "[Tt]okens?:\\s*(\\d[\\d,]*)\\s*in\\s*/\\s*(\\d[\\d,]*)\\s*out"
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
      return nil
    }

    let range = NSRange(text.startIndex..., in: text)
    guard let match = regex.firstMatch(in: text, options: [], range: range),
          match.numberOfRanges >= 3,
          let inRange = Range(match.range(at: 1), in: text),
          let outRange = Range(match.range(at: 2), in: text),
          let inTokens = parseNumber(String(text[inRange])),
          let outTokens = parseNumber(String(text[outRange]))
    else {
      return nil
    }

    return (inTokens, outTokens)
  }

  /// Matches "Context: X / Y" pattern.
  private func matchContextWindow(_ text: String) -> (Int, Int)? {
    let pattern = "[Cc]ontext(?:\\s+[Ww]indow)?:\\s*(\\d[\\d,]*)\\s*/\\s*(\\d[\\d,]*)"
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
      return nil
    }

    let range = NSRange(text.startIndex..., in: text)
    guard let match = regex.firstMatch(in: text, options: [], range: range),
          match.numberOfRanges >= 3,
          let usedRange = Range(match.range(at: 1), in: text),
          let limitRange = Range(match.range(at: 2), in: text),
          let used = parseNumber(String(text[usedRange])),
          let limit = parseNumber(String(text[limitRange]))
    else {
      return nil
    }

    return (used, limit)
  }

  /// Parses a number string, removing commas.
  private func parseNumber(_ string: String) -> Int? {
    let cleanedString = string.replacingOccurrences(of: ",", with: "")
    return Int(cleanedString)
  }
}

// MARK: - Number Formatting Extension

extension Int {
  /// Formats the integer with thousands separators.
  var formatted: String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.groupingSeparator = ","
    return formatter.string(from: NSNumber(value: self)) ?? "\(self)"
  }
}

extension Double {
  /// Formats as currency (USD).
  var formattedAsCurrency: String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = "USD"
    formatter.minimumFractionDigits = 4
    formatter.maximumFractionDigits = 4
    return formatter.string(from: NSNumber(value: self)) ?? "$\(self)"
  }
}
