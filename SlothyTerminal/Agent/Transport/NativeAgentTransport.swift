import Foundation
import OSLog

/// Protocol abstracting the agent loop for testability.
protocol AgentLoopProtocol: Sendable {
  func run(
    input: RuntimeInput,
    messages: inout [[String: JSONValue]],
    context: ToolContext,
    onEvent: AgentEventHandler?
  ) async throws -> String
}

extension AgentLoop: AgentLoopProtocol {}

/// A `ChatTransport` implementation backed by the native agent system.
///
/// Maps `AgentLoopEvent`s to `StreamEvent`s so that the existing
/// `ChatSessionEngine` and `ChatState` remain unchanged.
///
/// Event mapping:
/// - `textDelta`         → `contentBlockStart("text")` / `contentBlockDelta("text_delta")` / `contentBlockStop`
/// - `thinkingDelta`     → `contentBlockStart("thinking")` / `contentBlockDelta("thinking_delta")` / `contentBlockStop`
/// - `toolCallStart`     → `contentBlockStart("tool_use", id, name)`
/// - `toolCallDelta`     → `contentBlockDelta("input_json_delta")`
/// - `toolCallComplete`  → `contentBlockStop`
/// - `toolResult`        → `userToolResult(toolUseId, content, isError)`
/// - `stepEnd`           → `messageStop`
/// - `finished`          → `result(text, inputTokens, outputTokens)`
final class NativeAgentTransport: ChatTransport, @unchecked Sendable {

  private let loop: AgentLoopProtocol
  private let model: ModelDescriptor
  private let workingDirectory: URL
  private let permissions: PermissionDelegate
  private let variant: ReasoningVariant?
  private let systemPrompt: String?

  private var onEvent: ((StreamEvent) -> Void)?
  private var onReady: ((String) -> Void)?
  private var onError: ((Error) -> Void)?
  private var onTerminated: ((TerminationReason) -> Void)?

  private var runningTask: Task<Void, Never>?
  private var messages: [[String: JSONValue]] = []
  private var sessionID: String = ""

  /// Token counts for the current turn only (reset before each runLoop).
  private var turnInputTokens: Int = 0
  private var turnOutputTokens: Int = 0

  /// Tracks which content blocks are currently open during event mapping.
  private var blockState = BlockState()

  private(set) var isRunning: Bool = false

  init(
    loop: AgentLoopProtocol,
    model: ModelDescriptor,
    workingDirectory: URL,
    permissions: PermissionDelegate,
    variant: ReasoningVariant? = nil,
    systemPrompt: String? = nil
  ) {
    self.loop = loop
    self.model = model
    self.workingDirectory = workingDirectory
    self.permissions = permissions
    self.variant = variant
    self.systemPrompt = systemPrompt
  }

  func start(
    onEvent: @escaping (StreamEvent) -> Void,
    onReady: @escaping (String) -> Void,
    onError: @escaping (Error) -> Void,
    onTerminated: @escaping (TerminationReason) -> Void
  ) {
    self.onEvent = onEvent
    self.onReady = onReady
    self.onError = onError
    self.onTerminated = onTerminated

    sessionID = UUID().uuidString
    isRunning = true

    onReady(sessionID)
  }

  func send(message: String) {
    guard isRunning else {
      return
    }

    /// Add the user message to the conversation history.
    messages.append([
      "role": .string("user"),
      "content": .array([
        .object(["type": .string("text"), "text": .string(message)])
      ]),
    ])

    /// Kick off the agent loop in a Task.
    runningTask = Task { [weak self] in
      guard let self else {
        return
      }

      await self.runLoop(userMessage: message)
    }
  }

  func interrupt() {
    runningTask?.cancel()
    runningTask = nil
  }

  func terminate() {
    runningTask?.cancel()
    runningTask = nil
    isRunning = false
    onTerminated?(.normal)
  }

  // MARK: - Private

  /// Tracks which content blocks are currently open and their indices.
  private struct BlockState {
    var textBlockIndex: Int?
    var thinkingBlockIndex: Int?
    var toolBlockIndex = 0
    var nextBlockIndex = 0

    var textBlockOpen: Bool { textBlockIndex != nil }
    var thinkingBlockOpen: Bool { thinkingBlockIndex != nil }
  }

