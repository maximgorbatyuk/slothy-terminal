import Foundation

/// Represents the different session types a user can launch from the startup page.
enum LaunchType: String, CaseIterable, Identifiable, Codable {
  case terminal
  case claude
  case opencode
  case gitClient

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

    case .gitClient:
      return "Git client"
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

    case .gitClient:
      return "Built-in Git repository browser"
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

    case .gitClient:
      return "arrow.triangle.branch"
    }
  }

  /// Whether this launch type accepts a predefined prompt.
  /// Used to decide if the prompt selector should be shown.
  var requiresPrompt: Bool {
    switch self {
    case .terminal, .claude, .opencode:
      return true

    case .gitClient:
      return false
    }
  }

  /// Whether this launch type requires selecting a saved prompt before start.
  /// Desktop launches require an explicit prompt selection.
  var requiresPredefinedPrompt: Bool {
    switch self {
    case .terminal, .claude, .opencode, .gitClient:
      return false
    }
  }

  /// The underlying agent type used for tab creation, if applicable.
  var agentType: AgentType? {
    switch self {
    case .terminal:
      return .terminal

    case .claude:
      return .claude

    case .opencode:
      return .opencode

    case .gitClient:
      return nil
    }
  }
}
