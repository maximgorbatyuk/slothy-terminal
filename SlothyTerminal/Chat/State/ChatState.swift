import Foundation
import OSLog

/// Thin adapter between `ChatSessionEngine` and the UI layer.
///
/// Owns the engine and the transport. Bridges engine's `@Observable`
/// state to SwiftUI views and executes commands emitted by the engine.
///
/// The public API is unchanged from the original so views don't need updating.
@Observable
class ChatState {
  // MARK: - Public (observed by views)

  /// The conversation model with messages and token counts.
  var conversation: ChatConversation { engine.conversation }

  /// Whether a turn is in progress (sending or streaming).
  var isLoading: Bool { engine.sessionState.isProcessingTurn }

  /// Current error, if any. Settable to allow dismissal from UI.
  var error: ChatSessionError?

  /// Claude session ID from the transport.
  var sessionId: String? { engine.sessionId }

  /// Name of the currently running tool (for streaming indicator).
  var currentToolName: String? { engine.currentToolName }

  /// Current session state (for status bar, future UI).
  var sessionState: ChatSessionState { engine.sessionState }

  /// User-selected chat mode (Build / Plan).
  var selectedMode: ChatMode = .build {
    didSet {
      persistLastOpenCodeSelectionIfNeeded()
    }
  }

  /// User-selected model override (nil = agent default).
  var selectedModel: ChatModelSelection? {
    didSet {
      persistLastOpenCodeSelectionIfNeeded()
    }
  }

  /// Whether OpenCode should ask clarifying questions before implementation.
  var isOpenCodeAskModeEnabled: Bool = false {
    didSet {
      if let ocTransport = transport as? OpenCodeCLITransport {
        ocTransport.askModeEnabled = isOpenCodeAskModeEnabled
      }

      persistLastOpenCodeSelectionIfNeeded()
    }
  }

  /// Metadata resolved from the transport after a turn.
  var resolvedMetadata: ChatResolvedMetadata?

  /// Dynamically discovered OpenCode model list (`opencode models`).
  var openCodeModelOptions: [ChatModelSelection] = []

  // MARK: - Private

  private let engine: ChatSessionEngine
  private let store: ChatSessionStore
  private let configManager: ConfigManager
  let agentType: AgentType
  private var transport: ChatTransport?

  /// Tracks which model the current Claude transport was started with.
  /// Used to detect when a restart is needed on model change.
  private var transportModel: ChatModelSelection?

  /// Pending message to send once transport is ready.
  private var pendingMessageText: String?

  /// Prevent duplicate OpenCode model catalog loads.
  private var didLoadOpenCodeModels = false

  init(
    workingDirectory: URL,
    agentType: AgentType = .claude,
    store: ChatSessionStore = .shared,
    configManager: ConfigManager = .shared
  ) {
    self.engine = ChatSessionEngine(workingDirectory: workingDirectory)
    self.store = store
    self.configManager = configManager
    self.agentType = agentType

    applyLastOpenCodeSelectionIfNeeded()

    self.resolvedMetadata = ChatResolvedMetadata(
      resolvedProviderID: selectedModel?.providerID,
      resolvedModelID: selectedModel?.modelID,
      resolvedMode: selectedMode
    )
  }

  /// Creates a ChatState and restores conversation from a snapshot.
  ///
  /// Use this when resuming a previous session. The engine gets the
  /// restored sessionId so it can use `--resume` when starting transport.
  init(
    workingDirectory: URL,
    agentType: AgentType = .claude,
    resumeSessionId: String,
    store: ChatSessionStore = .shared,
    configManager: ConfigManager = .shared
  ) {
    self.engine = ChatSessionEngine(workingDirectory: workingDirectory)
    self.store = store
    self.configManager = configManager
    self.agentType = agentType

    if let snapshot = store.loadSnapshot(sessionId: resumeSessionId) {
      engine.conversation.restore(from: snapshot)
      engine.restoreSessionId(resumeSessionId)

      if let mode = snapshot.selectedMode {
        self.selectedMode = mode
      }
      self.selectedModel = snapshot.selectedModel
      self.resolvedMetadata = ChatResolvedMetadata(
        resolvedProviderID: self.selectedModel?.providerID,
        resolvedModelID: self.selectedModel?.modelID,
        resolvedMode: self.selectedMode
      )

      if agentType == .opencode {
        self.isOpenCodeAskModeEnabled = configManager.config.lastUsedOpenCodeAskModeEnabled
      }
    } else {
      applyLastOpenCodeSelectionIfNeeded()
      self.resolvedMetadata = ChatResolvedMetadata(
        resolvedProviderID: self.selectedModel?.providerID,
        resolvedModelID: self.selectedModel?.modelID,
        resolvedMode: self.selectedMode
      )
    }
  }

