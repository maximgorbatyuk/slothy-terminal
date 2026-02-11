import Foundation
import OSLog

/// Pure state machine and turn orchestrator for chat sessions.
///
/// Receives events, updates state, and emits commands for the adapter
/// (`ChatState`) to execute. Does no I/O, no process management, no
/// UI work — only state transitions and conversation mutation.
@Observable
class ChatSessionEngine {
  // MARK: - Observable state (read by ChatState adapter)

  /// Current session state.
  private(set) var sessionState: ChatSessionState = .idle

  /// The conversation model (messages, tokens).
  private(set) var conversation: ChatConversation

  /// Claude session ID from the transport.
  private(set) var sessionId: String?

  /// Name of the currently running tool (for streaming indicator).
  private(set) var currentToolName: String?

  // MARK: - Internal state

  /// The currently streaming assistant message.
  private var currentMessage: ChatMessage?

  /// The last user message text (for retry).
  private var lastUserMessageText: String?

  /// Number of crash recovery attempts made.
  private var recoveryAttempts: Int = 0

  /// Maximum number of recovery attempts before giving up.
  private let maxRecoveryAttempts: Int = 3

  init(workingDirectory: URL) {
    self.conversation = ChatConversation(workingDirectory: workingDirectory)
  }

  /// Transitions to a new state with logging.
  private func transitionTo(_ newState: ChatSessionState) {
    let oldState = sessionState
    sessionState = newState
    Logger.chat.info("Engine: \(String(describing: oldState)) → \(String(describing: newState))")
  }

  /// Restores a session ID from a persisted snapshot.
  ///
  /// Used during resume so the engine knows which session to reconnect to.
  func restoreSessionId(_ id: String) {
    sessionId = id
  }

  // MARK: - Public API

  /// Process an event and return commands for the adapter to execute.
  func handle(_ event: ChatSessionEvent) -> [ChatSessionCommand] {
    switch event {
    case .userSendMessage(let text):
      return handleUserSendMessage(text)

    case .userCancel:
      return handleUserCancel()

    case .userClear:
      return handleUserClear()

    case .userRetry:
      return handleUserRetry()

    case .transportReady(let sessionId):
      return handleTransportReady(sessionId)

    case .transportStreamEvent(let streamEvent):
      return handleStreamEvent(streamEvent)

    case .transportError(let error):
      return handleTransportError(error)

    case .transportTerminated(let reason):
      return handleTransportTerminated(reason)

    case .recoveryAttempt(let attempt):
      return handleRecoveryAttempt(attempt)

    case .recoveryFailed:
      return handleRecoveryFailed()
    }
  }

  // MARK: - User event handlers

  private func handleUserSendMessage(_ text: String) -> [ChatSessionCommand] {
    guard sessionState.canSendMessage else {
      return [.surfaceError(.invalidState("Cannot send message in state: \(sessionState)"))]
    }

    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !trimmed.isEmpty else {
      return []
    }

    lastUserMessageText = trimmed

    /// Add user message to conversation.
    let userMessage = ChatMessage(role: .user, contentBlocks: [.text(trimmed)])
    conversation.addMessage(userMessage)

    /// Create assistant message placeholder.
    let assistantMessage = ChatMessage(role: .assistant, isStreaming: true)
    conversation.addMessage(assistantMessage)
    currentMessage = assistantMessage

    /// Determine whether transport needs starting.
    let needsTransportStart = sessionState == .idle

    transitionTo(.sending)

    var commands: [ChatSessionCommand] = []

    if needsTransportStart {
      commands.append(.startTransport(
        workingDirectory: conversation.workingDirectory,
        resumeSessionId: sessionId
      ))
    }

    commands.append(.sendMessage(trimmed))
    return commands
  }

  private func handleUserCancel() -> [ChatSessionCommand] {
    guard sessionState.canCancel else {
      return []
    }

    transitionTo(.cancelling)

    /// Finalize the current streaming message.
    if let message = currentMessage {
      message.isStreaming = false
    }

    currentMessage = nil
    currentToolName = nil

    return [.interruptTransport, .persistSnapshot]
  }

  private func handleUserClear() -> [ChatSessionCommand] {
    conversation.clear()
    sessionId = nil
    currentMessage = nil
    currentToolName = nil
    lastUserMessageText = nil
    recoveryAttempts = 0
    transitionTo(.idle)

    return [.terminateTransport]
  }

  private func handleUserRetry() -> [ChatSessionCommand] {
    guard let lastText = lastUserMessageText else {
      return []
    }

    /// Remove the last assistant message if it exists.
    if let lastAssistant = conversation.messages.last,
       lastAssistant.role == .assistant
    {
      conversation.removeMessage(lastAssistant)
    }

    /// Remove the previous user message to avoid duplication
    /// since handleUserSendMessage will append a new one.
    if let lastUser = conversation.messages.last,
       lastUser.role == .user
    {
      conversation.removeMessage(lastUser)
    }

    currentMessage = nil
    currentToolName = nil

    /// Re-send through the normal path.
    return handleUserSendMessage(lastText)
  }

