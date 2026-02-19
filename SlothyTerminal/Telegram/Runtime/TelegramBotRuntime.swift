import Foundation
import OSLog

/// Coordinates the Telegram bot lifecycle: polling, authorization,
/// command routing, and prompt execution.
@MainActor
@Observable
class TelegramBotRuntime {
  var mode: TelegramBotMode = .stopped
  var status: TelegramBotStatus = .idle
  var stats = TelegramBotStats()
  var events: [TelegramBotEvent] = []
  var messages: [TelegramTimelineMessage] = []
  var interactionState: TelegramInteractionState = .idle

  /// Delegate for app-level actions (report, open tab, enqueue task).
  weak var delegate: TelegramBotDelegate?

  private var pollingTask: Task<Void, Never>?
  private var executor: TelegramPromptExecutor?
  private let workingDirectory: URL
  private let configManager = ConfigManager.shared

  /// Maximum events/messages to keep in memory.
  private let maxEvents = 500
  private let maxMessages = 200

  init(workingDirectory: URL) {
    self.workingDirectory = workingDirectory
  }

  // MARK: - Lifecycle

  /// Starts the bot in Listen Only (passive) mode.
  ///
  /// The bot always starts in passive mode. Execute mode must be
  /// activated explicitly via `switchMode(.execute)` after the bot is running.
  func start() {
    guard pollingTask == nil else {
      return
    }

    let config = configManager.config

    guard let token = config.telegramBotToken,
          !token.isEmpty
    else {
      status = .error("No bot token configured")
      addEvent(.error, "Cannot start: no bot token configured")
      return
    }

    guard config.telegramAllowedUserID != nil else {
      status = .error("No allowed user ID configured")
      addEvent(.error, "Cannot start: no allowed user ID configured")
      return
    }

    mode = .passive
    status = .running

    addEvent(.info, "Starting bot in \(TelegramBotMode.passive.displayName) mode")
    addSystemMessage("Bot started in \(TelegramBotMode.passive.displayName) mode")

    executor = TelegramPromptExecutor(
      workingDirectory: workingDirectory,
      agentType: config.telegramExecutionAgent
    )

    let client = TelegramBotAPIClient(token: token)
    pollingTask = Task { [weak self] in
      await self?.pollingLoop(client: client)
    }
  }

  /// Stops the bot and cancels any in-flight work.
  func stop() {
    pollingTask?.cancel()
    pollingTask = nil

    /// Cancel the actor-isolated executor asynchronously.
    if let executor {
      Task { await executor.cancel() }
    }
    executor = nil

    mode = .stopped
    status = .idle
    interactionState = .idle

    addEvent(.info, "Bot stopped")
    addSystemMessage("Bot stopped")
  }

  /// Switches between execute and passive modes while running.
  func switchMode(_ newMode: TelegramBotMode) {
    guard newMode != .stopped else {
      stop()
      return
    }

    guard mode != .stopped else {
      start()
      return
    }

    mode = newMode
    interactionState = .idle
    addEvent(.info, "Switched to \(newMode.displayName) mode")
    addSystemMessage("Switched to \(newMode.displayName) mode")
  }

  // MARK: - Polling Loop

  private func pollingLoop(client: TelegramBotAPIClient) async {
    var offset = await prepareInitialOffset(client: client)
    var backoffSeconds: UInt64 = 1

    while !Task.isCancelled {
      do {
        let updates = try await client.getUpdates(offset: offset)
        backoffSeconds = 1

        for update in updates {
          offset = update.updateId + 1
          await handleUpdate(update, client: client)
        }
      } catch is CancellationError {
        break
      } catch let error as TelegramAPIError {
        if case .unauthorized = error {
          addEvent(.error, "Unauthorized — bot token invalid. Stopping.")
          addSystemMessage("Unauthorized (401). Bot stopped.")
          mode = .stopped
          status = .error("Unauthorized")
          pollingTask = nil
          return
        }

        addEvent(.warning, "Polling error: \(error.localizedDescription)")
        await exponentialBackoff(&backoffSeconds)
      } catch {
        addEvent(.warning, "Polling error: \(error.localizedDescription)")
        await exponentialBackoff(&backoffSeconds)
      }
    }
  }

  private func prepareInitialOffset(client: TelegramBotAPIClient) async -> Int64? {
    do {
      let pendingUpdates = try await client.getUpdates(offset: nil, timeout: 0)

      guard let lastUpdate = pendingUpdates.last else {
        return nil
      }

      addEvent(.info, "Skipped \(pendingUpdates.count) pending update(s) from before startup")
      return lastUpdate.updateId + 1
    } catch {
      addEvent(.warning, "Failed to drain pending updates on startup: \(error.localizedDescription)")
      return nil
    }
  }