  // MARK: - Public API (unchanged signatures for view compatibility)

  /// Sends a user message and starts streaming the assistant response.
  @MainActor
  func sendMessage(_ text: String) {
    /// Show immediate metadata for the upcoming turn.
    resolvedMetadata = ChatResolvedMetadata(
      resolvedProviderID: selectedModel?.providerID,
      resolvedModelID: selectedModel?.modelID,
      resolvedMode: selectedMode
    )

    switch agentType {
    case .claude:
      /// If model changed since transport started, restart it.
      if selectedModel != transportModel,
         transport != nil
      {
        Logger.chat.info("Model changed, restarting Claude transport")
        transport?.terminate()
        transport = nil
      }

    case .opencode:
      /// OpenCode spawns per message — update model/mode on existing transport.
      if let ocTransport = transport as? OpenCodeCLITransport {
        ocTransport.currentModel = selectedModel
        ocTransport.currentMode = selectedMode
        ocTransport.askModeEnabled = isOpenCodeAskModeEnabled
      }

    default:
      break
    }

    let commands = engine.handle(.userSendMessage(text))
    executeCommands(commands)
  }

  /// Cancels the current streaming response.
  @MainActor
  func cancelResponse() {
    let commands = engine.handle(.userCancel)
    executeCommands(commands)
  }

  /// Clears the conversation and terminates the process.
  @MainActor
  func clearConversation() {
    let commands = engine.handle(.userClear)
    executeCommands(commands)
  }

  /// Retries the last failed message.
  @MainActor
  func retryLastMessage() {
    let commands = engine.handle(.userRetry)
    executeCommands(commands)
  }

  /// Terminates the persistent process. Called when closing the tab.
  func terminateProcess() {
    store.saveImmediately()
    transport?.terminate()
    transport = nil
    pendingMessageText = nil
  }

  // MARK: - Command execution

  @MainActor
  private func executeCommands(_ commands: [ChatSessionCommand]) {
    for command in commands {
      switch command {
      case .startTransport(let dir, let resumeId):
        startTransport(workingDirectory: dir, resumeSessionId: resumeId)

      case .sendMessage(let text):
        if let transport,
           transport.isRunning
        {
          transport.send(message: text)
        } else {
          /// Transport not ready yet — queue the message.
          pendingMessageText = text
        }

      case .interruptTransport:
        transport?.interrupt()

      case .terminateTransport:
        transport?.terminate()
        transport = nil
        pendingMessageText = nil

      case .attemptRecovery(let sessionId, let attempt):
        let delay = recoveryBackoff(attempt: attempt)
        Task { @MainActor [weak self] in
          try? await Task.sleep(for: .seconds(delay))

          guard let self else {
            return
          }

          Logger.chat.info("Recovery attempt \(attempt) after \(delay)s delay")
          self.startTransport(
            workingDirectory: self.engine.conversation.workingDirectory,
            resumeSessionId: sessionId
          )
        }

      case .persistSnapshot:
        if let sessionId = engine.sessionId {
          let snapshot = engine.conversation.toSnapshot(
            sessionId: sessionId,
            selectedMode: selectedMode,
            selectedModel: selectedModel
          )
          store.save(snapshot: snapshot)
        }

      case .turnComplete:
        /// UI updates automatically via @Observable.
        error = nil

        if agentType == .opencode,
           let sessionId = engine.sessionId,
           !sessionId.isEmpty
        {
          refreshOpenCodeResolvedMetadata(sessionId: sessionId)
        }

      case .surfaceError(let sessionError):
        error = sessionError
      }
    }
  }

