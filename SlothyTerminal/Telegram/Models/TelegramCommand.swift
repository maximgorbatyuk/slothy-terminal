import Foundation

/// Recognized bot slash commands.
enum TelegramCommand: Equatable {
  case help
  case report
  case showMode
  case openDirectory
  case newTask
  case relayStart
  case relayStop
  case relayStatus
  case relayTabs
  case relayInterrupt
  case unknown(String)
}

/// Conversational state for multi-step command interactions.
enum TelegramInteractionState: Equatable {
  case idle
  case awaitingNewTaskText
  case awaitingNewTaskSchedule(taskText: String)
  case awaitingRelayTabChoice(tabs: [TelegramRelayTabInfo])
}

extension TelegramRelayTabInfo: Equatable {
  static func == (lhs: TelegramRelayTabInfo, rhs: TelegramRelayTabInfo) -> Bool {
    lhs.id == rhs.id
  }
}

/// Parses incoming message text into a command.
enum TelegramCommandParser {
  /// Parses a text message into a command, or returns nil if not a command.
  static func parse(_ text: String) -> TelegramCommand? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

    guard trimmed.hasPrefix("/") else {
      return nil
    }

    /// Extract the command name (everything before the first space or @).
    let commandPart = trimmed
      .split(separator: " ", maxSplits: 1).first
      .map(String.init) ?? trimmed

    let normalized = commandPart
      .split(separator: "@").first
      .map(String.init) ?? commandPart

    switch normalized.lowercased() {
    case "/help", "/start":
      return .help

    case "/report":
      return .report

    case "/show-mode", "/show_mode":
      return .showMode

    case "/open-directory", "/open_directory":
      return .openDirectory

    case "/new-task", "/new_task":
      return .newTask

    case "/relay-start", "/relay_start":
      return .relayStart

    case "/relay-stop", "/relay_stop":
      return .relayStop

    case "/relay-status", "/relay_status":
      return .relayStatus

    case "/relay-tabs", "/relay_tabs":
      return .relayTabs

    case "/relay-interrupt", "/relay_interrupt":
      return .relayInterrupt

    default:
      return .unknown(normalized)
    }
  }
}
