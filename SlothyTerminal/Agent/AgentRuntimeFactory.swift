import Foundation
import OSLog

/// Assembles a fully configured `AgentRuntime` from application configuration.
///
/// This is the single composition point for the native agent system.
/// It reads API keys from the Keychain, creates provider adapters,
/// and wires everything together.
enum AgentRuntimeFactory {

  /// Creates an `AgentRuntime` with all available provider adapters.
  ///
  /// - Parameter tokenStore: The token store to use for credential access.
  ///   Defaults to `KeychainTokenStore`.
  /// - Returns: A configured `AgentRuntime` ready to stream LLM responses.
  static func makeRuntime(
    tokenStore: TokenStore = KeychainTokenStore()
  ) -> AgentRuntime {
    let adapters = makeAdapters(tokenStore: tokenStore)
    let mapper = DefaultVariantMapper()

    return AgentRuntime(
      adapters: adapters,
      tokenStore: tokenStore,
      mapper: mapper
    )
  }

  /// Creates an `AgentLoop` wired to a runtime for a given agent definition.
  ///
  /// - Parameters:
  ///   - agent: The agent definition (e.g. `.build`, `.plan`).
  ///   - tokenStore: The token store for credential access.
  /// - Returns: A fully configured `AgentLoop`.
  static func makeLoop(
    agent: AgentDefinition = .build,
    tokenStore: TokenStore = KeychainTokenStore()
  ) -> AgentLoop {
    let runtime = makeRuntime(tokenStore: tokenStore)
    let registry = ToolRegistry()
    registry.registerDefaults(for: agent.mode)

    return AgentLoop(
      runtime: runtime,
      registry: registry,
      agent: agent
    )
  }

  /// Creates a `NativeAgentTransport` ready for use with `ChatState`.
  ///
  /// - Parameters:
  ///   - model: The model to use for LLM calls.
  ///   - workingDirectory: The project directory for tool execution.
  ///   - permissions: The permission delegate for tool approvals.
  ///   - agent: The agent definition (defaults to `.build`).
  ///   - variant: Optional reasoning variant override.
  ///   - systemPrompt: Optional custom system prompt.
  ///   - tokenStore: The token store for credential access.
  /// - Returns: A configured `NativeAgentTransport`.
  static func makeTransport(
    model: ModelDescriptor,
    workingDirectory: URL,
    permissions: PermissionDelegate,
    agent: AgentDefinition = .build,
    variant: ReasoningVariant? = nil,
    systemPrompt: String? = nil,
    tokenStore: TokenStore = KeychainTokenStore()
  ) -> NativeAgentTransport {
    let loop = makeLoop(agent: agent, tokenStore: tokenStore)

    return NativeAgentTransport(
      loop: loop,
      model: model,
      workingDirectory: workingDirectory,
      permissions: permissions,
      variant: variant,
      systemPrompt: systemPrompt
    )
  }

  /// Checks whether the native agent system has auth configured for
  /// a given provider.
  ///
  /// - Parameters:
  ///   - provider: The provider to check.
  ///   - tokenStore: The token store to query.
  /// - Returns: `true` if an API key or OAuth token is stored.
  static func hasAuth(
    for provider: ProviderID,
    tokenStore: TokenStore = KeychainTokenStore()
  ) async -> Bool {
    do {
      if try await tokenStore.load(provider: provider) != nil {
        Logger.agent.debug("hasAuth(\(provider.rawValue)): found in Keychain")
        return true
      }

      /// Z.AI providers fall back to environment variables.
      if provider == .zai || provider == .zhipuAI {
        let envAuth = ZAIAdapter.authFromEnvironment() != nil
        Logger.agent.debug("hasAuth(\(provider.rawValue)): env fallback = \(envAuth)")
        return envAuth
      }

      Logger.agent.debug("hasAuth(\(provider.rawValue)): no credentials found")
      return false
    } catch {
      Logger.agent.error("hasAuth(\(provider.rawValue)): Keychain error: \(error.localizedDescription)")
      return false
    }
  }

  // MARK: - Private

  /// Creates adapter instances for all supported providers.
  private static func makeAdapters(
    tokenStore: TokenStore,
    zaiEndpoint: ZAIEndpoint = ConfigManager.shared.config.zaiEndpoint
  ) -> [ProviderID: any ProviderAdapter] {
    let zaiURL = zaiEndpoint.chatCompletionsURL

    return [
      .anthropic: ClaudeAdapter(tokenStore: tokenStore),
      .openAI: CodexAdapter(tokenStore: tokenStore),
      .zai: ZAIAdapter(providerID: .zai, endpointURL: zaiURL),
      .zhipuAI: ZAIAdapter(providerID: .zhipuAI, endpointURL: zaiURL),
    ]
  }
}
