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

  /// Lists terminal tabs that have a registered surface and can be relayed to.
  func telegramBotListRelayableTabs() -> [TelegramRelayTabInfo]

  /// Injects a request into a terminal tab. Returns the request with updated status, or nil on failure.
  func telegramBotInject(_ request: InjectionRequest) -> InjectionRequest?

  /// Returns the currently active AI terminal tab (Claude/OpenCode) with a registered surface, or nil.
  func telegramBotActiveInjectableAITab() -> TelegramRelayTabInfo?

  /// Returns a startup status statement for the given working directory.
  func telegramBotStartupStatement(workingDirectory: URL) async -> String
}

// MARK: - Startup Statement

/// Pure helper for composing the Telegram startup status statement.
enum TelegramStartupStatement {
  static func compose(
    repositoryPath: String?,
    workingDirectoryPath: String,
    openTabCount: Int,
    activeTaskCount: Int
  ) -> String {
    let repo = repositoryPath ?? workingDirectoryPath
    return [
      "Status",
      "Repository: \(repo)",
      "Open app tabs: \(openTabCount)",
      "Tasks to implement: \(activeTaskCount)"
    ].joined(separator: "\n")
  }
}