  private func exponentialBackoff(_ seconds: inout UInt64) async {
    let delay = seconds
    seconds = min(seconds * 2, 8)

    do {
      try await Task.sleep(nanoseconds: delay * 1_000_000_000)
    } catch {
      /// Cancelled during backoff.
    }
  }

  // MARK: - Update Handling

  private func handleUpdate(_ update: TelegramUpdate, client: TelegramBotAPIClient) async {
    guard let message = update.message,
          let text = message.text,
          !text.isEmpty
    else {
      return
    }

    stats.received += 1
    let config = configManager.config

    /// Authorization check.
    guard let fromUser = message.from,
          fromUser.id == config.telegramAllowedUserID,
          message.chat.type == "private"
    else {
      stats.ignored += 1
      addEvent(.info, "Ignored message from user \(message.from?.id ?? 0)")
      return
    }

    addInboundMessage(text)
    addEvent(.info, "Received: \(String(text.prefix(100)))")

    /// Command precedence: slash commands are always parsed first.
    if let command = TelegramCommandParser.parse(text) {
      await handleCommand(command, message: message, client: client)
      return
    }

    /// Handle multi-step interaction states first.
    if await handleInteractionState(text: text, message: message, client: client) {
      return
    }

    /// In execute mode, confirm receipt then run the text as a prompt.
    if mode == .execute {
      await sendReply("Message received. Processing...", chatId: message.chat.id, client: client)
      await executePrompt(text, message: message, client: client)
    } else {
      await sendReply(
        "Message received. Current mode (Listen Only) does not allow execution. Switch to Execute mode to run prompts.",
        chatId: message.chat.id,
        client: client
      )
      addEvent(.info, "Passive mode — not executing prompt")
    }
  }

  // MARK: - Command Handling

  private func handleCommand(
    _ command: TelegramCommand,
    message: TelegramAPIMessage,
    client: TelegramBotAPIClient
  ) async {
    switch command {
    case .help:
      await sendReply(TelegramCommandHandler.helpText(), chatId: message.chat.id, client: client)

    case .report:
      let report = delegate?.telegramBotRequestReport() ?? "No app state available."
      await sendReply(report, chatId: message.chat.id, client: client)

    case .showMode:
      await sendReply("Current mode: \(mode.displayName)", chatId: message.chat.id, client: client)

    case .openDirectory:
      await handleOpenDirectory(message: message, client: client)

    case .newTask:
      interactionState = .awaitingNewTaskText
      await sendReply("Send task text.", chatId: message.chat.id, client: client)

    case .unknown(let cmd):
      await sendReply(
        "Unknown command: \(cmd).\n\n\(TelegramCommandHandler.helpText())",
        chatId: message.chat.id,
        client: client
      )
    }
  }

  private func handleOpenDirectory(
    message: TelegramAPIMessage,
    client: TelegramBotAPIClient
  ) async {
    let config = configManager.config
    let result = TelegramCommandHandler.resolveOpenDirectory(
      rootPath: config.telegramRootDirectoryPath,
      subpath: config.telegramPredefinedOpenSubpath
    )

    switch result {
    case .success(let directoryURL):
      guard let delegate else {
        await sendReply("App state not available.", chatId: message.chat.id, client: client)
        return
      }

      let tabMode = config.telegramOpenDirectoryTabMode
      let agent = config.telegramOpenDirectoryAgent
      delegate.telegramBotOpenTab(mode: tabMode, agent: agent, directory: directoryURL)

      await sendReply(
        "Opened \(tabMode.displayName) (\(agent.rawValue)) tab at: \(directoryURL.path)",
        chatId: message.chat.id,
        client: client
      )

    case .failure(let errorMessage):
      await sendReply(errorMessage, chatId: message.chat.id, client: client)
    }
  }

  // MARK: - Multi-step Interaction

