import Foundation

/// Rough token count estimation for context budget management.
///
/// Uses the `characters / 4` heuristic which is a reasonable approximation
/// for English text across most tokenizers. Not precise enough for billing,
/// but sufficient for deciding when to trigger compaction.
enum TokenEstimator {

  /// Estimates the token count for a string.
  static func estimate(_ text: String) -> Int {
    max(1, text.count / 4)
  }

  /// Estimates the total token count for a message array.
  ///
  /// Walks the JSON structure and sums estimates for all string values,
  /// plus a small overhead per message for role/structural tokens.
  static func estimate(messages: [[String: JSONValue]]) -> Int {
    var total = 0

    for message in messages {
      /// ~4 tokens overhead per message (role, delimiters).
      total += 4
      total += estimateValue(message)
    }

    return total
  }

  // MARK: - Private

  private static func estimateValue(_ dict: [String: JSONValue]) -> Int {
    var total = 0

    for (key, value) in dict {
      total += estimate(key)
      total += estimateJSONValue(value)
    }

    return total
  }

  private static func estimateJSONValue(_ value: JSONValue) -> Int {
    switch value {
    case .string(let s):
      return estimate(s)

    case .number:
      return 1

    case .bool:
      return 1

    case .null:
      return 1

    case .array(let arr):
      return arr.reduce(0) { $0 + estimateJSONValue($1) }

    case .object(let obj):
      return estimateValue(obj)
    }
  }
}
