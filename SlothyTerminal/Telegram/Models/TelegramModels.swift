import Foundation

/// Operating mode for the Telegram bot.
enum TelegramBotMode: String, Codable, CaseIterable {
  case stopped
  case execute
  case passive

  var displayName: String {
    switch self {
    case .stopped:
      return "Stopped"

    case .execute:
      return "Execute"

    case .passive:
      return "Listen Only"
    }
  }
}

/// Runtime status of the Telegram bot.
enum TelegramBotStatus: Equatable {
  case idle
  case running
  case error(String)

  var displayName: String {
    switch self {
    case .idle:
      return "Idle"

    case .running:
      return "Running"

    case .error(let message):
      return "Error: \(message)"
    }
  }
}

/// Severity level for bot activity events.
enum TelegramEventLevel: String, Codable {
  case info
  case warning
  case error
}

/// A timestamped activity log entry for the Telegram bot.
struct TelegramBotEvent: Identifiable {
  let id: UUID
  let timestamp: Date
  let level: TelegramEventLevel
  let message: String

  init(
    id: UUID = UUID(),
    timestamp: Date = Date(),
    level: TelegramEventLevel = .info,
    message: String
  ) {
    self.id = id
    self.timestamp = timestamp
    self.level = level
    self.message = message
  }
}

/// Counters tracking bot activity.
struct TelegramBotStats {
  var received: Int = 0
  var ignored: Int = 0
  var executed: Int = 0
  var failed: Int = 0
}

/// Delegate protocol to decouple the bot runtime from AppState.
@MainActor
protocol TelegramBotDelegate: AnyObject {
  /// Returns a text report of the current app state (tab list, etc.).
  func telegramBotRequestReport() -> String

  /// Opens a new tab at the given directory.
  func telegramBotOpenTab(mode: TabMode, agent: AgentType, directory: URL)

  /// Enqueues a background task.
  func telegramBotEnqueueTask(
    title: String,
    prompt: String,
    repoPath: String,
    agentType: AgentType
  )
}
