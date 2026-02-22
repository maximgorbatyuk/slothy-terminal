import Foundation

/// A single parsed Server-Sent Events frame.
struct SSEEvent: Sendable {
  /// The `event:` field, if present (e.g. "message_start", "content_block_delta").
  let event: String?

  /// The `data:` field content. Multiple `data:` lines are joined with newlines.
  let data: String
}

/// Incremental parser for the `text/event-stream` format (Server-Sent Events).
///
/// Handles:
/// - Multi-line `data:` fields (joined by newlines)
/// - `event:` fields
/// - Empty-line delimiters between events
/// - Partial chunks (buffered across feed calls)
/// - Comment lines (prefixed with `:`)
///
/// Usage:
/// ```
/// let parser = SSEParser()
/// for chunk in incomingBytes {
///   let events = parser.feed(chunk)
///   for event in events { ... }
/// }
/// ```
final class SSEParser: @unchecked Sendable {

  /// Accumulated text that hasn't formed a complete event yet.
  private var buffer = ""

  /// Current event being assembled.
  private var currentEvent: String?
  private var currentData: [String] = []

  init() {}

  /// Feed a chunk of text data into the parser.
  ///
  /// Returns zero or more complete SSE events parsed from the buffer.
  func feed(_ chunk: String) -> [SSEEvent] {
    buffer += chunk
    var events: [SSEEvent] = []

    while let newlineRange = buffer.range(of: "\n") {
      let line = String(buffer[buffer.startIndex..<newlineRange.lowerBound])
      buffer = String(buffer[newlineRange.upperBound...])

      if line.isEmpty {
        /// Empty line = event delimiter.
        if !currentData.isEmpty {
          let data = currentData.joined(separator: "\n")
          events.append(SSEEvent(event: currentEvent, data: data))
        }
        currentEvent = nil
        currentData = []
        continue
      }

      if line.hasPrefix(":") {
        /// Comment line — skip.
        continue
      }

      if line.hasPrefix("event:") {
        currentEvent = line
          .dropFirst("event:".count)
          .trimmingCharacters(in: .whitespaces)
        continue
      }

      if line.hasPrefix("data:") {
        let value = line
          .dropFirst("data:".count)
          .trimmingCharacters(in: .init(charactersIn: " "))
        currentData.append(String(value))
        continue
      }

      if line.hasPrefix("id:") || line.hasPrefix("retry:") {
        /// Standard SSE fields we don't need — skip.
        continue
      }
    }

    return events
  }

  /// Reset the parser state, discarding any buffered data.
  func reset() {
    buffer = ""
    currentEvent = nil
    currentData = []
  }
}
