import Foundation

/// Named reasoning / thinking intensity presets.
///
/// Maps to provider-specific parameters:
/// - OpenAI/Codex: `reasoningEffort`
/// - Anthropic: thinking `budgetTokens`
/// - Z.AI/GLM: no manual variants (thinking enabled by default)
enum ReasoningVariant: String, Codable, CaseIterable, Sendable {
  case none
  case minimal
  case low
  case medium
  case high
  case max
  case xhigh
}
