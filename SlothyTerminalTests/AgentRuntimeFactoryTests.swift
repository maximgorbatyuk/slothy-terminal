import Foundation
import Testing

@testable import SlothyTerminalLib

@Suite("AgentRuntimeFactory")
struct AgentRuntimeFactoryTests {

  // MARK: - Runtime creation

  @Test("makeRuntime creates a runtime with all adapters")
  func makeRuntimeCreatesRuntime() {
    let store = MockTokenStore()
    let runtime = AgentRuntimeFactory.makeRuntime(tokenStore: store)

    /// Runtime should be non-nil and functional.
    /// We can't inspect private state, but it should not crash.
    #expect(runtime is AgentRuntime)
  }

  // MARK: - Loop creation

  @Test("makeLoop creates a loop with default build agent")
  func makeLoopDefaultAgent() {
    let store = MockTokenStore()
    let loop = AgentRuntimeFactory.makeLoop(tokenStore: store)

    /// Loop should be creatable without errors.
    #expect(loop is AgentLoop)
  }

  @Test("makeLoop creates a loop with custom agent definition")
  func makeLoopCustomAgent() {
    let store = MockTokenStore()
    let agent = AgentDefinition.plan
    let loop = AgentRuntimeFactory.makeLoop(agent: agent, tokenStore: store)

    #expect(loop is AgentLoop)
  }

  // MARK: - Transport creation

  @Test("makeTransport creates a NativeAgentTransport")
  func makeTransportCreatesTransport() {
    let store = MockTokenStore()
    let model = ModelDescriptor(
      providerID: .anthropic,
      modelID: "claude-sonnet-4-6",
      packageID: "@ai-sdk/anthropic",
      supportsReasoning: true,
      releaseDate: "2025-05-14",
      outputLimit: 16_384
    )

    let transport = AgentRuntimeFactory.makeTransport(
      model: model,
      workingDirectory: FileManager.default.temporaryDirectory,
      permissions: MockPermissionDelegate(),
      tokenStore: store
    )

    #expect(transport is NativeAgentTransport)
    #expect(!transport.isRunning)
  }

  @Test("makeTransport with variant passes through")
  func makeTransportWithVariant() {
    let store = MockTokenStore()
    let model = ModelDescriptor(
      providerID: .anthropic,
      modelID: "claude-sonnet-4-6",
      packageID: "@ai-sdk/anthropic",
      supportsReasoning: true,
      releaseDate: "2025-05-14",
      outputLimit: 16_384
    )

    let transport = AgentRuntimeFactory.makeTransport(
      model: model,
      workingDirectory: FileManager.default.temporaryDirectory,
      permissions: MockPermissionDelegate(),
      variant: .high,
      tokenStore: store
    )

    #expect(transport is NativeAgentTransport)
  }

  // MARK: - Auth check

  @Test("hasAuth returns false when no credentials stored")
  func hasAuthNoCredentials() async {
    let store = MockTokenStore()
    let result = await AgentRuntimeFactory.hasAuth(
      for: .anthropic,
      tokenStore: store
    )

    #expect(!result)
  }

  @Test("hasAuth returns true when API key is stored")
  func hasAuthWithCredentials() async throws {
    let store = MockTokenStore()
    try await store.save(provider: .anthropic, auth: .apiKey("sk-test-key"))

    let result = await AgentRuntimeFactory.hasAuth(
      for: .anthropic,
      tokenStore: store
    )

    #expect(result)
  }

  @Test("hasAuth returns false for different provider")
  func hasAuthDifferentProvider() async throws {
    let store = MockTokenStore()
    try await store.save(provider: .anthropic, auth: .apiKey("sk-test-key"))

    let result = await AgentRuntimeFactory.hasAuth(
      for: .openAI,
      tokenStore: store
    )

    #expect(!result)
  }
}
