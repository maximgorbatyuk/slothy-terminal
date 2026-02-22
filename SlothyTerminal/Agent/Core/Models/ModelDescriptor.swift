import Foundation

/// Describes an LLM model's capabilities and identity.
struct ModelDescriptor: Codable, Sendable, Hashable {
  let providerID: ProviderID
  let modelID: String
  let packageID: String
  let supportsReasoning: Bool
  let releaseDate: String
  let outputLimit: Int

  /// Total context window size in tokens. Used by `ContextCompactor`
  /// to determine when the conversation exceeds the budget.
  /// Defaults to `outputLimit * 4` when not explicitly set.
  let contextWindow: Int

  init(
    providerID: ProviderID,
    modelID: String,
    packageID: String,
    supportsReasoning: Bool,
    releaseDate: String,
    outputLimit: Int,
    contextWindow: Int? = nil
  ) {
    self.providerID = providerID
    self.modelID = modelID
    self.packageID = packageID
    self.supportsReasoning = supportsReasoning
    self.releaseDate = releaseDate
    self.outputLimit = outputLimit
    self.contextWindow = contextWindow ?? (outputLimit * 4)
  }
}
