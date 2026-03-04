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

/// Line-based viewport diffing for terminal relay output.
enum ViewportDiffer {
  /// Finds new/changed lines by comparing from the top.
  /// Returns lines after the longest common prefix as "new or changed" content.
  static func diffLines(previous: [String], current: [String]) -> String {
    if previous.isEmpty {
      return current.joined(separator: "\n")
    }

    var commonPrefixCount = 0
    let minCount = min(previous.count, current.count)
    for i in 0..<minCount {
      if previous[i] == current[i] {
        commonPrefixCount += 1
      } else {
        break
      }
    }

    let newLines = Array(current.dropFirst(commonPrefixCount))

    if newLines.isEmpty {
      return ""
    }

    return newLines.joined(separator: "\n")
  }
}
