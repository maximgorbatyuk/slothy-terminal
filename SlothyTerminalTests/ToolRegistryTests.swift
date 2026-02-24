import Foundation
import Testing

@testable import SlothyTerminalLib

@Suite("ToolRegistry")
struct ToolRegistryTests {

  /// A minimal stub tool for testing registration and lookup.
  private struct StubTool: AgentTool {
    let id: String
    let toolDescription: String
    let parameters = ToolParameterSchema(
      type: "object",
      properties: [:],
      required: []
    )

    func execute(
      arguments: [String: JSONValue],
      context: ToolContext
    ) async throws -> ToolResult {
      ToolResult(output: "stub")
    }
  }

  // MARK: - Registration

  @Test("Register built-in tools and look up by ID")
  func registerAndLookup() {
    let registry = ToolRegistry()
    let tool = StubTool(id: "read", toolDescription: "Read a file")
    registry.registerBuiltIn([tool])

    let found = registry.tool(byID: "read")
    #expect(found?.id == "read")
  }

  @Test("Lookup returns nil for unknown tool")
  func lookupUnknown() {
    let registry = ToolRegistry()
    let found = registry.tool(byID: "nonexistent")
    #expect(found == nil)
  }

  @Test("Custom tool is registered alongside built-in tools")
  func customRegistration() {
    let registry = ToolRegistry()
    let builtIn = StubTool(id: "bash", toolDescription: "Bash")
    let custom = StubTool(id: "custom", toolDescription: "Custom")

    registry.registerBuiltIn([builtIn])
    registry.register(custom)

    let tools = registry.tools(for: .primary)
    #expect(tools.count == 2)
    #expect(registry.tool(byID: "custom")?.id == "custom")
  }

  // MARK: - Mode Filtering

  @Test("Primary mode returns all tools")
  func primaryModeAllTools() {
    let registry = ToolRegistry()
    registry.registerBuiltIn([
      StubTool(id: "bash", toolDescription: "Bash"),
      StubTool(id: "read", toolDescription: "Read"),
      StubTool(id: "write", toolDescription: "Write"),
      StubTool(id: "edit", toolDescription: "Edit"),
      StubTool(id: "glob", toolDescription: "Glob"),
      StubTool(id: "grep", toolDescription: "Grep"),
      StubTool(id: "webfetch", toolDescription: "WebFetch"),
    ])

    let tools = registry.tools(for: .primary)
    #expect(tools.count == 7)
  }

  @Test("Read-only mode filters to safe tools only")
  func readOnlyModeFilters() {
    let registry = ToolRegistry()
    registry.registerBuiltIn([
      StubTool(id: "bash", toolDescription: "Bash"),
      StubTool(id: "read", toolDescription: "Read"),
      StubTool(id: "write", toolDescription: "Write"),
      StubTool(id: "edit", toolDescription: "Edit"),
      StubTool(id: "glob", toolDescription: "Glob"),
      StubTool(id: "grep", toolDescription: "Grep"),
      StubTool(id: "webfetch", toolDescription: "WebFetch"),
      StubTool(id: "open", toolDescription: "Open"),
      StubTool(id: "applescript", toolDescription: "AppleScript"),
      StubTool(id: "system_info", toolDescription: "System Info"),
    ])

    let tools = registry.tools(for: .readOnly)
    let ids = Set(tools.map(\.id))
    #expect(ids == ["bash", "read", "glob", "grep", "webfetch", "open", "applescript", "system_info"])
    #expect(!ids.contains("write"))
    #expect(!ids.contains("edit"))
  }

  @Test("Subagent mode returns all tools")
  func subagentModeAllTools() {
    let registry = ToolRegistry()
    registry.registerBuiltIn([
      StubTool(id: "bash", toolDescription: "Bash"),
      StubTool(id: "read", toolDescription: "Read"),
    ])

    let tools = registry.tools(for: .subagent)
    #expect(tools.count == 2)
  }

  // MARK: - Tool Definitions

  @Test("Tool definitions produce correct JSON structure")
  func toolDefinitionsFormat() {
    let registry = ToolRegistry()
    let tool = StubTool(id: "test_tool", toolDescription: "A test tool")
    registry.registerBuiltIn([tool])

    let defs = registry.toolDefinitions(for: .primary)
    #expect(defs.count == 1)

    let def = defs[0]
    #expect(def["type"] == .string("function"))

    if case .object(let fn) = def["function"] {
      #expect(fn["name"] == .string("test_tool"))
      #expect(fn["description"] == .string("A test tool"))

      if case .object(let params) = fn["parameters"] {
        #expect(params["type"] == .string("object"))
      } else {
        Issue.record("parameters should be an object")
      }
    } else {
      Issue.record("function should be an object")
    }
  }

  @Test("Empty registry returns empty definitions")
  func emptyDefinitions() {
    let registry = ToolRegistry()
    let defs = registry.toolDefinitions(for: .primary)
    #expect(defs.isEmpty)
  }
}
