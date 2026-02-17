import SwiftUI

/// Plain terminal shell agent.
struct TerminalAgent: AIAgent {
  let type: AgentType = .terminal

  let accentColor = Color.secondary
  let iconName = "terminal"
  let displayName = "Terminal"
  let contextWindowLimit = 0

  /// Uses the user's default shell.
  var command: String {
    ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
  }

  /// No arguments needed - just start the shell.
  var defaultArgs: [String] {
    []
  }

  var environmentVariables: [String: String] {
    [
      "TERM": "xterm-256color",
      "COLORTERM": "truecolor"
    ]
  }

  /// Terminal doesn't parse stats.
  func parseStats(from output: String) -> UsageUpdate? {
    nil
  }

  /// Terminal is always available.
  func isAvailable() -> Bool {
    true
  }

  /// Terminal does not support initial prompts.
  func argsWithPrompt(_ promptText: String) -> [String] {
    defaultArgs
  }
}
