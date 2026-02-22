import Foundation

/// Assembles the system prompt from agent definition, tool descriptions,
/// project context, and working directory.
///
/// The system prompt is built in sections:
/// 1. Agent's custom system prompt (if any)
/// 2. Working directory context
/// 3. Tool descriptions (summary of available tools)
/// 4. Agent mode constraints
enum SystemPromptBuilder {

  /// Builds a complete system prompt for the given agent and context.
  ///
  /// - Parameters:
  ///   - agent: The agent definition providing base prompt and mode.
  ///   - tools: The available tools (for generating descriptions).
  ///   - workingDirectory: The project directory path.
  /// - Returns: The assembled system prompt string.
  static func build(
    agent: AgentDefinition,
    tools: [AgentTool],
    workingDirectory: URL
  ) -> String {
    var sections: [String] = []

    /// 1. Agent's custom system prompt.
    if let custom = agent.systemPrompt {
      sections.append(custom)
    }

    /// 2. Working directory context.
    sections.append(
      "Working directory: \(workingDirectory.path)"
    )

    /// 3. Tool descriptions.
    if !tools.isEmpty {
      let toolList = tools.map { tool in
        "- \(tool.id): \(tool.toolDescription)"
      }.joined(separator: "\n")

      sections.append("Available tools:\n\(toolList)")
    }

    /// 4. Mode constraints.
    switch agent.mode {
    case .readOnly:
      sections.append(
        "You are in read-only mode. Do not modify any files or execute destructive commands."
      )

    case .subagent:
      sections.append(
        "You are running as a subagent. Complete the task and return a concise result."
      )

    case .primary:
      break
    }

    return sections.joined(separator: "\n\n")
  }
}
