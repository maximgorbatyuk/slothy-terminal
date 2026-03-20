import SwiftUI

/// Plain terminal shell agent.
struct TerminalAgent: AIAgent {
  let type: AgentType = .terminal

  let accentColor = Color.secondary
  let iconName = "terminal"
  let displayName = "Terminal"
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

  /// Terminal is always available.
  func isAvailable() -> Bool {
    true
  }

  /// Terminal does not support initial prompts.
  func argsWithPrompt(_ promptText: String) -> [String] {
    defaultArgs
  }
}
