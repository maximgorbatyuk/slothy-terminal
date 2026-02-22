import Foundation

/// Configuration bundle for an agent instance.
///
/// Defines the agent's name, operating mode, tool access, step limits,
/// and optional model/variant overrides. Presets mirror OpenCode's
/// built-in agent definitions.
struct AgentDefinition: Sendable {
  /// Human-readable name (e.g. "build", "plan", "explore").
  let name: String

  /// Optional description shown in agent picker UI.
  let agentDescription: String?

  /// Operating mode that controls tool access.
  let mode: AgentMode

  /// Hidden agents are not shown in the agent picker.
  let isHidden: Bool

  /// System prompt prepended to every conversation.
  let systemPrompt: String?

  /// LLM sampling temperature override.
  let temperature: Double?

  /// Maximum tool-execution rounds before forced stop.
  let maxSteps: Int

  /// Optional model override (provider + model ID).
  let modelOverride: ModelOverride?

  /// Optional reasoning variant override.
  let variant: ReasoningVariant?

  init(
    name: String,
    agentDescription: String? = nil,
    mode: AgentMode = .primary,
    isHidden: Bool = false,
    systemPrompt: String? = nil,
    temperature: Double? = nil,
    maxSteps: Int = 50,
    modelOverride: ModelOverride? = nil,
    variant: ReasoningVariant? = nil
  ) {
    self.name = name
    self.agentDescription = agentDescription
    self.mode = mode
    self.isHidden = isHidden
    self.systemPrompt = systemPrompt
    self.temperature = temperature
    self.maxSteps = maxSteps
    self.modelOverride = modelOverride
    self.variant = variant
  }
}

// MARK: - Model Override

extension AgentDefinition {
  /// A Sendable-safe model override (replaces tuple from skeleton).
  struct ModelOverride: Sendable {
    let providerID: ProviderID
    let modelID: String

    init(providerID: ProviderID, modelID: String) {
      self.providerID = providerID
      self.modelID = modelID
    }
  }
}

// MARK: - Presets

extension AgentDefinition {
  /// Default agent with full tool access.
  static let build = AgentDefinition(
    name: "build",
    agentDescription: "Default agent with full tool access",
    mode: .primary,
    maxSteps: 100
  )

  /// Read-only planning mode.
  static let plan = AgentDefinition(
    name: "plan",
    agentDescription: "Read-only planning mode",
    mode: .readOnly,
    maxSteps: 50
  )

  /// Fast codebase exploration.
  static let explore = AgentDefinition(
    name: "explore",
    agentDescription: "Fast codebase exploration",
    mode: .readOnly,
    maxSteps: 30
  )

  /// Multi-step task executor (subagent).
  static let general = AgentDefinition(
    name: "general",
    agentDescription: "Multi-step task executor",
    mode: .subagent,
    maxSteps: 50
  )

  /// Session summarization for context compaction.
  static let compaction = AgentDefinition(
    name: "compaction",
    agentDescription: "Session summarization",
    mode: .primary,
    isHidden: true,
    maxSteps: 1
  )
}