  private func handleInteractionState(
    text: String,
    message: TelegramAPIMessage,
    client: TelegramBotAPIClient
  ) async -> Bool {
    switch interactionState {
    case .idle:
      return false

    case .awaitingNewTaskText:
      interactionState = .awaitingNewTaskSchedule(taskText: text)
      await sendReply(
        "When should I start it? Reply: immediately or queue",
        chatId: message.chat.id,
        client: client
      )
      return true

    case .awaitingNewTaskSchedule(let taskText):
      let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

      if normalized == "cancel" {
        interactionState = .idle
        await sendReply("Task creation cancelled.", chatId: message.chat.id, client: client)
        return true
      }

      if normalized == "immediately" || normalized == "immediate" {
        interactionState = .idle

        guard let executor else {
          if enqueueTask(taskText) {
            await sendReply(
              "Executor unavailable. Added to task queue instead.",
              chatId: message.chat.id,
              client: client
            )
          } else {
            await sendReply("App state not available.", chatId: message.chat.id, client: client)
          }

          return true
        }

        if await executor.isBusy() {
          if enqueueTask(taskText) {
            await sendReply(
              "Task is already running. Added this task to queue.",
              chatId: message.chat.id,
              client: client
            )
          } else {
            await sendReply("App state not available.", chatId: message.chat.id, client: client)
          }

          return true
        }

        await sendReply(
          "Starting task now. I will send report when completed.",
          chatId: message.chat.id,
          client: client
        )
        await executePrompt(taskText, message: message, client: client)
        return true
      }

      if normalized == "queue" {
        interactionState = .idle

        if enqueueTask(taskText) {
          await sendReply("Added to task queue.", chatId: message.chat.id, client: client)
        } else {
          await sendReply("App state not available.", chatId: message.chat.id, client: client)
        }

        return true
      }

      await sendReply(
        "Please reply with one option: immediately or queue",
        chatId: message.chat.id,
        client: client
      )
      return true

    }
  }

  // MARK: - Task Queue Bridge

  private func enqueueTask(_ taskText: String) -> Bool {
    guard let delegate else {
      return false
    }

    let config = configManager.config
    let title = String(taskText.prefix(80))
    delegate.telegramBotEnqueueTask(
      title: title,
      prompt: taskText,
      repoPath: workingDirectory.path,
      agentType: config.telegramExecutionAgent
    )

    return true
  }

  // MARK: - Prompt Execution

  private func executePrompt(
    _ prompt: String,
    message: TelegramAPIMessage,
    client: TelegramBotAPIClient
  ) async {
    guard mode == .execute else {
      addEvent(.info, "Skipped execution — not in Execute mode")
      return
    }

    guard let executor else {
      await sendReply("Executor not available.", chatId: message.chat.id, client: client)
      return
    }

    addEvent(.info, "Executing prompt...")
    addSystemMessage("Executing prompt...")

    /// Send typing indicator.
    try? await client.sendChatAction(chatId: message.chat.id)

    do {
      let result = try await executor.execute(prompt: prompt)
      stats.executed += 1
      addEvent(.info, "Execution completed (\(result.count) chars)")
      await sendReply(result, chatId: message.chat.id, replyTo: message.messageId, client: client)
    } catch {
      stats.failed += 1
      addEvent(.error, "Execution failed: \(error.localizedDescription)")
      await sendReply(
        "Execution failed: \(error.localizedDescription)",
        chatId: message.chat.id,
        replyTo: message.messageId,
        client: client
      )
    }
  }

  // MARK: - Message Sending

  private func sendReply(
    _ text: String,
    chatId: Int64,
    replyTo messageId: Int64? = nil,
    client: TelegramBotAPIClient
  ) async {
    let config = configManager.config
    let prefixed = config.telegramReplyPrefix.map { "\($0) \(text)" } ?? text

    let chunks = TelegramMessageChunker.chunk(prefixed)
    for chunk in chunks {
      do {
        try await client.sendMessage(chatId: chatId, text: chunk, replyToMessageId: messageId)
        addOutboundMessage(chunk)
      } catch {
        addEvent(.error, "Failed to send message: \(error.localizedDescription)")
      }
    }
  }

  // MARK: - Event & Message Logging

  private func addEvent(_ level: TelegramEventLevel, _ message: String) {
    let event = TelegramBotEvent(level: level, message: message)
    events.append(event)

    if events.count > maxEvents {
      events.removeFirst(events.count - maxEvents)
    }

    Logger.telegram.log(level: level.osLogType, "\(message)")
  }

  private func addInboundMessage(_ text: String) {
    appendMessage(TelegramTimelineMessage(direction: .inbound, text: text))
  }

  private func addOutboundMessage(_ text: String) {
    appendMessage(TelegramTimelineMessage(direction: .outbound, text: text))
  }

  private func addSystemMessage(_ text: String) {
    appendMessage(TelegramTimelineMessage(direction: .system, text: text))
  }

  private func appendMessage(_ message: TelegramTimelineMessage) {
    messages.append(message)

    if messages.count > maxMessages {
      messages.removeFirst(messages.count - maxMessages)
    }
  }
}

// MARK: - TelegramEventLevel + OSLog

extension TelegramEventLevel {
  var osLogType: OSLogType {
    switch self {
    case .info:
      return .info

    case .warning:
      return .default

    case .error:
      return .error
    }
  }
}
