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
final class NativeAgentTransport: ChatTransport {

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

  /// Accumulated token counts across all steps.
  private var totalInputTokens: Int = 0
  private var totalOutputTokens: Int = 0

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

  /// Tracks which content blocks are currently open.
  private struct BlockState {
    var textBlockOpen = false
    var thinkingBlockOpen = false
    var toolBlockIndex = 0
    var nextBlockIndex = 0
  }

  private func runLoop(userMessage: String) async {
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

    blockState = BlockState()

    do {
      let finalText = try await loop.run(
        input: input,
        messages: &messages,
        context: context,
        onEvent: { [weak self] event in
          guard let self else {
            return
          }
          self.mapEvent(event)
        }
      )

      /// Emit the final result event.
      onEvent?(.result(
        text: finalText,
        inputTokens: totalInputTokens,
        outputTokens: totalOutputTokens
      ))
    } catch is CancellationError {
      onTerminated?(.cancelled)
      return
    } catch {
      onError?(error)
      onTerminated?(.crash(exitCode: 1, stderr: error.localizedDescription))
    }
  }

  /// Map an `AgentLoopEvent` to one or more `StreamEvent`s.
  private func mapEvent(_ event: AgentLoopEvent) {
    switch event {
    case .textDelta(let text):
      if !blockState.textBlockOpen {
        onEvent?(.contentBlockStart(
          index: blockState.nextBlockIndex,
          blockType: "text",
          id: nil,
          name: nil
        ))
        blockState.textBlockOpen = true
        blockState.nextBlockIndex += 1
      }
      onEvent?(.contentBlockDelta(
        index: blockState.nextBlockIndex - 1,
        deltaType: "text_delta",
        text: text
      ))

    case .thinkingDelta(let text):
      if !blockState.thinkingBlockOpen {
        onEvent?(.contentBlockStart(
          index: blockState.nextBlockIndex,
          blockType: "thinking",
          id: nil,
          name: nil
        ))
        blockState.thinkingBlockOpen = true
        blockState.nextBlockIndex += 1
      }
      onEvent?(.contentBlockDelta(
        index: blockState.nextBlockIndex - 1,
        deltaType: "thinking_delta",
        text: text
      ))

    case .toolCallStart(let id, let name):
      /// Close any open text/thinking blocks first.
      closeOpenBlocks()

      blockState.toolBlockIndex = blockState.nextBlockIndex
      onEvent?(.contentBlockStart(
        index: blockState.nextBlockIndex,
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

    case .toolCallComplete(let id, _, _):
      onEvent?(.contentBlockStop(index: blockState.toolBlockIndex))
      _ = id

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
      totalInputTokens += input
      totalOutputTokens += output

    case .finished:
      closeOpenBlocks()

    case .error(let msg):
      Logger.chat.error("Agent loop error: \(msg)")
    }
  }

  /// Close any text or thinking blocks that are still open.
  private func closeOpenBlocks() {
    if blockState.textBlockOpen {
      onEvent?(.contentBlockStop(index: blockState.nextBlockIndex - 1))
      blockState.textBlockOpen = false
    }
    if blockState.thinkingBlockOpen {
      onEvent?(.contentBlockStop(index: blockState.nextBlockIndex - 1))
      blockState.thinkingBlockOpen = false
    }
  }
}
