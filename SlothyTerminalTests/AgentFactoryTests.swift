import XCTest
@testable import SlothyTerminalLib

final class AgentFactoryTests: XCTestCase {

  // MARK: - Factory Creation Tests

  func testCreateTerminalAgent() {
    let agent = AgentFactory.createAgent(for: .terminal)

    XCTAssertEqual(agent.type, .terminal)
    XCTAssertEqual(agent.displayName, "Terminal")
  }

  func testCreateClaudeAgent() {
    let agent = AgentFactory.createAgent(for: .claude)

    XCTAssertEqual(agent.type, .claude)
    XCTAssertEqual(agent.displayName, "Claude")
  }

  func testCreateOpenCodeAgent() {
    let agent = AgentFactory.createAgent(for: .opencode)

    XCTAssertEqual(agent.type, .opencode)
    XCTAssertEqual(agent.displayName, "OpenCode")
  }

  // MARK: - All Agents Tests

  func testAllAgentsReturnsAllTypes() {
    let agents = AgentFactory.allAgents

    XCTAssertEqual(agents.count, AgentType.allCases.count)
  }

  func testAllAgentsContainsEachType() {
    let agents = AgentFactory.allAgents
    let types = agents.map { $0.type }

    XCTAssertTrue(types.contains(.terminal))
    XCTAssertTrue(types.contains(.claude))
    XCTAssertTrue(types.contains(.opencode))
  }

  // MARK: - Agent Properties Tests

  func testTerminalAgentCommand() {
    let agent = AgentFactory.createAgent(for: .terminal)

    /// Terminal agent should use the user's default shell
    XCTAssertFalse(agent.command.isEmpty)
  }

  func testClaudeAgentCommand() {
    let agent = AgentFactory.createAgent(for: .claude)

    /// Claude agent should have claude in the command path
    XCTAssertTrue(agent.command.contains("claude"))
  }

  func testOpenCodeAgentCommand() {
    let agent = AgentFactory.createAgent(for: .opencode)

    /// OpenCode agent should have opencode in the command path
    XCTAssertTrue(agent.command.contains("opencode"))
  }

  // MARK: - Context Window Limit Tests

  func testTerminalAgentContextWindowLimit() {
    let agent = AgentFactory.createAgent(for: .terminal)

    /// Terminal doesn't have a context window concept
    XCTAssertEqual(agent.contextWindowLimit, 0)
  }

  func testClaudeAgentContextWindowLimit() {
    let agent = AgentFactory.createAgent(for: .claude)

    /// Claude has a large context window
    XCTAssertGreaterThan(agent.contextWindowLimit, 0)
  }

  func testOpenCodeAgentContextWindowLimit() {
    let agent = AgentFactory.createAgent(for: .opencode)

    /// OpenCode should also have a context window
    XCTAssertGreaterThan(agent.contextWindowLimit, 0)
  }

  // MARK: - Icon Tests

  func testTerminalAgentIcon() {
    let agent = AgentFactory.createAgent(for: .terminal)

    XCTAssertEqual(agent.iconName, "terminal")
  }

  func testClaudeAgentIcon() {
    let agent = AgentFactory.createAgent(for: .claude)

    XCTAssertEqual(agent.iconName, "brain.head.profile")
  }

  func testOpenCodeAgentIcon() {
    let agent = AgentFactory.createAgent(for: .opencode)

    XCTAssertEqual(agent.iconName, "chevron.left.forwardslash.chevron.right")
  }

  // MARK: - Parse Stats Tests

  func testTerminalAgentParseStatsReturnsNil() {
    let agent = AgentFactory.createAgent(for: .terminal)
    let result = agent.parseStats(from: "some output")

    /// Terminal doesn't parse stats
    XCTAssertNil(result)
  }

  func testClaudeAgentParseStats() {
    let agent = AgentFactory.createAgent(for: .claude)
    let result = agent.parseStats(from: "Tokens: 1000 in / 500 out")

    XCTAssertNotNil(result)
    XCTAssertEqual(result?.tokensIn, 1000)
    XCTAssertEqual(result?.tokensOut, 500)
  }
}

// MARK: - AgentType Tests

final class AgentTypeTests: XCTestCase {

  func testAllCasesCount() {
    XCTAssertEqual(AgentType.allCases.count, 3)
  }

  func testRawValues() {
    XCTAssertEqual(AgentType.terminal.rawValue, "Terminal")
    XCTAssertEqual(AgentType.claude.rawValue, "Claude")
    XCTAssertEqual(AgentType.opencode.rawValue, "OpenCode")
  }

  func testIdentifiable() {
    XCTAssertEqual(AgentType.terminal.id, "Terminal")
    XCTAssertEqual(AgentType.claude.id, "Claude")
    XCTAssertEqual(AgentType.opencode.id, "OpenCode")
  }

  func testShowsUsageStats() {
    XCTAssertFalse(AgentType.terminal.showsUsageStats)
    XCTAssertTrue(AgentType.claude.showsUsageStats)
    XCTAssertTrue(AgentType.opencode.showsUsageStats)
  }

  func testIconNames() {
    XCTAssertEqual(AgentType.terminal.iconName, "terminal")
    XCTAssertEqual(AgentType.claude.iconName, "brain.head.profile")
    XCTAssertEqual(AgentType.opencode.iconName, "chevron.left.forwardslash.chevron.right")
  }
}
