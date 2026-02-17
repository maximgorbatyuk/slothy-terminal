import Foundation

/// Top-level event types from `opencode run --format json` NDJSON output.
///
/// Each line has `type`, `timestamp`, `sessionID`, and a `part` object.
/// The event type determines which fields are present in `part`.
enum OpenCodeStreamEvent {
  case stepStart(OpenCodeStepStartPart)
  case text(OpenCodeTextPart)
  case toolUse(OpenCodeToolUsePart)
  case stepFinish(OpenCodeStepFinishPart)
  case error(OpenCodeErrorPart)
  case unknown
}

/// Part payload for `step_start` events.
struct OpenCodeStepStartPart {
  let id: String
  let sessionID: String
  let messageID: String
  let snapshot: String?
}

/// Part payload for `text` events.
struct OpenCodeTextPart {
  let id: String
  let sessionID: String
  let messageID: String
  let text: String
}

/// Part payload for `tool_use` events.
///
/// Unlike Claude where tool use streams incrementally, OpenCode delivers
/// complete tool invocations (input + output + status) in a single event.
struct OpenCodeToolUsePart {
  let id: String
  let sessionID: String
  let messageID: String
  let callID: String
  let tool: String
  let status: String
  let input: [String: String]
  let output: String
  let title: String?
}

/// Part payload for `step_finish` events.
struct OpenCodeStepFinishPart {
  let id: String
  let sessionID: String
  let messageID: String
  let reason: String
  let cost: Double?
  let tokens: OpenCodeTokens?
}

/// Payload for top-level `error` events.
struct OpenCodeErrorPart {
  let name: String
  let message: String
}

/// Token usage counters from a `step_finish` event.
struct OpenCodeTokens {
  let input: Int
  let output: Int
  let reasoning: Int
  let cacheRead: Int
  let cacheWrite: Int
}
