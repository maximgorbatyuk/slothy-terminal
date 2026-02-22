import Foundation

/// JSON Schema representation for tool parameter definitions.
struct ToolParameterSchema: Codable, Sendable {
  let type: String
  let properties: [String: PropertySchema]
  let required: [String]

  /// Schema for a single property within the tool parameters.
  struct PropertySchema: Codable, Sendable {
    let type: String
    let description: String?
    let enumValues: [String]?

    enum CodingKeys: String, CodingKey {
      case type
      case description
      case enumValues = "enum"
    }
  }
}

/// Result returned by a tool execution.
struct ToolResult: Sendable {
  let output: String
  let isError: Bool
  let metadata: [String: JSONValue]

  init(
    output: String,
    isError: Bool = false,
    metadata: [String: JSONValue] = [:]
  ) {
    self.output = output
    self.isError = isError
    self.metadata = metadata
  }
}

/// Context provided to a tool during execution.
struct ToolContext: Sendable {
  let sessionID: String
  let workingDirectory: URL
  let permissions: PermissionDelegate

  init(
    sessionID: String,
    workingDirectory: URL,
    permissions: PermissionDelegate
  ) {
    self.sessionID = sessionID
    self.workingDirectory = workingDirectory
    self.permissions = permissions
  }
}

/// Protocol every tool must implement.
///
/// Each tool declares its parameter schema (for the LLM function-calling payload)
/// and an async execute method that performs the actual work.
protocol AgentTool: Sendable {
  /// Unique identifier (e.g., "bash", "read", "edit").
  var id: String { get }

  /// Human-readable description for the LLM.
  var toolDescription: String { get }

  /// JSON Schema for the tool's parameters.
  var parameters: ToolParameterSchema { get }

  /// Execute the tool with decoded arguments.
  func execute(
    arguments: [String: JSONValue],
    context: ToolContext
  ) async throws -> ToolResult
}