  // MARK: - Transport lifecycle

  @MainActor
  private func startTransport(workingDirectory: URL, resumeSessionId: String?) {
    /// Terminate any existing transport.
    transport?.terminate()

    let newTransport: ChatTransport
    switch agentType {
    case .opencode:
      let customExecutablePath = configManager.customPath(for: .opencode)
      newTransport = OpenCodeCLITransport(
        workingDirectory: workingDirectory,
        resumeSessionId: resumeSessionId,
        currentModel: selectedModel,
        currentMode: selectedMode,
        askModeEnabled: isOpenCodeAskModeEnabled,
        executablePathOverride: customExecutablePath
      )

    default:
      newTransport = ClaudeCLITransport(
        workingDirectory: workingDirectory,
        resumeSessionId: resumeSessionId,
        selectedModel: selectedModel
      )
      transportModel = selectedModel
    }
    self.transport = newTransport

    newTransport.start(
      onEvent: { [weak self] event in
        Task { @MainActor in
          guard let self else {
            return
          }

          let commands = self.engine.handle(.transportStreamEvent(event))
          self.executeCommands(commands)
        }
      },
      onReady: { [weak self] sessionId in
        Task { @MainActor in
          guard let self else {
            return
          }

          let commands = self.engine.handle(.transportReady(sessionId: sessionId))
          self.executeCommands(commands)

          /// If a message was queued while transport was starting, send it now.
          if let pending = self.pendingMessageText {
            self.pendingMessageText = nil
            self.transport?.send(message: pending)
          }
        }
      },
      onError: { [weak self] error in
        Task { @MainActor in
          guard let self else {
            return
          }

          let commands = self.engine.handle(.transportError(error))
          self.executeCommands(commands)
        }
      },
      onTerminated: { [weak self] reason in
        Task { @MainActor in
          guard let self else {
            return
          }

          let commands = self.engine.handle(.transportTerminated(reason: reason))
          self.executeCommands(commands)
        }
      }
    )
  }

  // MARK: - Recovery

  /// Exponential backoff for recovery attempts: 1s, 2s, 4s.
  private func recoveryBackoff(attempt: Int) -> Double {
    pow(2.0, Double(attempt - 1))
  }

  // MARK: - Model catalog

  /// Loads OpenCode models once and exposes them to the composer dropdown.
  @MainActor
  func refreshModelCatalogIfNeeded(for agentType: AgentType) {
    guard agentType == .opencode,
          !didLoadOpenCodeModels
    else {
      return
    }

    didLoadOpenCodeModels = true

    Task.detached { [weak self] in
      guard let self,
            let models = self.loadOpenCodeModels(),
            !models.isEmpty
      else {
        return
      }

      await MainActor.run {
        self.openCodeModelOptions = models
      }
    }
  }

  private func loadOpenCodeModels() -> [ChatModelSelection]? {
    let process = Process()
    let stdout = Pipe()
    let stderr = Pipe()

    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["opencode", "models"]
    process.standardOutput = stdout
    process.standardError = stderr

    var env = ProcessInfo.processInfo.environment
    let extraPaths = [
      "/opt/homebrew/bin",
      "/usr/local/bin",
      "\(NSHomeDirectory())/.local/bin",
    ]
    let existingPath = env["PATH"] ?? "/usr/bin:/bin"
    env["PATH"] = (extraPaths + [existingPath]).joined(separator: ":")
    process.environment = env

    do {
      try process.run()
      process.waitUntilExit()
    } catch {
      Logger.chat.warning("OpenCode model list failed to start: \(error.localizedDescription)")
      return nil
    }

    guard process.terminationStatus == 0 else {
      let errorText = String(
        data: stderr.fileHandleForReading.readDataToEndOfFile(),
        encoding: .utf8
      ) ?? ""
      Logger.chat.warning("OpenCode model list failed: \(errorText.prefix(200))")
      return nil
    }

    let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
    guard let output = String(data: outputData, encoding: .utf8) else {
      return nil
    }

    var seen = Set<String>()
    var models: [ChatModelSelection] = []

    for line in output.split(whereSeparator: \.isNewline) {
      let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !value.isEmpty else {
        continue
      }

      let parts = value.split(separator: "/", maxSplits: 1).map(String.init)
      guard parts.count == 2 else {
        continue
      }

      let providerID = parts[0]
      let modelID = parts[1]
      let key = "\(providerID)/\(modelID)"

      guard !seen.contains(key) else {
        continue
      }
      seen.insert(key)

      models.append(ChatModelSelection(
        providerID: providerID,
        modelID: modelID,
        displayName: key
      ))
    }

    return models.sorted { $0.displayName < $1.displayName }
  }

