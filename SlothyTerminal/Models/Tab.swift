import Foundation

/// The mode a tab operates in.
enum TabMode: String, Codable, CaseIterable {
  case terminal
  case chat

  var displayName: String {
    switch self {
    case .terminal:
      return "Terminal"

    case .chat:
      return "Chat"
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

  /// The PTY controller managing this tab's terminal session.
  /// Set after the tab is created and the terminal is initialized.
  var ptyController: PTYController?

  /// Callback to send text to the terminal.
  var sendToTerminal: ((String) -> Void)?

  /// Buffer for accumulating terminal output for stats parsing.
  private var outputBuffer: String = ""
  private let maxBufferSize = 10_000

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
          resumeSessionId: resumeSessionId
        )
      } else {
        self.chatState = ChatState(workingDirectory: workingDirectory)
      }
    }
  }

  /// Creates a display title combining agent type and directory.
  var displayTitle: String {
    let prefix = mode == .chat ? "Chat" : agent.displayName
    return "\(prefix): \(title)"
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

  /// Processes terminal output and updates usage statistics.
  /// - Parameter output: New terminal output to process.
  func processOutput(_ output: String) {
    /// Add to buffer.
    outputBuffer += output

    /// Trim buffer if too large.
    if outputBuffer.count > maxBufferSize {
      let startIndex = outputBuffer.index(
        outputBuffer.endIndex,
        offsetBy: -maxBufferSize,
        limitedBy: outputBuffer.startIndex
      ) ?? outputBuffer.startIndex
      outputBuffer = String(outputBuffer[startIndex...])
    }

    /// Try to parse stats from the new output.
    if let update = agent.parseStats(from: output) {
      usageStats.applyUpdate(update, incrementMessages: update.incrementMessageCount)
    }
  }

  /// Clears the output buffer.
  func clearOutputBuffer() {
    outputBuffer = ""
  }

  /// Checks if the agent is available (installed).
  var isAgentAvailable: Bool {
    agent.isAvailable()
  }

  /// Sends a command to request usage stats from the agent.
  func requestUsageStats() {
    /// Only send for AI agents (not plain terminal).
    guard agentType.showsUsageStats else {
      return
    }

    /// Send /usage command to Claude CLI.
    sendToTerminal?("/usage\n")
  }
}
