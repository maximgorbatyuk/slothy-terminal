import Foundation

/// Strips ANSI escape codes from terminal output text.
enum ANSIStripper {
  private static let pattern = "\\x1B\\[[0-9;?]*[a-zA-Z]|\\x1B\\][^\\x07\\x1B]*(?:\\x07|\\x1B\\\\)|\\x1B[()][A-Z0-9]|\\x1B[78=>]"
  private static let regex = try? NSRegularExpression(pattern: pattern, options: [])

  static func strip(_ text: String) -> String {
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
