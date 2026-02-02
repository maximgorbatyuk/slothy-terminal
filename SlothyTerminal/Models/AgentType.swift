import SwiftUI

/// Represents the different AI agent types supported by the terminal.
enum AgentType: String, CaseIterable, Identifiable, Codable {
  case claude = "Claude"
  case glm = "GLM"

  var id: String { rawValue }

  /// The command to execute for this agent.
  var command: String {
    switch self {
    case .claude:
      return ProcessInfo.processInfo.environment["CLAUDE_PATH"] ?? "/usr/local/bin/claude"
    case .glm:
      return ProcessInfo.processInfo.environment["GLM_PATH"] ?? "/usr/local/bin/glm"
    }
  }

  /// SF Symbol icon name for this agent.
  var iconName: String {
    switch self {
    case .claude:
      return "brain.head.profile"
    case .glm:
      return "cpu"
    }
  }

  /// Accent color for this agent.
  var accentColor: Color {
    switch self {
    case .claude:
      return Color(red: 0.85, green: 0.47, blue: 0.34)  // #da7756
    case .glm:
      return Color(red: 0.29, green: 0.62, blue: 1.0)  // #4a9eff
    }
  }
}
