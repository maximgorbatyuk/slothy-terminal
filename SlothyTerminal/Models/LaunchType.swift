import Foundation

/// Represents the different session types a user can launch from the startup page.
enum LaunchType: String, CaseIterable, Identifiable, Codable {
  case terminal
  case claude
  case opencode
  case claudeChat
  case opencodeChat

  var id: String { rawValue }

  /// User-visible name shown in the launch type picker.
  var displayName: String {
    switch self {
    case .terminal:
      return "Terminal"

    case .claude:
      return "claude"

    case .opencode:
      return "opencode"

    case .claudeChat:
      return "Claude Chat"

    case .opencodeChat:
      return "OpenCode Chat"
    }
  }

  /// Short description shown below the launch type name.
  var subtitle: String {
    switch self {
    case .terminal:
      return "Plain shell terminal"

    case .claude:
      return "Terminal running claude CLI"

    case .opencode:
      return "Terminal running opencode CLI"

    case .claudeChat:
      return "Chat interface for Claude"

    case .opencodeChat:
      return "Chat interface for OpenCode"
    }
  }

  /// SF Symbol icon name for display in the picker.
  var iconName: String {
    switch self {
    case .terminal:
      return "terminal"

    case .claude:
      return "apple.terminal"

    case .opencode:
      return "apple.terminal"

    case .claudeChat:
      return "bubble.left.and.bubble.right"

    case .opencodeChat:
      return "bubble.left.and.bubble.right"
    }
  }

  /// Whether this launch type accepts a predefined prompt.
  /// Used to decide if the prompt selector should be shown.
  var requiresPrompt: Bool {
    switch self {
    case .terminal, .claude, .opencode, .claudeChat, .opencodeChat:
      return true
    }
  }

  /// Whether this launch type requires selecting a saved prompt before start.
  /// Desktop launches require an explicit prompt selection.
  var requiresPredefinedPrompt: Bool {
    switch self {
    case .terminal, .claude, .opencode, .claudeChat, .opencodeChat:
      return false
    }
  }

  /// The underlying agent type used for tab creation, if applicable.
  var agentType: AgentType? {
    switch self {
    case .terminal:
      return .terminal

    case .claude, .claudeChat:
      return .claude

    case .opencode, .opencodeChat:
      return .opencode
    }
  }
}
