import SwiftUI

/// Claude AI agent implementation.
struct ClaudeAgent: AIAgent {
  let type: AgentType = .claude

  /// Claude's accent color (coral/orange).
  let accentColor = Color(red: 0.85, green: 0.47, blue: 0.34)

  let iconName = "brain.head.profile"
  let displayName = "Claude"

  /// Claude's context window is 200K tokens.
  let contextWindowLimit = 200_000

  /// Path to the Claude CLI executable.
  var command: String {
    /// Check environment variable first, then common paths.
    if let envPath = ProcessInfo.processInfo.environment["CLAUDE_PATH"],
       FileManager.default.isExecutableFile(atPath: envPath)
    {
      return envPath
    }

    /// Check common installation paths.
    let commonPaths = [
      "/usr/local/bin/claude",
      "/opt/homebrew/bin/claude",
      "\(NSHomeDirectory())/.local/bin/claude",
      "\(NSHomeDirectory())/bin/claude"
    ]

    for path in commonPaths {
      if FileManager.default.isExecutableFile(atPath: path) {
        return path
      }
    }

    /// Default path.
    return "/usr/local/bin/claude"
  }

  /// Default arguments for Claude CLI.
  var defaultArgs: [String] {
    []
  }

  /// Environment variables for Claude.
  var environmentVariables: [String: String] {
    var env: [String: String] = [:]

    /// Pass through API key if set.
    if let apiKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] {
      env["ANTHROPIC_API_KEY"] = apiKey
    }

    /// Enable color output.
    env["TERM"] = "xterm-256color"
    env["COLORTERM"] = "truecolor"

    return env
  }

  /// Parses Claude CLI output for usage statistics.
  func parseStats(from output: String) -> UsageUpdate? {
    let parser = StatsParser.shared
    return parser.parseClaudeOutput(output)
  }

  /// Formats a startup message for Claude sessions.
  func formatStartupMessage() -> String? {
    nil
  }

  /// Checks if Claude CLI is installed and available.
  func isAvailable() -> Bool {
    FileManager.default.isExecutableFile(atPath: command)
  }
}

// MARK: - Claude-specific Parsing Helpers

extension ClaudeAgent {
  /// Detects if the output indicates a new message was sent.
  func detectNewMessage(in output: String) -> Bool {
    /// Claude CLI typically shows prompts or message indicators.
    let messageIndicators = [
      "Human:",
      "Assistant:",
      ">>> ",
      "You:"
    ]

    return messageIndicators.contains { output.contains($0) }
  }

  /// Extracts the model name from Claude output if present.
  func extractModelName(from output: String) -> String? {
    /// Look for model indicators like "claude-3-opus" or "claude-3-sonnet".
    let pattern = "claude-[0-9]+-[a-z]+"
    guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
      return nil
    }

    let range = NSRange(output.startIndex..., in: output)
    guard let match = regex.firstMatch(in: output, options: [], range: range),
          let matchRange = Range(match.range, in: output)
    else {
      return nil
    }

    return String(output[matchRange])
  }
}
