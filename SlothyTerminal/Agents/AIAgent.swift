import SwiftUI

/// Protocol defining the interface for AI agents.
protocol AIAgent {
  /// The type of agent.
  var type: AgentType { get }

  /// The command to execute for this agent.
  var command: String { get }

  /// Default arguments to pass to the command.
  var defaultArgs: [String] { get }

  /// Environment variables to set for the process.
  var environmentVariables: [String: String] { get }

  /// The accent color for this agent's UI elements.
  var accentColor: Color { get }

  /// The SF Symbol icon name for this agent.
  var iconName: String { get }

  /// The display name for this agent.
  var displayName: String { get }

  /// The context window limit for this agent (in tokens).
  var contextWindowLimit: Int { get }

  /// Parses terminal output to extract usage statistics.
  /// - Parameter output: The terminal output text to parse.
  /// - Returns: A UsageUpdate if stats were found, nil otherwise.
  func parseStats(from output: String) -> UsageUpdate?

  /// Formats a startup message to display when the session begins.
  /// - Returns: An optional startup message, or nil for no message.
  func formatStartupMessage() -> String?

  /// Validates that the agent's command is available.
  /// - Returns: true if the command exists and is executable.
  func isAvailable() -> Bool
}

// MARK: - Default Implementations

extension AIAgent {
  /// Default implementation checks if the command file exists.
  func isAvailable() -> Bool {
    FileManager.default.isExecutableFile(atPath: command)
  }

  /// Default implementation returns nil (no startup message).
  func formatStartupMessage() -> String? {
    nil
  }

  /// Default environment variables (empty).
  var environmentVariables: [String: String] {
    [:]
  }

  /// Default args (empty).
  var defaultArgs: [String] {
    []
  }
}

// MARK: - Agent Factory

/// Factory for creating agent instances.
enum AgentFactory {
  /// Creates an agent instance for the given type.
  static func createAgent(for type: AgentType) -> AIAgent {
    switch type {
    case .claude:
      return ClaudeAgent()
    case .glm:
      return GLMAgent()
    }
  }

  /// Returns all available agents.
  static var allAgents: [AIAgent] {
    AgentType.allCases.map { createAgent(for: $0) }
  }

  /// Returns all agents that are currently available (installed).
  static var availableAgents: [AIAgent] {
    allAgents.filter { $0.isAvailable() }
  }
}
