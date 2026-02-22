import Foundation

/// Describes an LLM model's capabilities and identity.
struct ModelDescriptor: Codable, Sendable, Hashable {
  let providerID: ProviderID
  let modelID: String
  let packageID: String
  let supportsReasoning: Bool
  let releaseDate: String
  let outputLimit: Int

  init(
    providerID: ProviderID,
    modelID: String,
    packageID: String,
    supportsReasoning: Bool,
    releaseDate: String,
    outputLimit: Int
  ) {
    self.providerID = providerID
    self.modelID = modelID
    self.packageID = packageID
    self.supportsReasoning = supportsReasoning
    self.releaseDate = releaseDate
    self.outputLimit = outputLimit
  }
}
