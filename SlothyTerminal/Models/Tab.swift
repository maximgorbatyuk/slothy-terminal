import Foundation

/// The mode a tab operates in.
enum TabMode: String, Codable, CaseIterable {
  case terminal
  case chat
  case git

  /// Modes available as a default startup option in settings.
  static var defaultOptions: [TabMode] {
    [.terminal, .chat]
  }

  var displayName: String {
    switch self {
    case .terminal:
      return "Terminal"

    case .chat:
      return "Chat"

    case .git:
      return "Git client"
    }
  }
}

/// Represents a single terminal tab with an AI agent session.
@MainActor
@Observable
class Tab: Identifiable {
  let id: UUID
  let workspaceID: UUID
  let agentType: AgentType?
  let mode: TabMode
  var workingDirectory: URL
  var title: String
  var isActive: Bool = false
  var hasBackgroundActivity: Bool = false
  var usageStats: UsageStats
  var isTerminalBusy: Bool = false
  private var terminalActivityResetTask: Task<Void, Never>?
  private let terminalActivityIdleDelayNanoseconds: UInt64 = 800_000_000

  /// The saved prompt to pass as the first message to the AI agent.
  let initialPrompt: SavedPrompt?

  /// Optional launch arguments override for terminal tabs.
  /// When set, replaces the agent's default argument construction.
  let launchArgumentsOverride: [String]?

  /// The AI agent for this tab (nil for non-agent modes like `.git`).
  let agent: AIAgent?

  /// The chat state for chat-mode tabs.
  var chatState: ChatState?

  init(
    id: UUID = UUID(),
    workspaceID: UUID,
    agentType: AgentType? = nil,
    workingDirectory: URL,
    title: String? = nil,
    initialPrompt: SavedPrompt? = nil,
    launchArgumentsOverride: [String]? = nil,
    mode: TabMode = .terminal,
    resumeSessionId: String? = nil
  ) {
    assert(
      mode != .git || agentType == nil,
      "Git tabs must not have an agentType"
    )

    self.id = id
    self.workspaceID = workspaceID
    self.agentType = agentType
    self.mode = mode
    self.workingDirectory = workingDirectory
    self.title = title ?? workingDirectory.lastPathComponent
    self.initialPrompt = initialPrompt
    self.launchArgumentsOverride = launchArgumentsOverride
    self.usageStats = UsageStats()

    if let agentType {
      let createdAgent = AgentFactory.createAgent(for: agentType)
      self.agent = createdAgent
      self.usageStats.contextWindowLimit = createdAgent.contextWindowLimit
    } else {
      self.agent = nil
    }

    if mode == .chat, let agentType {
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
  /// Examples: "Claude | chat", "Opencode | cli", "Git client".
  var tabName: String {
    if mode == .git {
      return "Git client"
    }

    return "\(agentNameForTab) | \(modeNameForTab)"
  }

  /// Agent label used in tab/window titles.
  private var agentNameForTab: String {
    switch agentType {
    case .claude:
      return "Claude"

    case .opencode:
      return "Opencode"

    case .terminal:
      return "Terminal"

    case nil:
      return ""
    }
  }

  /// Mode label used in tab/window titles.
  private var modeNameForTab: String {
    switch mode {
    case .chat:
      return "chat"

    case .terminal:
      return "cli"

    case .git:
      return "git"
    }
  }

  /// The command to execute for this tab's agent.
  var command: String {
    agent?.command ?? ""
  }

  /// The arguments to pass to the agent command.
  /// Uses launch override if set, otherwise delegates to the agent.
  var arguments: [String] {
    guard let agent else {
      return []
    }

    if let launchArgumentsOverride {
      return launchArgumentsOverride
    }

    if let prompt = initialPrompt {
      return agent.argsWithPrompt(prompt.promptText)
    }

    return agent.defaultArgs
  }

  /// The environment variables for the agent process.
  var environment: [String: String] {
    agent?.environmentVariables ?? [:]
  }

  /// Checks if the agent is available (installed).
  var isAgentAvailable: Bool {
    agent?.isAvailable() ?? false
  }

  /// Whether this tab is actively executing work.
  var isExecuting: Bool {
    switch mode {
    case .chat:
      return chatState?.isLoading ?? false

    case .terminal:
      return isTerminalBusy

    case .git:
      return false
    }
  }

  /// Marks the terminal tab as busy.
  /// Driven by Ghostty command lifecycle events.
  func markTerminalBusy() {
    isTerminalBusy = true
  }

  /// Records that a terminal command has started running.
  func handleTerminalCommandEntered() {
    usageStats.incrementCommandCount()
    recordTerminalActivity()
  }

  /// Marks auto-run terminal sessions as busy as soon as they launch.
  func handleTerminalLaunch(shouldAutoRunCommand: Bool) {
    guard shouldAutoRunCommand else {
      return
    }

    recordTerminalActivity()
  }

  /// Records terminal activity and clears the busy state after a short idle window.
  func recordTerminalActivity() {
    let idleDelayNanoseconds = terminalActivityIdleDelayNanoseconds

    markTerminalBusy()
    terminalActivityResetTask?.cancel()

    terminalActivityResetTask = Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: idleDelayNanoseconds)

      guard !Task.isCancelled else {
        return
      }

      self?.markTerminalIdle()
    }
  }

  /// Marks the terminal tab as idle.
  func markTerminalIdle() {
    terminalActivityResetTask?.cancel()
    terminalActivityResetTask = nil
    isTerminalBusy = false
  }

  /// Marks the tab as having unseen background terminal output.
  func markBackgroundActivity() {
    guard !isActive,
          !hasBackgroundActivity
    else {
      return
    }

    hasBackgroundActivity = true
  }

  /// Clears the unseen background terminal output indicator.
  func clearBackgroundActivity() {
    guard hasBackgroundActivity else {
      return
    }

    hasBackgroundActivity = false
  }
}
