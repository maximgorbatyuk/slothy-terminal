import Foundation

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

  // MARK: - Private

  private let engine: ChatSessionEngine
  private let store: ChatSessionStore
  private var transport: ChatTransport?

  /// Pending message to send once transport is ready.
  private var pendingMessageText: String?

  init(workingDirectory: URL, store: ChatSessionStore = .shared) {
    self.engine = ChatSessionEngine(workingDirectory: workingDirectory)
    self.store = store
  }

  /// Creates a ChatState and restores conversation from a snapshot.
  ///
  /// Use this when resuming a previous session. The engine gets the
  /// restored sessionId so it can use `--resume` when starting transport.
  init(
    workingDirectory: URL,
    resumeSessionId: String,
    store: ChatSessionStore = .shared
  ) {
    self.engine = ChatSessionEngine(workingDirectory: workingDirectory)
    self.store = store

    if let snapshot = store.loadSnapshot(sessionId: resumeSessionId) {
      engine.conversation.restore(from: snapshot)
      engine.restoreSessionId(resumeSessionId)
    }
  }

  // MARK: - Public API (unchanged signatures for view compatibility)

  /// Sends a user message and starts streaming the assistant response.
  @MainActor
  func sendMessage(_ text: String) {
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

      case .attemptRecovery(let sessionId, _):
        startTransport(
          workingDirectory: engine.conversation.workingDirectory,
          resumeSessionId: sessionId
        )

      case .persistSnapshot:
        if let sessionId = engine.sessionId {
          let snapshot = engine.conversation.toSnapshot(sessionId: sessionId)
          store.save(snapshot: snapshot)
        }

      case .turnComplete:
        /// UI updates automatically via @Observable.
        error = nil

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

    let newTransport = ClaudeCLITransport(
      workingDirectory: workingDirectory,
      resumeSessionId: resumeSessionId
    )
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
}
