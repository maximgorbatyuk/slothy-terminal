import Foundation

/// Spawns a subagent (a new `AgentLoop` with isolated message context)
/// and returns its final text result to the parent loop.
///
/// The subagent uses the `.general` agent definition (subagent mode)
/// and shares the same runtime and permissions, but gets a fresh
/// message history.
struct TaskTool: AgentTool {
  let id = "task"
  let toolDescription = "Spawn a subagent to handle a complex subtask. The subagent runs in isolation and returns a text result."
  let parameters = ToolParameterSchema(
    type: "object",
    properties: [
      "prompt": .init(
        type: "string",
        description: "The task description for the subagent to complete",
        enumValues: nil
      ),
    ],
    required: ["prompt"]
  )

  private let runtimeFactory: @Sendable (ToolContext) -> (AgentLoopProtocol, ToolRegistry)?

  /// Creates a TaskTool with a factory that provides the runtime and registry
  /// for spawning subagents.
  ///
  /// - Parameter runtimeFactory: Closure that creates an `AgentLoopProtocol`
  ///   and `ToolRegistry` from a `ToolContext`. Returns nil to indicate
  ///   subagent creation is unavailable.
  init(
    runtimeFactory: @escaping @Sendable (ToolContext) -> (AgentLoopProtocol, ToolRegistry)?
  ) {
    self.runtimeFactory = runtimeFactory
  }

  func execute(
    arguments: [String: JSONValue],
    context: ToolContext
  ) async throws -> ToolResult {
    guard case .string(let prompt) = arguments["prompt"] else {
      return ToolResult(
        output: "Missing required 'prompt' argument",
        isError: true
      )
    }

    guard let (loop, _) = runtimeFactory(context) else {
      return ToolResult(
        output: "Subagent creation is not available in the current configuration",
        isError: true
      )
    }

    /// Build a minimal input for the subagent.
    let input = RuntimeInput(
      sessionID: "\(context.sessionID)-sub-\(UUID().uuidString.prefix(8))",
      model: ModelDescriptor(
        providerID: .anthropic,
        modelID: "claude-sonnet-4-6",
        packageID: "@ai-sdk/anthropic",
        supportsReasoning: true,
        releaseDate: "",
        outputLimit: 16_384
      ),
      messages: []
    )

    /// Fresh message history for the subagent.
    var messages: [[String: JSONValue]] = [
      [
        "role": .string("user"),
        "content": .array([
          .object(["type": .string("text"), "text": .string(prompt)])
        ]),
      ]
    ]

    do {
      let result = try await loop.run(
        input: input,
        messages: &messages,
        context: context,
        onEvent: nil
      )

      return ToolResult(output: result)
    } catch {
      return ToolResult(
        output: "Subagent error: \(error.localizedDescription)",
        isError: true
      )
    }
  }
}
