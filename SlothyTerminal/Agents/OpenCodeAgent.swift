import SwiftUI

/// OpenCode AI agent implementation.
struct OpenCodeAgent: AIAgent {
  let type: AgentType = .opencode

  let accentColor = Color(red: 0.29, green: 0.78, blue: 0.49)
  let iconName = "chevron.left.forwardslash.chevron.right"
  let displayName = "OpenCode"
  let contextWindowLimit = 200_000

  /// Path to the opencode CLI executable.
  var command: String {
    if let envPath = ProcessInfo.processInfo.environment["OPENCODE_PATH"],
       FileManager.default.isExecutableFile(atPath: envPath)
    {
      return envPath
    }

    let commonPaths = [
      "/usr/local/bin/opencode",
      "/opt/homebrew/bin/opencode",
      "\(NSHomeDirectory())/.local/bin/opencode",
      "\(NSHomeDirectory())/go/bin/opencode"
    ]

    for path in commonPaths {
      if FileManager.default.isExecutableFile(atPath: path) {
        return path
      }
    }

    return "/usr/local/bin/opencode"
  }

  var defaultArgs: [String] {
    []
  }

  var environmentVariables: [String: String] {
    var env: [String: String] = [:]
    env["TERM"] = "xterm-256color"
    env["COLORTERM"] = "truecolor"
    return env
  }

  func parseStats(from output: String) -> UsageUpdate? {
    let parser = StatsParser.shared
    return parser.parseClaudeOutput(output)
  }

  func isAvailable() -> Bool {
    FileManager.default.isExecutableFile(atPath: command)
  }
}
