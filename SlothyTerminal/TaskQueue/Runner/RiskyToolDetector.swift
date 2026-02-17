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
  /// Returns all detected risky patterns, or an empty array if safe.
  static func check(toolName: String, input: String) -> [Detection] {
    let lower = toolName.lowercased()

    if isBashTool(lower) {
      return checkBash(toolName: toolName, input: input)
    }

    if isWriteTool(lower) {
      return checkWrite(toolName: toolName, input: input)
    }

    return []
  }

  // MARK: - Private

  private static func isBashTool(_ lower: String) -> Bool {
    lower == "bash" || lower == "execute" || lower == "shell"
  }

  private static func isWriteTool(_ lower: String) -> Bool {
    lower == "write" || lower == "create" || lower == "edit"
  }

  /// Patterns are lowercase — input is lowercased before comparison.
  private static let riskyBashPatterns: [(pattern: String, reason: String)] = [
    ("git push", "git push — pushes code to remote"),
    ("git commit", "git commit — creates a commit"),
    ("rm -rf", "rm -rf — recursive force delete"),
    ("rm -r ", "rm -r — recursive delete"),
    ("drop ", "SQL DROP statement"),
    ("delete from", "SQL DELETE statement"),
    ("truncate", "SQL TRUNCATE statement"),
    ("sudo ", "sudo — elevated privileges"),
    ("chmod ", "chmod — permission change"),
    ("chown ", "chown — ownership change"),
  ]

  /// Path patterns that indicate sensitive file writes.
  ///
  /// Uses path-boundary-aware matching: `/.env` requires a directory
  /// separator before `.env` to avoid matching `.environment` etc.
  private static let riskyWritePatterns: [(check: (String) -> Bool, reason: String)] = [
    ({ $0.contains("/.env") && !$0.contains("/.envrc") }, "writing to .env file"),
    ({ $0.hasSuffix("/credentials") || $0.contains("/credentials/") }, "writing to credentials file"),
    ({ $0.contains("/.ssh/") }, "writing to .ssh directory"),
    ({ $0.contains("/.gitconfig") }, "writing to .gitconfig"),
    ({ $0.contains("/.github/workflows") }, "writing to GitHub Actions workflow"),
  ]

  /// Checks bash input for risky command patterns.
  /// Input is lowercased; patterns are already lowercase.
  private static func checkBash(toolName: String, input: String) -> [Detection] {
    let inputLower = input.lowercased()
    var detections: [Detection] = []

    for (pattern, reason) in riskyBashPatterns {
      if inputLower.contains(pattern) {
        detections.append(Detection(toolName: toolName, reason: reason))
      }
    }

    return detections
  }

  private static func checkWrite(toolName: String, input: String) -> [Detection] {
    let inputLower = input.lowercased()
    var detections: [Detection] = []

    for (check, reason) in riskyWritePatterns {
      if check(inputLower) {
        detections.append(Detection(toolName: toolName, reason: reason))
      }
    }

    return detections
  }
}
