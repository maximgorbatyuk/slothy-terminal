import Foundation

/// Tracks the state of an active Telegram-to-terminal relay session.
struct TelegramRelaySession {
  let tabId: UUID
  let tabName: String
  let startedAt: Date
  var lastOutputTimestamp: Date?
  var status: Status

  enum Status {
    case active
  }
}

/// Info about a terminal tab that can be targeted for relay.
struct TelegramRelayTabInfo {
  let id: UUID
  let name: String
  let agentType: AgentType
  let directory: URL
  let isActive: Bool
}
