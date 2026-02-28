import Foundation

/// The mode a tab operates in.
enum TabMode: String, Codable, CaseIterable {
  case terminal
  case chat
  case telegramBot

  var displayName: String {
    switch self {
    case .terminal:
      return "Terminal"

    case .chat:
      return "Chat"

    case .telegramBot:
      return "Telegram Bot"
    }
  }
}

/// Represents a single terminal tab with an AI agent session.
@Observable
class Tab: Identifiable {
  let id: UUID
  let agentType: AgentType
  let mode: TabMode
  var workingDirectory: URL
  var title: String
  var isActive: Bool = false
  var usageStats: UsageStats

  /// The saved prompt to pass as the first message to the AI agent.
  let initialPrompt: SavedPrompt?

  /// The AI agent for this tab.
  let agent: AIAgent

  /// The chat state for chat-mode tabs.
  var chatState: ChatState?

  /// The Telegram bot runtime for telegram-bot-mode tabs.
  var telegramRuntime: TelegramBotRuntime?

  init(
    id: UUID = UUID(),
    agentType: AgentType,
    workingDirectory: URL,
    title: String? = nil,
    initialPrompt: SavedPrompt? = nil,
    mode: TabMode = .terminal,
    resumeSessionId: String? = nil
  ) {
    self.id = id
    self.agentType = agentType
    self.mode = mode
    self.workingDirectory = workingDirectory
    self.title = title ?? workingDirectory.lastPathComponent
    self.initialPrompt = initialPrompt
    self.usageStats = UsageStats()
    self.agent = AgentFactory.createAgent(for: agentType)

    /// Set context window limit from agent.
    self.usageStats.contextWindowLimit = agent.contextWindowLimit

    if mode == .chat {
      if let resumeSessionId {
        self.chatState = ChatState(
          workingDirectory: workingDirectory,
          agentType: agentType,
          resumeSessionId: resumeSessionId
        )
      } else {
        self.chatState = ChatState(
          workingDirectory: workingDirectory,
          agentType: agentType
        )
      }
    }
  }

  /// Creates a display title combining agent type and directory.
  var displayTitle: String {
    tabName
  }

  /// Stable tab label shown in the tab bar.
  /// Examples: "Claude | chat", "Opencode | cli", "Telegram | bot".
  var tabName: String {
    if mode == .telegramBot {
      return "Telegram | bot"
    }

    return "\(agentNameForTab) | \(modeNameForTab)"
  }

  /// Agent label used in tab/window titles.
  private var agentNameForTab: String {
    if mode == .telegramBot {
      return "Telegram"
    }

    switch agentType {
    case .claude:
      return "Claude"

    case .opencode:
      return "Opencode"

    case .terminal:
      return "Terminal"
    }
  }

  /// Mode label used in tab/window titles.
  private var modeNameForTab: String {
    switch mode {
    case .chat:
      return "chat"

    case .terminal:
      return "cli"

    case .telegramBot:
      return "bot"
    }
  }

  /// The command to execute for this tab's agent.
  var command: String {
    agent.command
  }

  /// The arguments to pass to the agent command.
  /// Delegates prompt formatting to the agent to ensure safe flag termination.
  var arguments: [String] {
    if let prompt = initialPrompt {
      return agent.argsWithPrompt(prompt.promptText)
    }

    return agent.defaultArgs
  }

  /// The environment variables for the agent process.
  var environment: [String: String] {
    agent.environmentVariables
  }

  /// Checks if the agent is available (installed).
  var isAgentAvailable: Bool {
    agent.isAvailable()
  }
}
