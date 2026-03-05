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
  var isExecutingPrompt: Bool = false

  /// Active relay session bridging Telegram to a terminal tab.
  var relaySession: TelegramRelaySession?

  /// Delegate for app-level actions (report, open tab, enqueue task).
  weak var delegate: TelegramBotDelegate?

  private var pollingTask: Task<Void, Never>?
  private var executor: TelegramPromptExecutor?
  private var outputPoller: TerminalOutputPoller?
  var relayChatId: Int64?
  var relayClient: TelegramBotAPIClient?
  private let workingDirectory: URL
  private let configManager = ConfigManager.shared

  /// Maximum events/messages to keep in memory.
  private let maxEvents = 500
  private let maxMessages = 200

  init(workingDirectory: URL) {
    self.workingDirectory = workingDirectory
  }

  // MARK: - Lifecycle

  /// Starts the bot in execute mode.
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

    mode = .execute
    status = .running

    addEvent(.info, "Starting bot in \(TelegramBotMode.execute.displayName) mode")
    addSystemMessage("Bot started in \(TelegramBotMode.execute.displayName) mode")

    executor = TelegramPromptExecutor(
      workingDirectory: workingDirectory,
      agentType: config.telegramExecutionAgent
    )

    let client = TelegramBotAPIClient(token: token)
    pollingTask = Task { [weak self] in
      await self?.pollingLoop(client: client)
    }

    if let chatId = config.telegramAllowedUserID {
      Task { [weak self] in
        await self?.sendStartupAnnouncement(client: client, chatId: chatId)
      }
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

    stopRelay()

    mode = .stopped
    status = .idle
    interactionState = .idle

    addEvent(.info, "Bot stopped")
    addSystemMessage("Bot stopped")
  }

  // MARK: - Startup Announcement

  private func sendStartupAnnouncement(client: TelegramBotAPIClient, chatId: Int64) async {
    do {
      try await client.sendMessage(chatId: chatId, text: "Ready for commands")
      addEvent(.info, "Startup announcement sent")
    } catch {
      addEvent(.warning, "Failed to send startup announcement: \(error.localizedDescription)")
      return
    }

    guard let delegate else {
      return
    }

    let statement = await delegate.telegramBotStartupStatement(workingDirectory: workingDirectory)

    do {
      try await client.sendMessage(chatId: chatId, text: statement)
      addEvent(.info, "Startup status sent")
    } catch {
      addEvent(.warning, "Failed to send startup status: \(error.localizedDescription)")
    }
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

  func handleUpdate(_ update: TelegramUpdate, client: TelegramBotAPIClient) async {
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

    /// Active AI terminal tab (Claude/OpenCode) wins for plain text.
    /// On failure, we return immediately (no relay fallback) to avoid
    /// silently redirecting to a different tab.
    if let aiTab = delegate?.telegramBotActiveInjectableAITab() {
      let request = InjectionRequest(
        payload: telegramCommandPayload(text: text, agentType: aiTab.agentType),
        target: .tabId(aiTab.id),
        origin: .telegram
      )

      if let result = delegate?.telegramBotInject(request),
         result.status == .completed || result.status == .written
      {
        addEvent(.info, "Injected into AI tab \(aiTab.name): \(String(text.prefix(80)))")
        ensureRelayToTab(aiTab, chatId: message.chat.id, client: client)
        return
      } else {
        await sendReply(
          "Injection into \(aiTab.name) failed.",
          chatId: message.chat.id,
          client: client
        )
        addEvent(.warning, "Injection into AI tab \(aiTab.name) failed")
        return
      }
    }

    /// Fallback: relay session if active and no AI tab available.
    if let relay = relaySession, relay.status == .active {
      let relayAgent = delegate?
        .telegramBotListRelayableTabs()
        .first(where: { $0.id == relay.tabId })?
        .agentType

      let request = InjectionRequest(
        payload: telegramCommandPayload(text: text, agentType: relayAgent),
        target: .tabId(relay.tabId),
        origin: .telegram
      )

      if let result = delegate?.telegramBotInject(request),
         result.status == .completed || result.status == .written
      {
        addEvent(.info, "Relayed command to tab: \(String(text.prefix(80)))")
        return
      } else {
        stopRelay()
        await sendReply(
          "Injection failed. Tab may have closed. Relay stopped.",
          chatId: message.chat.id,
          client: client
        )
        return
      }
    }

    /// No eligible target — inform the user.
    await sendReply(
      "No active AI terminal tab (Claude or OpenCode). Open one and try again.",
      chatId: message.chat.id,
      client: client
    )
    addEvent(.info, "No eligible AI tab for plain text injection")
  }

  private func telegramCommandPayload(text: String, agentType: AgentType?) -> InjectionPayload {
    if agentType == .opencode {
      return .text(text + "\n")
    }

    return .command(text, submit: .execute)
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

    case .openDirectory:
      await handleOpenDirectory(message: message, client: client)

    case .newTask:
      interactionState = .awaitingNewTaskText
      await sendReply("Send task text.", chatId: message.chat.id, client: client)

    case .relayTabs:
      await handleRelayTabs(message: message, client: client)

    case .relayStart:
      await handleRelayStart(message: message, client: client)

    case .relayStop:
      if relaySession != nil {
        stopRelay()
        await sendReply("Relay stopped.", chatId: message.chat.id, client: client)
      } else {
        await sendReply("No relay active.", chatId: message.chat.id, client: client)
      }

    case .relayStatus:
      await handleRelayStatus(message: message, client: client)

    case .relayInterrupt:
      await handleRelayInterrupt(message: message, client: client)

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

    case .awaitingRelayTabChoice(let tabs):
      let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

      if normalized == "cancel" {
        interactionState = .idle
        await sendReply("Relay cancelled.", chatId: message.chat.id, client: client)
        return true
      }

      guard let index = Int(normalized),
            index >= 1,
            index <= tabs.count
      else {
        await sendReply(
          "Reply with a number (1–\(tabs.count)) or cancel.",
          chatId: message.chat.id,
          client: client
        )
        return true
      }

      let chosen = tabs[index - 1]
      interactionState = .idle
      startRelay(tab: chosen, chatId: message.chat.id, client: client)
      await sendReply(
        "Relay started to: \(chosen.name)",
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

  // MARK: - Relay

  private func handleRelayTabs(
    message: TelegramAPIMessage,
    client: TelegramBotAPIClient
  ) async {
    guard let delegate else {
      await sendReply("App state not available.", chatId: message.chat.id, client: client)
      return
    }

    let tabs = delegate.telegramBotListRelayableTabs()

    if tabs.isEmpty {
      await sendReply("No injectable terminal tabs open.", chatId: message.chat.id, client: client)
      return
    }

    let list = formatRelayTabList(tabs)
    await sendReply("Terminal tabs:\n\(list)", chatId: message.chat.id, client: client)
  }

  private func handleRelayStart(
    message: TelegramAPIMessage,
    client: TelegramBotAPIClient
  ) async {
    if let relay = relaySession, relay.status == .active {
      await sendReply(
        "Relay already active to: \(relay.tabName). Use /relay_stop first.",
        chatId: message.chat.id,
        client: client
      )
      return
    }

    guard let delegate else {
      await sendReply("App state not available.", chatId: message.chat.id, client: client)
      return
    }

    let tabs = delegate.telegramBotListRelayableTabs()

    if tabs.isEmpty {
      await sendReply("No injectable terminal tabs open.", chatId: message.chat.id, client: client)
      return
    }

    if tabs.count == 1 {
      startRelay(tab: tabs[0], chatId: message.chat.id, client: client)
      await sendReply(
        "Relay started to: \(tabs[0].name)",
        chatId: message.chat.id,
        client: client
      )
      return
    }

    interactionState = .awaitingRelayTabChoice(tabs: tabs)

    let list = formatRelayTabList(tabs)
    await sendReply(
      "Which tab?\n\(list)\n\nReply with a number or cancel.",
      chatId: message.chat.id,
      client: client
    )
  }

  private func handleRelayStatus(
    message: TelegramAPIMessage,
    client: TelegramBotAPIClient
  ) async {
    guard let relay = relaySession else {
      await sendReply("No relay active.", chatId: message.chat.id, client: client)
      return
    }

    let duration = Int(Date().timeIntervalSince(relay.startedAt))
    let lastOutput = relay.lastOutputTimestamp
      .map { "\(Int(Date().timeIntervalSince($0)))s ago" } ?? "none"
    await sendReply(
      "Relay: \(relay.tabName)\nDuration: \(duration)s\nLast output: \(lastOutput)",
      chatId: message.chat.id,
      client: client
    )
  }

  private func handleRelayInterrupt(
    message: TelegramAPIMessage,
    client: TelegramBotAPIClient
  ) async {
    guard let relay = relaySession, relay.status == .active else {
      await sendReply("No relay active.", chatId: message.chat.id, client: client)
      return
    }

    let request = InjectionRequest(
      payload: .control(.ctrlC),
      target: .tabId(relay.tabId),
      origin: .telegram
    )

    if let result = delegate?.telegramBotInject(request),
       result.status == .completed || result.status == .written
    {
      await sendReply("Sent Ctrl+C.", chatId: message.chat.id, client: client)
    } else {
      await sendReply("Failed to send interrupt.", chatId: message.chat.id, client: client)
    }
  }

  private func formatRelayTabList(_ tabs: [TelegramRelayTabInfo]) -> String {
    tabs.enumerated().map { index, tab in
      let active = tab.isActive ? " [active]" : ""
      return "\(index + 1)) \(tab.name) (\(tab.agentType.rawValue))\(active)"
    }.joined(separator: "\n")
  }

  private func startRelay(tab: TelegramRelayTabInfo, chatId: Int64, client: TelegramBotAPIClient) {
    relaySession = TelegramRelaySession(
      tabId: tab.id,
      tabName: tab.name,
      startedAt: Date(),
      status: .active
    )
    relayChatId = chatId
    relayClient = client

    let poller = TerminalOutputPoller(tabId: tab.id)
    outputPoller = poller

    poller.start(
      handler: { [weak self] text in
        guard let self else { return }
        self.relaySession?.lastOutputTimestamp = Date()
        Task { [weak self] in
          await self?.sendRelayOutput(text)
        }
      },
      surfaceLost: { [weak self] in
        guard let self else { return }
        // Capture before stopRelay() clears them.
        let chatId = self.relayChatId
        let client = self.relayClient
        self.stopRelay()
        if let chatId, let client {
          Task { [weak self] in
            await self?.sendReply(
              "Tab closed. Relay stopped.",
              chatId: chatId,
              client: client
            )
          }
        }
      }
    )

    addEvent(.info, "Relay started to tab: \(tab.name)")
    addSystemMessage("Relay started to: \(tab.name)")
  }

  private func ensureRelayToTab(
    _ tab: TelegramRelayTabInfo,
    chatId: Int64,
    client: TelegramBotAPIClient
  ) {
    if let relay = relaySession,
       relay.status == .active,
       relay.tabId == tab.id,
       relayChatId == chatId
    {
      return
    }

    if relaySession != nil {
      stopRelay()
    }

    startRelay(tab: tab, chatId: chatId, client: client)
  }

  private func stopRelay() {
    outputPoller?.stop()
    outputPoller = nil

    guard let relay = relaySession else {
      return
    }

    relaySession = nil
    relayChatId = nil
    relayClient = nil

    addEvent(.info, "Relay stopped (tab: \(relay.tabName))")
    addSystemMessage("Relay stopped")
  }

  private func sendRelayOutput(_ text: String) async {
    guard let chatId = relayChatId, let client = relayClient else {
      return
    }

    let chunks = TelegramMessageChunker.chunk(text)
    for chunk in chunks {
      do {
        try await client.sendMessage(chatId: chatId, text: chunk)
        addOutboundMessage(chunk)
      } catch {
        addEvent(.error, "Failed to send relay output: \(error.localizedDescription)")
      }
    }
  }

  // MARK: - Prompt Execution

  private func executePrompt(
    _ prompt: String,
    message: TelegramAPIMessage,
    client: TelegramBotAPIClient
  ) async {
    guard let executor else {
      await sendReply("Executor not available.", chatId: message.chat.id, client: client)
      return
    }

    addEvent(.info, "Executing prompt...")
    addSystemMessage("Executing prompt...")

    isExecutingPrompt = true
    defer { isExecutingPrompt = false }

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
