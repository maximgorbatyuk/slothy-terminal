import Foundation

/// Chat interaction mode — controls agent behavior.
enum ChatMode: String, Codable, CaseIterable {
  case build
  case plan

  var displayName: String { rawValue.capitalized }
}

/// User-selected model for the chat session.
struct ChatModelSelection: Codable, Equatable {
  var providerID: String
  var modelID: String
  var displayName: String

  /// CLI model string: `modelID` for Claude, `providerID/modelID` for OpenCode.
  var cliModelString: String {
    providerID.isEmpty ? modelID : "\(providerID)/\(modelID)"
  }
}

/// Metadata resolved from the transport after a turn completes.
struct ChatResolvedMetadata: Codable, Equatable {
  var resolvedProviderID: String?
  var resolvedModelID: String?
  var resolvedMode: ChatMode?
}
