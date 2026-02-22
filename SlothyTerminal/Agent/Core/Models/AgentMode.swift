import Foundation

/// Operating mode for an agent definition.
///
/// Controls which tools are available and how the agent participates
/// in the conversation.
enum AgentMode: String, Codable, Sendable {
  /// Full tool access, drives the main conversation.
  case primary

  /// Read-only tools only (grep, glob, read, bash).
  case readOnly

  /// Spawned by TaskTool for isolated subtasks, returns result to parent.
  case subagent
}
