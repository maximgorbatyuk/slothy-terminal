import Foundation
import Testing

@testable import SlothyTerminalLib

@Suite("SystemPromptBuilder")
struct SystemPromptBuilderTests {

  /// A minimal stub tool for testing.
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

  private let workingDir = FileManager.default.temporaryDirectory

  // MARK: - Basic structure

  @Test("Build includes platform identity")
  func includesIdentity() {
    let prompt = SystemPromptBuilder.build(
      agent: .build,
      tools: [],
      workingDirectory: workingDir
    )

    #expect(prompt.contains("macOS"))
    #expect(prompt.contains("Architecture:"))
  }

  @Test("Build includes working directory")
  func includesWorkingDirectory() {
    let prompt = SystemPromptBuilder.build(
      agent: .build,
      tools: [],
      workingDirectory: workingDir
    )

    #expect(prompt.contains("Working directory:"))
    #expect(prompt.contains(workingDir.path))
  }

  @Test("Build includes macOS capabilities guide")
  func includesMacOSGuide() {
    let prompt = SystemPromptBuilder.build(
      agent: .build,
      tools: [],
      workingDirectory: workingDir
    )

    #expect(prompt.contains("macOS System Capabilities"))
    #expect(prompt.contains("open"))
    #expect(prompt.contains("applescript"))
    #expect(prompt.contains("system_info"))
  }

  // MARK: - Tool listing

  @Test("Build includes tool descriptions")
  func includesToolDescriptions() {
    let tools: [AgentTool] = [
      StubTool(id: "bash", toolDescription: "Execute bash"),
      StubTool(id: "read", toolDescription: "Read files"),
    ]

    let prompt = SystemPromptBuilder.build(
      agent: .build,
      tools: tools,
      workingDirectory: workingDir
    )

    #expect(prompt.contains("Available tools:"))
    #expect(prompt.contains("- bash: Execute bash"))
    #expect(prompt.contains("- read: Read files"))
  }

  // MARK: - Mode constraints

  @Test("Read-only mode adds constraint text")
  func readOnlyModeConstraint() {
    let prompt = SystemPromptBuilder.build(
      agent: .plan,
      tools: [],
      workingDirectory: workingDir
    )

    #expect(prompt.contains("read-only mode"))
  }

  @Test("Subagent mode adds constraint text")
  func subagentModeConstraint() {
    let prompt = SystemPromptBuilder.build(
      agent: .general,
      tools: [],
      workingDirectory: workingDir
    )

    #expect(prompt.contains("subagent"))
  }

  @Test("Primary mode has no constraint text")
  func primaryModeNoConstraint() {
    let prompt = SystemPromptBuilder.build(
      agent: .build,
      tools: [],
      workingDirectory: workingDir
    )

    #expect(!prompt.contains("read-only mode"))
    #expect(!prompt.contains("running as a subagent"))
  }

  // MARK: - Agent custom system prompt

  @Test("Custom agent system prompt is included")
  func customSystemPrompt() {
    let agent = AgentDefinition(
      name: "custom",
      systemPrompt: "You are a specialized testing agent."
    )

    let prompt = SystemPromptBuilder.build(
      agent: agent,
      tools: [],
      workingDirectory: workingDir
    )

    #expect(prompt.contains("You are a specialized testing agent."))
  }

  // MARK: - User profile

  @Test("Profile with preferred IDE is included")
  func profilePreferredIDE() {
    let profile = AgentProfile(preferredIDE: "Xcode")

    let prompt = SystemPromptBuilder.build(
      agent: .build,
      tools: [],
      workingDirectory: workingDir,
      profile: profile
    )

    #expect(prompt.contains("Preferred IDE: Xcode"))
  }

  @Test("Profile with project roots is included")
  func profileProjectRoots() {
    let profile = AgentProfile(projectRoots: [
      "/Users/dev/projects",
      "/Users/dev/work",
    ])

    let prompt = SystemPromptBuilder.build(
      agent: .build,
      tools: [],
      workingDirectory: workingDir,
      profile: profile
    )

    #expect(prompt.contains("/Users/dev/projects"))
    #expect(prompt.contains("/Users/dev/work"))
  }

  @Test("Profile with custom instructions is included")
  func profileCustomInstructions() {
    let profile = AgentProfile(
      customInstructions: "Always use 2-space indentation."
    )

    let prompt = SystemPromptBuilder.build(
      agent: .build,
      tools: [],
      workingDirectory: workingDir,
      profile: profile
    )

    #expect(prompt.contains("Always use 2-space indentation."))
  }

  @Test("Profile with preferred apps is included")
  func profilePreferredApps() {
    let profile = AgentProfile(
      preferredApps: ["browser": "Arc", "notes": "Obsidian"]
    )

    let prompt = SystemPromptBuilder.build(
      agent: .build,
      tools: [],
      workingDirectory: workingDir,
      profile: profile
    )

    #expect(prompt.contains("browser: Arc"))
    #expect(prompt.contains("notes: Obsidian"))
  }

  @Test("Empty profile produces no profile section")
  func emptyProfile() {
    let profile = AgentProfile()

    let prompt = SystemPromptBuilder.build(
      agent: .build,
      tools: [],
      workingDirectory: workingDir,
      profile: profile
    )

    #expect(!prompt.contains("User Profile"))
  }

  @Test("Nil profile produces no profile section")
  func nilProfile() {
    let prompt = SystemPromptBuilder.build(
      agent: .build,
      tools: [],
      workingDirectory: workingDir,
      profile: nil
    )

    #expect(!prompt.contains("User Profile"))
  }

  // MARK: - Project detection

  @Test("Detects git repository")
  func detectsGitRepo() {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    let gitDir = tempDir.appendingPathComponent(".git")

    try? FileManager.default.createDirectory(
      at: gitDir,
      withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let prompt = SystemPromptBuilder.build(
      agent: .build,
      tools: [],
      workingDirectory: tempDir
    )

    #expect(prompt.contains("Git repository: yes"))
  }

  @Test("Detects Swift Package project type")
  func detectsSwiftPackage() {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)

    try? FileManager.default.createDirectory(
      at: tempDir,
      withIntermediateDirectories: true
    )

    let packageSwift = tempDir.appendingPathComponent("Package.swift")
    try? "// swift-tools-version:5.9".write(to: packageSwift, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let prompt = SystemPromptBuilder.build(
      agent: .build,
      tools: [],
      workingDirectory: tempDir
    )

    #expect(prompt.contains("Swift Package"))
  }
}