  // MARK: - Transport event handlers

  private func handleTransportReady(_ sessionId: String) -> [ChatSessionCommand] {
    self.sessionId = sessionId

    if sessionState == .starting || sessionState == .sending {
      /// If we were starting, move to ready. If sending, stay in sending
      /// (the message will be sent once transport is ready).
      if sessionState == .starting {
        transitionTo(.ready)
      }
    }

    recoveryAttempts = 0
    return []
  }

  private func handleStreamEvent(_ event: StreamEvent) -> [ChatSessionCommand] {
    /// Ignore stream events while cancelling — they're remnants from
    /// the interrupted stream before the process exits.
    if sessionState == .cancelling {
      return []
    }

    switch event {
    case .system(let sid):
      sessionId = sid

    case .assistant(let content, let inputTokens, let outputTokens):
      handleAssistantSnapshot(content: content, inputTokens: inputTokens, outputTokens: outputTokens)

    case .userToolResult(let toolUseId, let content, _):
      appendToolResult(toolUseId: toolUseId, content: content)

    case .result(_, let inputTokens, let outputTokens):
      return handleResult(inputTokens: inputTokens, outputTokens: outputTokens)

    case .messageStart(let inputTokens):
      if currentMessage == nil {
        let assistantMessage = ChatMessage(role: .assistant, isStreaming: true)
        conversation.addMessage(assistantMessage)
        currentMessage = assistantMessage
      }

      if sessionState == .sending {
        transitionTo(.streaming)
      }
      currentMessage?.inputTokens = inputTokens

    case .contentBlockStart(let index, let blockType, let id, let name):
      handleContentBlockStart(index: index, blockType: blockType, id: id, name: name)

    case .contentBlockDelta(let index, let deltaType, let text):
      handleContentBlockDelta(index: index, deltaType: deltaType, text: text)

    case .contentBlockStop:
      currentToolName = nil

    case .messageDelta(_, let outputTokens):
      currentMessage?.outputTokens = outputTokens

    case .messageStop:
      return handleMessageStop()

    case .unknown:
      break
    }

    return []
  }

  private func handleTransportError(_ error: Error) -> [ChatSessionCommand] {
    /// If we have a session ID and haven't exceeded retries, try recovery.
    if let sessionId,
       recoveryAttempts < maxRecoveryAttempts
    {
      recoveryAttempts += 1
      transitionTo(.recovering(attempt: recoveryAttempts))

      if let message = currentMessage {
        message.isStreaming = false
      }

      currentMessage = nil
      currentToolName = nil

      return [.attemptRecovery(sessionId: sessionId, attempt: recoveryAttempts)]
    }

    /// Unrecoverable.
    let sessionError = ChatSessionError.transportStartFailed(error.localizedDescription)
    transitionTo(.failed(sessionError))

    if let message = currentMessage {
      message.isStreaming = false
    }

    currentMessage = nil
    currentToolName = nil

    return [.surfaceError(sessionError)]
  }

  private func handleTransportTerminated(_ reason: TerminationReason) -> [ChatSessionCommand] {
    switch reason {
    case .normal:
      if let message = currentMessage {
        message.isStreaming = false
      }
      currentMessage = nil
      currentToolName = nil
      transitionTo(.idle)
      return []

    case .crash(let exitCode, let stderr):
      /// Try recovery if possible.
      if let sessionId,
         recoveryAttempts < maxRecoveryAttempts
      {
        recoveryAttempts += 1
        transitionTo(.recovering(attempt: recoveryAttempts))

        if let message = currentMessage {
          message.isStreaming = false
        }

        currentMessage = nil
        currentToolName = nil

        return [.attemptRecovery(sessionId: sessionId, attempt: recoveryAttempts)]
      }

      /// Unrecoverable crash.
      let sessionError = ChatSessionError.transportCrashed(exitCode: exitCode, stderr: stderr)
      transitionTo(.failed(sessionError))

      if let message = currentMessage {
        message.isStreaming = false
      }

      currentMessage = nil
      currentToolName = nil

      return [.surfaceError(sessionError)]

    case .cancelled:
      if let message = currentMessage {
        message.isStreaming = false
      }
      currentMessage = nil
      currentToolName = nil
      transitionTo(.ready)
      return [.persistSnapshot]
    }
  }

  // MARK: - Recovery event handlers

  private func handleRecoveryAttempt(_ attempt: Int) -> [ChatSessionCommand] {
    transitionTo(.recovering(attempt: attempt))

    guard let sessionId else {
      return handleRecoveryFailed()
    }

    return [.attemptRecovery(sessionId: sessionId, attempt: attempt)]
  }

