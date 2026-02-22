import Foundation

/// Assembles available tools based on agent mode and configuration.
///
/// Tools are split into built-in (registered once at startup) and custom
/// (added dynamically). Mode filtering restricts read-only agents to
/// non-destructive tools.
final class ToolRegistry: @unchecked Sendable {
  private var builtIn: [AgentTool] = []
  private var custom: [AgentTool] = []

  /// Tool IDs allowed in read-only mode.
  private let readOnlyIDs: Set<String> = [
    "bash", "read", "glob", "grep", "webfetch"
  ]

  init() {}

  /// Registers the standard set of built-in tools for a given agent mode.
  ///
  /// This is the primary entry point for setting up tools. It creates
  /// all 7 built-in tools plus TaskTool for primary mode; mode filtering
  /// happens at query time via `tools(for:)`.
  ///
  /// - Parameters:
  ///   - mode: The agent mode (used to decide whether to include TaskTool).
  ///   - subagentFactory: Optional factory for creating subagent loops.
  ///     When nil, TaskTool is not registered.
  func registerDefaults(
    for mode: AgentMode = .primary,
    subagentFactory: (@Sendable (ToolContext) -> (AgentLoopProtocol, ToolRegistry)?)? = nil
  ) {
    var tools: [AgentTool] = [
      BashTool(),
      ReadFileTool(),
      WriteFileTool(),
      EditFileTool(),
      GlobTool(),
      GrepTool(),
      WebFetchTool(),
    ]

    /// Register TaskTool only for primary mode with a factory.
    if mode == .primary,
       let factory = subagentFactory
    {
      tools.append(TaskTool(runtimeFactory: factory))
    }

    registerBuiltIn(tools)
  }

  /// Register a single custom tool.
  func register(_ tool: AgentTool) {
    custom.append(tool)
  }

  /// Register the default set of built-in tools.
  func registerBuiltIn(_ tools: [AgentTool]) {
    builtIn = tools
  }

  /// Returns tools available for a given agent mode.
  func tools(for mode: AgentMode) -> [AgentTool] {
    let all = builtIn + custom
    switch mode {
    case .primary, .subagent:
      return all

    case .readOnly:
      return all.filter { readOnlyIDs.contains($0.id) }
    }
  }

  /// Lookup a tool by its unique ID.
  func tool(byID id: String) -> AgentTool? {
    (builtIn + custom).first { $0.id == id }
  }

  /// Convert tools to the JSON Schema format expected by LLM APIs.
  func toolDefinitions(for mode: AgentMode) -> [[String: JSONValue]] {
    tools(for: mode).map { tool in
      [
        "type": .string("function"),
        "function": .object([
          "name": .string(tool.id),
          "description": .string(tool.toolDescription),
          "parameters": encodeSchema(tool.parameters),
        ]),
      ]
    }
  }

  // MARK: - Private

  private func encodeSchema(_ schema: ToolParameterSchema) -> JSONValue {
    var props: [String: JSONValue] = [:]
    for (key, prop) in schema.properties {
      var obj: [String: JSONValue] = ["type": .string(prop.type)]
      if let desc = prop.description {
        obj["description"] = .string(desc)
      }
      if let vals = prop.enumValues {
        obj["enum"] = .array(vals.map { .string($0) })
      }
      props[key] = .object(obj)
    }

    return .object([
      "type": .string(schema.type),
      "properties": .object(props),
      "required": .array(schema.required.map { .string($0) }),
    ])
  }
}
