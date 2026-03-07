import Foundation

/// Specifies which terminal tab(s) should receive an injection.
enum InjectionTarget: Codable, Equatable, Sendable {
  /// The currently active tab.
  case activeTab

  /// A specific tab by its UUID.
  case tabId(UUID)

  /// All terminal tabs matching the given criteria.
  case filtered(agentType: AgentType?, mode: TabMode?)
}