  private func handleRecoveryFailed() -> [ChatSessionCommand] {
    let sessionError = ChatSessionError.maxRetriesExceeded(recoveryAttempts)
    transitionTo(.failed(sessionError))
    return [.surfaceError(sessionError)]
  }

  // MARK: - Stream event detail handlers

  private func handleAssistantSnapshot(
    content: [AssistantContentBlock],
    inputTokens: Int,
    outputTokens: Int
  ) {
    guard let message = currentMessage else {
      return
    }

    if sessionState == .sending {
      transitionTo(.streaming)
    }

    /// If streaming deltas already built the content, skip replacing
    /// to preserve the incrementally-rendered blocks. Only use the
    /// assistant snapshot when no streaming content was received.
    if message.contentBlocks.isEmpty {
      var blocks: [ChatContentBlock] = []

      for block in content {
        switch block.type {
        case "text":
          if !block.text.isEmpty {
            blocks.append(.text(block.text))
          }

        case "thinking":
          if !block.text.isEmpty {
            blocks.append(.thinking(block.text))
          }

        case "tool_use":
          blocks.append(.toolUse(
            id: block.id ?? "",
            name: block.name ?? "",
            input: block.input ?? ""
          ))

        case "tool_result":
          blocks.append(.toolResult(
            toolUseId: block.id ?? "",
            content: block.text
          ))

        default:
          if !block.text.isEmpty {
            blocks.append(.text(block.text))
          }
        }
      }

      message.contentBlocks = blocks
    }

    message.inputTokens = inputTokens
    message.outputTokens = outputTokens
  }

  private func handleContentBlockStart(index: Int, blockType: String, id: String?, name: String?) {
    guard let message = currentMessage else {
      return
    }

    if sessionState == .sending {
      transitionTo(.streaming)
    }

    let block: ChatContentBlock
    switch blockType {
    case "thinking":
      block = .thinking("")

    case "tool_use":
      block = .toolUse(id: id ?? "", name: name ?? "", input: "")
      currentToolName = name

    default:
      block = .text("")
    }

    /// Ensure contentBlocks array is large enough for this index.
    while message.contentBlocks.count <= index {
      message.contentBlocks.append(.text(""))
    }

    message.contentBlocks[index] = block
  }

  private func handleContentBlockDelta(index: Int, deltaType: String, text: String) {
    guard let message = currentMessage,
          index < message.contentBlocks.count
    else {
      return
    }

    if sessionState == .sending {
      transitionTo(.streaming)
    }

    let existing = message.contentBlocks[index]
    switch (existing, deltaType) {
    case (.text(let current), "text_delta"):
      message.contentBlocks[index] = .text(current + text)

    case (.thinking(let current), "thinking_delta"):
      message.contentBlocks[index] = .thinking(current + text)

    case (.toolUse(let id, let name, let input), "input_json_delta"):
      message.contentBlocks[index] = .toolUse(id: id, name: name, input: input + text)
      currentToolName = name.isEmpty ? nil : name

    default:
      break
    }
  }

  private func handleResult(inputTokens: Int, outputTokens: Int) -> [ChatSessionCommand] {
    let message = currentMessage ?? conversation.messages.last(where: { $0.role == .assistant })

    guard let message else {
      transitionTo(.ready)
      currentToolName = nil
      return [.turnComplete, .persistSnapshot]
    }

    message.isStreaming = false

    if inputTokens > 0 {
      message.inputTokens = inputTokens
    }

    if outputTokens > 0 {
      message.outputTokens = outputTokens
    }

    conversation.totalInputTokens += message.inputTokens
    conversation.totalOutputTokens += message.outputTokens

    currentMessage = nil
    currentToolName = nil
    transitionTo(.ready)

    return [.turnComplete, .persistSnapshot]
  }

  private func handleMessageStop() -> [ChatSessionCommand] {
    guard let message = currentMessage else {
      return []
    }

    message.isStreaming = false
    currentMessage = nil
    currentToolName = nil

    /// In stream-json mode a single turn can emit multiple assistant
    /// segments (e.g. tool_use -> tool_result -> final text). Keep the
    /// turn active and wait for `result` to mark completion.
    if sessionState.isProcessingTurn {
      transitionTo(.sending)
    }

    return []
  }

  private func appendToolResult(toolUseId: String, content: String) {
    guard !toolUseId.isEmpty else {
      return
    }

    if let message = currentMessage {
      message.contentBlocks.append(.toolResult(toolUseId: toolUseId, content: content))
      return
    }

    if let lastAssistant = conversation.messages.last(where: { $0.role == .assistant }) {
      lastAssistant.contentBlocks.append(.toolResult(toolUseId: toolUseId, content: content))
    }
  }

}
