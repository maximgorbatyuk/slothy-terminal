import Foundation

/// Manages context window budget by pruning old tool results when
/// the conversation exceeds a token threshold.
///
/// Compaction strategy:
/// 1. Estimate total tokens in the message history.
/// 2. If under threshold → no action.
/// 3. If over → prune tool result content from oldest messages first,
///    replacing long outputs with a truncation marker.
/// 4. Preserve the most recent N messages untouched.
///
/// This is a lightweight approach that avoids a separate LLM call.
/// A future enhancement could use the `.compaction` agent definition
/// to generate a summary of pruned content.
enum ContextCompactor {

  /// Default token budget as a fraction of the model's output limit.
  /// Context window is typically 4-8x the output limit, so we use
  /// a conservative multiplier.
  static let defaultContextMultiplier = 4

  /// Minimum number of recent messages to always preserve fully.
  static let defaultMinPreserved = 6

  /// Maximum length of a tool result before it gets truncated during compaction.
  static let maxToolResultLength = 500

  /// Checks whether compaction is needed and prunes if so.
  ///
  /// - Parameters:
  ///   - messages: The mutable message history.
  ///   - model: The model descriptor (used for budget calculation).
  ///   - contextBudget: Optional explicit token budget. If nil, derived from model.
  ///   - minPreserved: Number of recent messages to never prune.
  /// - Returns: `true` if compaction was performed.
  @discardableResult
  static func compactIfNeeded(
    messages: inout [[String: JSONValue]],
    model: ModelDescriptor,
    contextBudget: Int? = nil,
    minPreserved: Int = defaultMinPreserved
  ) -> Bool {
    let budget = contextBudget ?? (model.outputLimit * defaultContextMultiplier)
    let estimated = TokenEstimator.estimate(messages: messages)

    guard estimated > budget else {
      return false
    }

    prune(
      messages: &messages,
      budget: budget,
      minPreserved: minPreserved
    )
    return true
  }

  // MARK: - Private

  /// Prunes tool result content from oldest messages until under budget.
  private static func prune(
    messages: inout [[String: JSONValue]],
    budget: Int,
    minPreserved: Int
  ) {
    let preserveFrom = max(0, messages.count - minPreserved)

    /// Walk from oldest to newest, skipping preserved tail.
    for i in 0..<preserveFrom {
      guard TokenEstimator.estimate(messages: messages) > budget else {
        break
      }

      messages[i] = pruneMessage(messages[i])
    }
  }

  /// Truncates long tool result content in a single message.
  private static func pruneMessage(
    _ message: [String: JSONValue]
  ) -> [String: JSONValue] {
    guard case .array(let content) = message["content"] else {
      return message
    }

    let pruned = content.map { block -> JSONValue in
      guard case .object(var obj) = block else {
        return block
      }

      /// Prune tool_result content.
      if case .string(let type) = obj["type"],
         type == "tool_result",
         case .string(let resultContent) = obj["content"],
         resultContent.count > maxToolResultLength
      {
        let truncated = String(resultContent.prefix(maxToolResultLength))
          + "\n... [truncated by compaction]"
        obj["content"] = .string(truncated)
        return .object(obj)
      }

      /// Prune long text blocks in assistant messages.
      if case .string(let type) = obj["type"],
         type == "text",
         case .string(let text) = obj["text"],
         text.count > maxToolResultLength * 2
      {
        let truncated = String(text.prefix(maxToolResultLength * 2))
          + "\n... [truncated by compaction]"
        obj["text"] = .string(truncated)
        return .object(obj)
      }

      return block
    }

    var result = message
    result["content"] = .array(pruned)
    return result
  }
}