  // MARK: - OpenCode metadata resolution

  /// Refreshes resolved model and mode by exporting the OpenCode session.
  private func refreshOpenCodeResolvedMetadata(sessionId: String) {
    Task.detached { [weak self] in
      guard let self else {
        return
      }

      guard let metadata = self.loadOpenCodeMetadata(sessionId: sessionId) else {
        return
      }

      await MainActor.run {
        self.resolvedMetadata = metadata
      }
    }
  }

  private func loadOpenCodeMetadata(sessionId: String) -> ChatResolvedMetadata? {
    let process = Process()
    let stdout = Pipe()
    let stderr = Pipe()

    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["opencode", "export", sessionId]
    process.standardOutput = stdout
    process.standardError = stderr

    do {
      try process.run()
      process.waitUntilExit()
    } catch {
      Logger.chat.warning("OpenCode metadata export failed to start: \(error.localizedDescription)")
      return nil
    }

    guard process.terminationStatus == 0 else {
      let errorText = String(
        data: stderr.fileHandleForReading.readDataToEndOfFile(),
        encoding: .utf8
      ) ?? ""
      Logger.chat.warning("OpenCode metadata export failed: \(errorText.prefix(200))")
      return nil
    }

    let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
    guard let rawOutput = String(data: outputData, encoding: .utf8),
          let jsonStart = rawOutput.firstIndex(of: "{")
    else {
      return nil
    }

    let jsonText = String(rawOutput[jsonStart...])
    guard let jsonData = jsonText.data(using: .utf8),
          let root = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
          let messages = root["messages"] as? [[String: Any]]
    else {
      return nil
    }

    for message in messages.reversed() {
      guard let info = message["info"] as? [String: Any],
            (info["role"] as? String) == "assistant"
      else {
        continue
      }

      let provider = info["providerID"] as? String
      let model = info["modelID"] as? String
      let modeString = (info["mode"] as? String) ?? (info["agent"] as? String)

      let mode: ChatMode?
      switch modeString?.lowercased() {
      case "plan":
        mode = .plan

      case "build":
        mode = .build

      default:
        mode = nil
      }

      return ChatResolvedMetadata(
        resolvedProviderID: provider,
        resolvedModelID: model,
        resolvedMode: mode
      )
    }

    return nil
  }

  /// Applies persisted OpenCode model/mode defaults to new chat tabs.
  private func applyLastOpenCodeSelectionIfNeeded() {
    guard agentType == .opencode else {
      return
    }

    if selectedModel == nil {
      selectedModel = configManager.config.lastUsedOpenCodeModel
    }

    if let lastMode = configManager.config.lastUsedOpenCodeMode {
      selectedMode = lastMode
    }

    isOpenCodeAskModeEnabled = configManager.config.lastUsedOpenCodeAskModeEnabled
  }

  /// Persists the latest OpenCode model/mode selection to app config.
  private func persistLastOpenCodeSelectionIfNeeded() {
    guard agentType == .opencode else {
      return
    }

    if configManager.config.lastUsedOpenCodeModel != selectedModel {
      configManager.config.lastUsedOpenCodeModel = selectedModel
    }

    if configManager.config.lastUsedOpenCodeMode != selectedMode {
      configManager.config.lastUsedOpenCodeMode = selectedMode
    }

    if configManager.config.lastUsedOpenCodeAskModeEnabled != isOpenCodeAskModeEnabled {
      configManager.config.lastUsedOpenCodeAskModeEnabled = isOpenCodeAskModeEnabled
    }
  }
}
