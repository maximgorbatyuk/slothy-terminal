import Foundation

/// Splits long messages into chunks that fit Telegram's 4096-character limit.
enum TelegramMessageChunker {
  /// Maximum message length allowed by Telegram.
  static let maxLength = 4096

  /// Splits text into chunks, preferring line breaks as split points.
  static func chunk(_ text: String) -> [String] {
    guard text.count > maxLength else {
      return [text]
    }

    var chunks: [String] = []
    var remaining = text[text.startIndex...]

    while !remaining.isEmpty {
      if remaining.count <= maxLength {
        chunks.append(String(remaining))
        break
      }

      let endIndex = remaining.index(remaining.startIndex, offsetBy: maxLength)
      let window = remaining[remaining.startIndex..<endIndex]

      /// Try to find a newline to split at.
      if let newlineIndex = window.lastIndex(of: "\n") {
        let splitIndex = remaining.index(after: newlineIndex)
        chunks.append(String(remaining[remaining.startIndex..<splitIndex]))
        remaining = remaining[splitIndex...]
      } else {
        /// No newline found; split at the limit.
        chunks.append(String(window))
        remaining = remaining[endIndex...]
      }
    }

    return chunks
  }
}
