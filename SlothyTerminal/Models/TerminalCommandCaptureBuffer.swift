import Foundation

/// Best-effort shadow buffer that tracks user keystrokes to approximate
/// the current command line. Has no cursor position awareness, so readline
/// features (Ctrl+A/E/K/Y, arrow keys, history recall, tab completion)
/// will cause drift. Intended only for heuristic display (e.g., tab labels),
/// not as an authoritative record of terminal input.
struct TerminalCommandCaptureBuffer {
  private var buffer = ""

  mutating func append(_ text: String, submitOnNewline: Bool = true) -> [String] {
    guard !text.isEmpty else {
      return []
    }

    var submittedCommands: [String] = []

    for character in text {
      switch character {
      // Both CR and LF trigger submit. Enter typically sends \r;
      // if \r\n arrives, the second triggers an empty submit filtered by submit().
      case "\r" where submitOnNewline,
           "\n" where submitOnNewline:
        if let command = submit() {
          submittedCommands.append(command)
        }

      case "\u{8}", "\u{7F}":
        deleteBackward()

      default:
        buffer.append(character)
      }
    }

    return submittedCommands
  }

  mutating func deleteBackward() {
    guard !buffer.isEmpty else {
      return
    }

    buffer.removeLast()
  }

  mutating func deleteLastWord() {
    guard !buffer.isEmpty else {
      return
    }

    while let lastCharacter = buffer.last, lastCharacter.isWhitespace {
      buffer.removeLast()
    }

    while let lastCharacter = buffer.last, !lastCharacter.isWhitespace {
      buffer.removeLast()
    }
  }

  mutating func clear() {
    buffer.removeAll(keepingCapacity: true)
  }

  mutating func submit() -> String? {
    let commandLine = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
    clear()

    guard !commandLine.isEmpty else {
      return nil
    }

    return commandLine
  }
}
