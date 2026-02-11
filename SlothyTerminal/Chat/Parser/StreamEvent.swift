import Foundation

/// Token usage information from stream events.
struct StreamUsage {
  var inputTokens: Int
  var outputTokens: Int
}

/// A content block from an assistant message.
struct AssistantContentBlock {
  var type: String
  var text: String
  var id: String?
  var name: String?
  var input: String?
}

/// A parsed streaming event from Claude CLI's NDJSON output.
enum StreamEvent {
  /// Per-message streaming events (used in non-persistent mode).
  case messageStart(inputTokens: Int)
  case contentBlockStart(index: Int, blockType: String, id: String?, name: String?)
  case contentBlockDelta(index: Int, deltaType: String, text: String)
  case contentBlockStop(index: Int)
  case messageDelta(stopReason: String?, outputTokens: Int)
  case messageStop

  /// Persistent-mode events.
  case system(sessionId: String)
  case userToolResult(toolUseId: String, content: String, isError: Bool)
  case assistant(content: [AssistantContentBlock], inputTokens: Int, outputTokens: Int)
  case result(text: String, inputTokens: Int, outputTokens: Int)

  case unknown
}