  /// Runs the agent loop on the current task. All mutable state
  /// mutations and callback dispatches happen on MainActor.
  private func runLoop(userMessage: String) async {
    turnInputTokens = 0
    turnOutputTokens = 0
    blockState = BlockState()

    let input = RuntimeInput(
      sessionID: sessionID,
      model: model,
      messages: [],
      systemPrompt: systemPrompt,
      selectedVariant: variant
    )

    let context = ToolContext(
      sessionID: sessionID,
      workingDirectory: workingDirectory,
      permissions: permissions
    )

    do {
      let finalText = try await loop.run(
        input: input,
        messages: &messages,
        context: context,
        onEvent: { [weak self] event in
          /// Dispatch to MainActor since AgentEventHandler is @Sendable
          /// and may be called from any isolation domain.
          Task { @MainActor [weak self] in
            self?.mapEvent(event)
          }
        }
      )

      await MainActor.run {
        onEvent?(.result(
          text: finalText,
          inputTokens: turnInputTokens,
          outputTokens: turnOutputTokens
        ))
      }
    } catch is CancellationError {
      await MainActor.run {
        onTerminated?(.cancelled)
      }
      return
    } catch {
      await MainActor.run {
        if NativeAgentTransport.isAPIError(error) {
          /// Non-transient API errors (rate limits, auth failures) —
          /// surface directly without recovery retries.
          onError?(error)
        } else {
          /// Transport-level errors — let the engine attempt recovery.
          onError?(error)
          onTerminated?(.crash(exitCode: 1, stderr: error.localizedDescription))
        }
      }
    }
  }

  /// Map an `AgentLoopEvent` to one or more `StreamEvent`s.
  private func mapEvent(_ event: AgentLoopEvent) {
    switch event {
    case .textDelta(let text):
      if !blockState.textBlockOpen {
        let idx = blockState.nextBlockIndex
        onEvent?(.contentBlockStart(
          index: idx,
          blockType: "text",
          id: nil,
          name: nil
        ))
        blockState.textBlockIndex = idx
        blockState.nextBlockIndex += 1
      }
      if let idx = blockState.textBlockIndex {
        onEvent?(.contentBlockDelta(
          index: idx,
          deltaType: "text_delta",
          text: text
        ))
      }

    case .thinkingDelta(let text):
      if !blockState.thinkingBlockOpen {
        let idx = blockState.nextBlockIndex
        onEvent?(.contentBlockStart(
          index: idx,
          blockType: "thinking",
          id: nil,
          name: nil
        ))
        blockState.thinkingBlockIndex = idx
        blockState.nextBlockIndex += 1
      }
      if let idx = blockState.thinkingBlockIndex {
        onEvent?(.contentBlockDelta(
          index: idx,
          deltaType: "thinking_delta",
          text: text
        ))
      }

    case .toolCallStart(let id, let name):
      /// Close any open text/thinking blocks first.
      closeOpenBlocks()

      let idx = blockState.nextBlockIndex
      blockState.toolBlockIndex = idx
      onEvent?(.contentBlockStart(
        index: idx,
        blockType: "tool_use",
        id: id,
        name: name
      ))
      blockState.nextBlockIndex += 1

    case .toolCallDelta(_, let delta):
      onEvent?(.contentBlockDelta(
        index: blockState.toolBlockIndex,
        deltaType: "input_json_delta",
        text: delta
      ))

    case .toolCallComplete:
      onEvent?(.contentBlockStop(index: blockState.toolBlockIndex))

    case .toolResult(let id, _, let output, let isError):
      onEvent?(.userToolResult(
        toolUseId: id,
        content: output,
        isError: isError
      ))

    case .stepStart:
      break

    case .stepEnd:
      /// Close any open blocks and emit messageStop.
      closeOpenBlocks()
      onEvent?(.messageStop)
      /// Reset block indices for the next step.
      blockState.nextBlockIndex = 0

    case .usage(let input, let output):
      turnInputTokens += input
      turnOutputTokens += output

    case .finished:
      closeOpenBlocks()

    case .error(let msg):
      Logger.chat.error("Agent loop error: \(msg)")
    }
  }

  /// Returns true for HTTP API errors (4xx/5xx) that should not
  /// trigger transport recovery retries.
  private static func isAPIError(_ error: Error) -> Bool {
    if let httpError = error as? URLSessionHTTPTransportError,
       case .httpError = httpError
    {
      return true
    }

    return false
  }

  /// Close any text or thinking blocks that are still open.
  private func closeOpenBlocks() {
    if let idx = blockState.textBlockIndex {
      onEvent?(.contentBlockStop(index: idx))
      blockState.textBlockIndex = nil
    }
    if let idx = blockState.thinkingBlockIndex {
      onEvent?(.contentBlockStop(index: idx))
      blockState.thinkingBlockIndex = nil
    }
  }
}
