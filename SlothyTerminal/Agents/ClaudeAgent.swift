import SwiftUI

/// Claude AI agent implementation.
struct ClaudeAgent: AIAgent {
  let type: AgentType = .claude

  let accentColor = Color(red: 0.85, green: 0.47, blue: 0.34)
  let iconName = "brain.head.profile"
  let displayName = "Claude"
  let contextWindowLimit = 200_000

  /// Command to run Claude CLI.
  /// Uses just "claude" to let the shell's PATH find the correct version.
  var command: String {
    if let envPath = ProcessInfo.processInfo.environment["CLAUDE_PATH"],
       FileManager.default.isExecutableFile(atPath: envPath)
    {
      return envPath
    }

    /// Use just "claude" - the shell will find it via PATH.
    return "claude"
  }

  var defaultArgs: [String] {
    []
  }

  var environmentVariables: [String: String] {
    var env: [String: String] = [:]

    if let apiKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] {
      env["ANTHROPIC_API_KEY"] = apiKey
    }

    env["TERM"] = "xterm-256color"
    env["COLORTERM"] = "truecolor"

    return env
  }

  func parseStats(from output: String) -> UsageUpdate? {
    let parser = StatsParser.shared
    return parser.parseClaudeOutput(output)
  }

  func isAvailable() -> Bool {
    /// Check if CLAUDE_PATH is set and valid.
    if let envPath = ProcessInfo.processInfo.environment["CLAUDE_PATH"] {
      return FileManager.default.isExecutableFile(atPath: envPath)
    }

    /// Check common installation paths.
    let commonPaths = [
      "/usr/local/bin/claude",
      "/opt/homebrew/bin/claude",
      "\(NSHomeDirectory())/.local/bin/claude",
      "\(NSHomeDirectory())/.claude/local/claude",
      "\(NSHomeDirectory())/bin/claude"
    ]

    for path in commonPaths {
      if FileManager.default.isExecutableFile(atPath: path) {
        return true
      }
    }

    return false
  }
}
