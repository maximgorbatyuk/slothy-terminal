import Foundation
@testable import SlothyTerminalLib

/// Mock tab provider for orchestrator tests.
@MainActor
class MockInjectionTabProvider: InjectionTabProvider {
  var activeTabId: UUID?
  var tabIds: [UUID] = []
  var tabAgentTypes: [UUID: AgentType] = [:]
  var tabModes: [UUID: TabMode] = [:]

  func terminalTabs(agentType: AgentType?, mode: TabMode?) -> [UUID] {
    tabIds.filter { tabId in
      if let agentType, tabAgentTypes[tabId] != agentType {
        return false
      }

      if let mode, tabModes[tabId] != mode {
        return false
      }

      return true
    }
  }
}
