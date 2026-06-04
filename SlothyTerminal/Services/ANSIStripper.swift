import Foundation

/// Strips ANSI escape codes from terminal output text.
enum ANSIStripper {
  private static let pattern = "\\x1B\\[[0-9;?]*[a-zA-Z]|\\x1B\\][^\\x07\\x1B]*(?:\\x07|\\x1B\\\\)|\\x1B[()][A-Z0-9]|\\x1B[78=>]"
  private static let regex = try? NSRegularExpression(pattern: pattern, options: [])

  static func strip(_ text: String) -> String {
    /// Fast path: every pattern alternative begins with ESC (0x1B), so text
    /// without an ESC byte can never match. Skipping the regex engine here
    /// avoids per-snapshot work on the hot terminal-output path, where the
    /// grid text read back from libghostty is usually already plain.
    guard text.contains("\u{1B}") else {
      return text
    }

    guard let regex else {
      return text
    }

    let range = NSRange(text.startIndex..., in: text)
    return regex.stringByReplacingMatches(
      in: text,
      options: [],
      range: range,
      withTemplate: ""
    )
  }
}
