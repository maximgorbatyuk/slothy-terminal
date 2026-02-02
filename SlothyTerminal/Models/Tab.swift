import Foundation

/// Represents a single terminal tab with an AI agent session.
@Observable
class Tab: Identifiable {
  let id: UUID
  let agentType: AgentType
  var workingDirectory: URL
  var title: String
  var isActive: Bool = false
  var usageStats: UsageStats

  /// The AI agent for this tab.
  let agent: AIAgent

  /// The PTY controller managing this tab's terminal session.
  /// Set after the tab is created and the terminal is initialized.
  var ptyController: PTYController?

  /// Buffer for accumulating terminal output for stats parsing.
  private var outputBuffer: String = ""
  private let maxBufferSize = 10_000

  init(
    id: UUID = UUID(),
    agentType: AgentType,
    workingDirectory: URL,
    title: String? = nil
  ) {
    self.id = id
    self.agentType = agentType
    self.workingDirectory = workingDirectory
    self.title = title ?? workingDirectory.lastPathComponent
    self.usageStats = UsageStats()
    self.agent = AgentFactory.createAgent(for: agentType)

    /// Set context window limit from agent.
    self.usageStats.contextWindowLimit = agent.contextWindowLimit
  }

  /// Creates a display title combining agent type and directory.
  var displayTitle: String {
    "\(agent.displayName): \(title)"
  }

  /// The command to execute for this tab's agent.
  var command: String {
    agent.command
  }

  /// The arguments to pass to the agent command.
  var arguments: [String] {
    agent.defaultArgs
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
}
