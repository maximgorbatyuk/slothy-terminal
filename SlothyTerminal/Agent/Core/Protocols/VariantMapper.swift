import Foundation

/// Maps reasoning variant presets to provider-specific API parameters.
///
/// The variant mapper is provider-aware: it knows that OpenAI uses
/// `reasoningEffort`, Anthropic uses thinking `budgetTokens`, and
/// Z.AI enables thinking by default with no manual variants.
protocol VariantMapper: Sendable {
  /// Returns the list of selectable variants for a given model.
  /// Empty array means reasoning variants are not user-configurable.
  func variants(for model: ModelDescriptor) -> [ReasoningVariant]

  /// Returns API options for a specific model + variant combination.
  func options(
    for model: ModelDescriptor,
    variant: ReasoningVariant
  ) -> [String: JSONValue]

  /// Returns default thinking options applied automatically
  /// (e.g., Z.AI enables thinking by default).
  func defaultThinkingOptions(
    for model: ModelDescriptor
  ) -> [String: JSONValue]
}
