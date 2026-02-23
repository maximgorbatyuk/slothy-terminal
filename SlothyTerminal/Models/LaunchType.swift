import Foundation

/// Represents the different session types a user can launch from the startup page.
enum LaunchType: String, CaseIterable, Identifiable, Codable {
  case terminal
  case claudeChat
  case opencodeChat
  case claudeNative
  case codexNative
  case zaiNative
  case claudeDesktop
  case codexDesktop
  case telegramBot

  var id: String { rawValue }

  /// User-visible name shown in the launch type picker.
  var displayName: String {
    switch self {
    case .terminal:
      return "Terminal"

    case .claudeChat:
      return "Claude Chat"

    case .opencodeChat:
      return "OpenCode Chat"

    case .claudeNative:
      return "Claude Native"

    case .codexNative:
      return "Codex Native"

    case .zaiNative:
      return "Z.AI Native"

    case .claudeDesktop:
      return "Claude Desktop"

    case .codexDesktop:
      return "Codex Desktop"

    case .telegramBot:
      return "Telegram Bot"
    }
  }

  /// Short description shown below the launch type name.
  var subtitle: String {
    switch self {
    case .terminal:
      return "Plain shell terminal"

    case .claudeChat:
      return "Chat interface for Claude"

    case .opencodeChat:
      return "Chat interface for OpenCode"

    case .claudeNative:
      return "Direct API — no CLI required"

    case .codexNative:
      return "Direct API — no CLI required"

    case .zaiNative:
      return "Direct API — no CLI required"

    case .claudeDesktop:
      return "Open project in Claude Desktop"

    case .codexDesktop:
      return "Open project in Codex Desktop"

    case .telegramBot:
      return "Bot listener with prompt execution"
    }
  }

  /// SF Symbol icon name for display in the picker.
  var iconName: String {
    switch self {
    case .terminal:
      return "terminal"

    case .claudeChat:
      return "bubble.left.and.bubble.right"

    case .opencodeChat:
      return "bubble.left.and.bubble.right"

    case .claudeNative:
      return "bolt.fill"

    case .codexNative:
      return "bolt.fill"

    case .zaiNative:
      return "bolt.fill"

    case .claudeDesktop:
      return "desktopcomputer"

    case .codexDesktop:
      return "desktopcomputer"

    case .telegramBot:
      return "paperplane"
    }
  }

  /// Whether this launch type accepts a predefined prompt.
  /// Used to decide if the prompt selector should be shown.
  var requiresPrompt: Bool {
    switch self {
    case .terminal, .claudeChat, .opencodeChat, .claudeNative, .codexNative,
         .zaiNative, .claudeDesktop, .codexDesktop:
      return true

    case .telegramBot:
      return false
    }
  }

  /// Whether this launch type requires selecting a saved prompt before start.
  /// Desktop launches require an explicit prompt selection.
  var requiresPredefinedPrompt: Bool {
    switch self {
    case .claudeDesktop, .codexDesktop:
      return true

    case .terminal, .claudeChat, .opencodeChat, .claudeNative, .codexNative,
         .zaiNative, .telegramBot:
      return false
    }
  }

  /// The underlying agent type used for tab creation, if applicable.
  var agentType: AgentType? {
    switch self {
    case .terminal:
      return .terminal

    case .claudeChat, .claudeDesktop:
      return .claude

    case .opencodeChat:
      return .opencode

    case .claudeNative, .codexNative, .zaiNative:
      return .nativeAgent

    case .codexDesktop, .telegramBot:
      return nil
    }
  }

  /// The native provider ID for native agent launch types.
  var nativeProviderID: ProviderID? {
    switch self {
    case .claudeNative:
      return .anthropic

    case .codexNative:
      return .openAI

    case .zaiNative:
      return .zai

    default:
      return nil
    }
  }
}
