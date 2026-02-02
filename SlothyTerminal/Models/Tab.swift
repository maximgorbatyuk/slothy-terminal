import Foundation

/// Represents a single terminal tab with an AI agent session.
@Observable
class Tab: Identifiable {
  let id: UUID
  let agentType: AgentType
  var workingDirectory: URL
  var title: String
  var isActive: Bool = false
  var usageStats: UsageStats

  /// The PTY controller managing this tab's terminal session.
  /// Set after the tab is created and the terminal is initialized.
  var ptyController: PTYController?

  init(
    id: UUID = UUID(),
    agentType: AgentType,
    workingDirectory: URL,
    title: String? = nil
  ) {
    self.id = id
    self.agentType = agentType
    self.workingDirectory = workingDirectory
    self.title = title ?? workingDirectory.lastPathComponent
    self.usageStats = UsageStats()
  }

  /// Creates a display title combining agent type and directory.
  var displayTitle: String {
    "\(agentType.rawValue): \(title)"
  }
}
