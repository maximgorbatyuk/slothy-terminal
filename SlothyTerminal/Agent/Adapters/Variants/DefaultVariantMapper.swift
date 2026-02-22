import Foundation

/// Maps reasoning variant presets to provider-specific API parameters.
///
/// Provider behavior:
/// - **OpenAI/Codex**: maps to `reasoningEffort` (low/medium/high/xhigh)
/// - **Anthropic**: maps to thinking `budgetTokens` or adaptive mode for newer models
/// - **Z.AI/GLM**: no manual variants (thinking enabled by default via adapter)
struct DefaultVariantMapper: VariantMapper, Sendable {

  func variants(for model: ModelDescriptor) -> [ReasoningVariant] {
    guard model.supportsReasoning else {
      return []
    }

    let id = model.modelID.lowercased()

    /// GLM models: no manual variants.
    if id.contains("glm") {
      return []
    }

    switch model.providerID {
    case .openAI:
      if id.contains("codex") {
        if id.contains("5.2") || id.contains("5.3") {
          return [.low, .medium, .high, .xhigh]
        }
        return [.low, .medium, .high]
      }

      if id.contains("gpt-5") {
        return [.minimal, .low, .medium, .high]
      }

      return [.low, .medium, .high]

    case .anthropic:
      if isAdaptiveAnthropic(id: id) {
        return [.low, .medium, .high, .max]
      }
      return [.high, .max]

    case .zai, .zhipuAI:
      return []
    }
  }

  func options(
    for model: ModelDescriptor,
    variant: ReasoningVariant
  ) -> [String: JSONValue] {
    let id = model.modelID.lowercased()

    switch model.providerID {
    case .openAI:
      return [
        "reasoningEffort": .string(variant.rawValue),
        "reasoningSummary": .string("auto"),
      ]

    case .anthropic:
      if isAdaptiveAnthropic(id: id) {
        return [
          "thinking": .object(["type": .string("adaptive")]),
          "effort": .string(variant.rawValue),
        ]
      }

      if variant == .high {
        return [
          "thinking": .object([
            "type": .string("enabled"),
            "budgetTokens": .number(16_000),
          ])
        ]
      }

      if variant == .max {
        return [
          "thinking": .object([
            "type": .string("enabled"),
            "budgetTokens": .number(31_999),
          ])
        ]
      }

      return [:]

    case .zai, .zhipuAI:
      return [:]
    }
  }

  func defaultThinkingOptions(
    for model: ModelDescriptor
  ) -> [String: JSONValue] {
    switch model.providerID {
    case .zai, .zhipuAI:
      return [
        "thinking": .object([
          "type": .string("enabled"),
          "clear_thinking": .bool(false),
        ])
      ]

    default:
      return [:]
    }
  }

  // MARK: - Private

  private func isAdaptiveAnthropic(id: String) -> Bool {
    id.contains("opus-4-6") || id.contains("opus-4.6")
      || id.contains("sonnet-4-6") || id.contains("sonnet-4.6")
  }
}
