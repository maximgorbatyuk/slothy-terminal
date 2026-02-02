import SwiftUI

/// Represents the different tab types supported by the terminal.
enum AgentType: String, CaseIterable, Identifiable, Codable {
  case terminal = "Terminal"
  case claude = "Claude"
  case opencode = "OpenCode"

  var id: String { rawValue }

  /// SF Symbol icon name for this tab type.
  var iconName: String {
    switch self {
    case .terminal:
      return "terminal"
    case .claude:
      return "brain.head.profile"
    case .opencode:
      return "chevron.left.forwardslash.chevron.right"
    }
  }

  /// Accent color for this tab type.
  var accentColor: Color {
    switch self {
    case .terminal:
      return .secondary
    case .claude:
      return Color(red: 0.85, green: 0.47, blue: 0.34)
    case .opencode:
      return Color(red: 0.29, green: 0.78, blue: 0.49)
    }
  }

  /// Whether this tab type shows usage stats in the sidebar.
  var showsUsageStats: Bool {
    switch self {
    case .terminal:
      return false
    case .claude, .opencode:
      return true
    }
  }

  /// Description for the tab type.
  var description: String {
    switch self {
    case .terminal:
      return "Plain shell terminal"
    case .claude:
      return "Claude AI assistant"
    case .opencode:
      return "OpenCode AI assistant"
    }
  }
}
