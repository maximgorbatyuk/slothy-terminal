import Foundation

/// Detects risky tool operations that require user approval.
///
/// Both CLI transports handle tool execution internally — we observe
/// tool use events but cannot intercept mid-stream. Detections are
/// collected during execution and trigger a post-completion approval gate.
enum RiskyToolDetector {

  /// A detected risky operation.
  struct Detection {
    let toolName: String
    let reason: String
  }

  /// Checks whether a tool invocation is risky.
  ///
  /// Returns a `Detection` if the tool name + input match a risky pattern,
  /// or `nil` if the operation is safe.
  static func check(toolName: String, input: String) -> Detection? {
    let lower = toolName.lowercased()

    if isBashTool(lower) {
      return checkBash(toolName: toolName, input: input)
    }

    if isWriteTool(lower) {
      return checkWrite(toolName: toolName, input: input)
    }

    return nil
  }

  // MARK: - Private

  private static func isBashTool(_ lower: String) -> Bool {
    lower == "bash" || lower == "execute" || lower == "shell"
  }

  private static func isWriteTool(_ lower: String) -> Bool {
    lower == "write" || lower == "create" || lower == "edit"
  }

  private static let riskyBashPatterns: [(pattern: String, reason: String)] = [
    ("git push", "git push — pushes code to remote"),
    ("git commit", "git commit — creates a commit"),
    ("rm -rf", "rm -rf — recursive force delete"),
    ("rm -r", "rm -r — recursive delete"),
    ("DROP ", "SQL DROP statement"),
    ("DELETE FROM", "SQL DELETE statement"),
    ("TRUNCATE", "SQL TRUNCATE statement"),
    ("sudo ", "sudo — elevated privileges"),
    ("chmod ", "chmod — permission change"),
    ("chown ", "chown — ownership change"),
  ]

  private static let riskyWritePaths: [(pattern: String, reason: String)] = [
    (".env", "writing to .env file"),
    ("credentials", "writing to credentials file"),
    (".ssh/", "writing to .ssh directory"),
    (".gitconfig", "writing to .gitconfig"),
    (".github/workflows", "writing to GitHub Actions workflow"),
  ]

  private static func checkBash(toolName: String, input: String) -> Detection? {
    let inputLower = input.lowercased()

    for (pattern, reason) in riskyBashPatterns {
      if inputLower.contains(pattern.lowercased()) {
        return Detection(toolName: toolName, reason: reason)
      }
    }

    return nil
  }

  private static func checkWrite(toolName: String, input: String) -> Detection? {
    let inputLower = input.lowercased()

    for (pattern, reason) in riskyWritePaths {
      if inputLower.contains(pattern.lowercased()) {
        return Detection(toolName: toolName, reason: reason)
      }
    }

    return nil
  }
}
