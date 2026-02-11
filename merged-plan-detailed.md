# Detailed Implementation Plan: Production Chat + Primary UX

Based on `merged-plan.md`. Every milestone specifies exact files, types, methods, and wiring.

## Validation Adjustments (Applied)

This plan was validated against the current repository and CLI capabilities. The following corrections are now part of the plan:

1. Add a **Phase 0** before Track A/B to make chat modules testable via SwiftPM (`Package.swift` currently excludes chat sources).
2. Treat `StreamEvent` as **non-Equatable** unless explicitly updated; tests should use `if case` pattern matching instead of `XCTAssertEqual` for enum payload cases.
3. `ToolBlockRouter` examples must avoid `AnyView` return shortcuts inside `body`; use `@ViewBuilder` branching for compile-safe SwiftUI.
4. `swift-markdown` AST node examples are illustrative; actual node names/APIs must be aligned to the pinned package version during implementation.
5. `ChatState` adapter must include a concrete observation/wiring strategy so engine updates propagate reliably to SwiftUI.
6. `resumeSession(sessionId:)` must be added to `ChatState` API (or resume ID passed via initializer) before `AppState.createChatTab(...resumeSessionId:)` integration.
7. `StreamEventParser` guidance is clarified: no schema redesign required in A2, but parser logging hooks are expected in A5.
8. Timeline adjusted to **5-6 weeks** for one developer if all P0 + P1 scope is delivered with tests.

---

## Phase 0: Testability and Compatibility Prep

**Goal**: unblock reliable implementation and automated tests before major refactors.

### Modified file: `Package.swift`

- Include chat core files in `SlothyTerminalLib` test target scope:
  - `Chat/Parser/StreamEvent.swift`
  - `Chat/Parser/StreamEventParser.swift`
  - `Chat/Models/ChatMessage.swift`
  - `Chat/Models/ChatConversation.swift`
  - New Track A files under `Chat/Engine`, `Chat/Transport`, `Chat/Storage`
- Keep UI views excluded from SwiftPM tests.

### Compatibility spike

- Verify concrete `swift-markdown` node APIs against selected package version.
- Verify Claude resume behavior with `--resume` in current `--print --input-format stream-json --output-format stream-json` flow.
- Confirm interrupt semantics (`Process.interrupt()` / SIGINT) map to expected stream events.

---

## Track A (P0): Core Engine and Reliability

### A1. Session Engine and State Machine

**Goal**: Extract turn orchestration from `ChatState` into a testable state machine. `ChatState` (486 lines) currently mixes process management, event handling, and UI state. The engine owns the session lifecycle; `ChatState` becomes a thin `@Observable` adapter.

#### New file: `SlothyTerminal/Chat/Engine/ChatSessionState.swift`

```swift
/// All possible states the chat session can be in.
enum ChatSessionState: Equatable {
  case idle                    // No turn in progress, ready for input
  case starting                // Transport is being initialized
  case ready                   // Transport running, waiting for user input
  case sending                 // User message written to transport, waiting for response
  case streaming               // Assistant response is being received
  case cancelling              // Cancel requested, waiting for transport to confirm
  case recovering(attempt: Int) // Crash recovery in progress
  case failed(ChatSessionError) // Unrecoverable failure
  case terminated              // Session ended, cleanup done
}
```

#### New file: `SlothyTerminal/Chat/Engine/ChatSessionEvent.swift`

```swift
/// Events that drive state transitions.
enum ChatSessionEvent {
  // User-initiated
  case userSendMessage(String)
  case userCancel
  case userClear
  case userRetry

  // Transport-originated
  case transportReady(sessionId: String)
  case transportStreamEvent(StreamEvent)  // Reuses existing StreamEvent enum
  case transportError(Error)
  case transportTerminated(reason: TerminationReason)

  // Internal
  case recoveryAttempt(Int)
  case recoveryFailed
}

enum TerminationReason: Equatable {
  case normal
  case crash(exitCode: Int32, stderr: String)
  case cancelled
}
```

#### New file: `SlothyTerminal/Chat/Engine/ChatSessionError.swift`

```swift
/// Errors surfaced by the engine. Replaces ChatError for engine-level concerns.
enum ChatSessionError: LocalizedError, Equatable {
  case transportNotAvailable(String)  // Claude CLI not found
  case transportStartFailed(String)   // Process failed to launch
  case transportCrashed(exitCode: Int32, stderr: String)
  case maxRetriesExceeded(Int)
  case invalidState(String)           // Programming error: invalid transition

  var errorDescription: String? { /* per-case messages */ }
}
```

#### New file: `SlothyTerminal/Chat/Engine/ChatSessionEngine.swift`

```swift
/// Pure state machine + turn orchestrator. No I/O, no UI, no process management.
/// Receives events, updates state, emits commands for the adapter to execute.
@Observable
class ChatSessionEngine {
  // MARK: - Observable state (read by ChatState adapter)
  private(set) var sessionState: ChatSessionState = .idle
  private(set) var conversation: ChatConversation
  private(set) var sessionId: String?
  private(set) var currentToolName: String?

  // MARK: - Internal state
  private var currentMessage: ChatMessage?
  private var lastUserMessageText: String?
  private var recoveryAttempts: Int = 0
  private let maxRecoveryAttempts: Int = 3

  init(workingDirectory: URL) {
    self.conversation = ChatConversation(workingDirectory: workingDirectory)
  }

  // MARK: - Public API (called by ChatState adapter)

  /// Process an event and return commands for the adapter to execute.
  func handle(_ event: ChatSessionEvent) -> [ChatSessionCommand] {
    // Validate transition is legal for current state
    // Update state
    // Return commands
  }

  // MARK: - Private: State transition table

  /// Returns whether this event is valid in the current state.
  private func isValidTransition(_ event: ChatSessionEvent) -> Bool { ... }

  // MARK: - Private: Event handlers

  /// Each returns [ChatSessionCommand] — what the adapter should do next.
  private func handleUserSendMessage(_ text: String) -> [ChatSessionCommand] {
    // 1. Validate state is .idle or .ready
    // 2. Create user ChatMessage, add to conversation
    // 3. Create assistant placeholder (isStreaming = true)
    // 4. Transition to .sending
    // 5. Return [.startTransportIfNeeded, .sendMessage(text)]
  }

  private func handleUserCancel() -> [ChatSessionCommand] {
    // 1. Transition to .cancelling
    // 2. Return [.interruptTransport]
  }

  private func handleUserClear() -> [ChatSessionCommand] {
    // 1. Reset conversation, sessionId, currentMessage
    // 2. Transition to .idle
    // 3. Return [.terminateTransport]
  }

  private func handleUserRetry() -> [ChatSessionCommand] {
    // 1. Remove last assistant message
    // 2. Re-send lastUserMessageText
    // 3. Return [.sendMessage(lastUserMessageText)]
  }

  private func handleTransportReady(_ sessionId: String) -> [ChatSessionCommand] {
    // 1. Store sessionId
    // 2. Transition to .ready
    // 3. Return []
  }

  private func handleStreamEvent(_ event: StreamEvent) -> [ChatSessionCommand] {
    // This is the bulk of current handleStreamEvent() logic from ChatState lines 241-380
    // Moved here verbatim with state transition wrappers
    // Key: on .result or .messageStop → transition to .ready, return [.turnComplete]
  }

  private func handleTransportError(_ error: Error) -> [ChatSessionCommand] {
    // 1. If recoverable: transition to .recovering, return [.attemptRecovery]
    // 2. If not: transition to .failed, return [.surfaceError]
  }

  private func handleTransportTerminated(_ reason: TerminationReason) -> [ChatSessionCommand] {
    // 1. If crash + sessionId available + retries < max: return [.attemptRecovery]
    // 2. If normal: transition to .idle
    // 3. If unrecoverable: transition to .failed
  }
}
```

#### New file: `SlothyTerminal/Chat/Engine/ChatSessionCommand.swift`

```swift
/// Commands emitted by the engine for the adapter (ChatState) to execute.
/// The engine never does I/O itself — it tells the adapter what to do.
enum ChatSessionCommand {
  case startTransport(workingDirectory: URL, resumeSessionId: String?)
  case sendMessage(String)
  case interruptTransport    // Send SIGINT
  case terminateTransport    // Full cleanup
  case attemptRecovery(sessionId: String, attempt: Int)
  case persistSnapshot       // Tell storage layer to save
  case turnComplete          // Signal UI that a turn finished
  case surfaceError(ChatSessionError)
}
```

#### Modified file: `SlothyTerminal/Chat/State/ChatState.swift`

Becomes a thin adapter (~120 lines instead of 486). Responsibilities:
- Owns `ChatSessionEngine` and `ChatTransport` (injected or created)
- Bridges engine's `@Observable` state to SwiftUI
- Executes `ChatSessionCommand`s by calling transport/storage methods
- Feeds transport events back into engine

```swift
@Observable
class ChatState {
  // MARK: - Public (observed by views, unchanged API)
  var conversation: ChatConversation { engine.conversation }
  var isLoading: Bool { engine.sessionState == .sending || engine.sessionState == .streaming }
  var error: ChatSessionError? { /* derived from engine.sessionState */ }
  var sessionId: String? { engine.sessionId }
  var currentToolName: String? { engine.currentToolName }

  // MARK: - Private
  private let engine: ChatSessionEngine
  private var transport: ChatTransport?
  private var store: ChatSessionStore?

  init(workingDirectory: URL) {
    self.engine = ChatSessionEngine(workingDirectory: workingDirectory)
  }

  // MARK: - Public API (unchanged signatures for view compatibility)

  @MainActor
  func sendMessage(_ text: String) {
    let commands = engine.handle(.userSendMessage(text))
    executeCommands(commands)
  }

  func cancelResponse() {
    let commands = engine.handle(.userCancel)
    executeCommands(commands)
  }

  func clearConversation() {
    let commands = engine.handle(.userClear)
    executeCommands(commands)
  }

  func retryLastMessage() {
    let commands = engine.handle(.userRetry)
    executeCommands(commands)
  }

  func terminateProcess() {
    transport?.terminate()
    transport = nil
  }

  // MARK: - Command execution

  @MainActor
  private func executeCommands(_ commands: [ChatSessionCommand]) {
    for command in commands {
      switch command {
      case .startTransport(let dir, let resumeId):
        startTransport(workingDirectory: dir, resumeSessionId: resumeId)
      case .sendMessage(let text):
        transport?.send(message: text)
      case .interruptTransport:
        transport?.interrupt()
      case .terminateTransport:
        transport?.terminate()
        transport = nil
      case .attemptRecovery(let sessionId, _):
        startTransport(workingDirectory: engine.conversation.workingDirectory, resumeSessionId: sessionId)
      case .persistSnapshot:
        store?.save(engine.conversation, sessionId: engine.sessionId)
      case .turnComplete:
        break // UI updates automatically via @Observable
      case .surfaceError:
        break // Error surfaced via engine.sessionState
      }
    }
  }

  // MARK: - Transport lifecycle

  private func startTransport(workingDirectory: URL, resumeSessionId: String?) {
    let newTransport = ClaudeCLITransport(workingDirectory: workingDirectory, resumeSessionId: resumeSessionId)
    self.transport = newTransport

    newTransport.start { [weak self] event in
      Task { @MainActor in
        guard let self else { return }
        let commands = self.engine.handle(.transportStreamEvent(event))
        self.executeCommands(commands)
      }
    } onReady: { [weak self] sessionId in
      Task { @MainActor in
        guard let self else { return }
        let commands = self.engine.handle(.transportReady(sessionId: sessionId))
        self.executeCommands(commands)
      }
    } onError: { [weak self] error in
      Task { @MainActor in
        guard let self else { return }
        let commands = self.engine.handle(.transportError(error))
        self.executeCommands(commands)
      }
    } onTerminated: { [weak self] reason in
      Task { @MainActor in
        guard let self else { return }
        let commands = self.engine.handle(.transportTerminated(reason: reason))
        self.executeCommands(commands)
      }
    }
  }
}
```

#### Delete file: `SlothyTerminal/Chat/State/ChatError.swift`
Replaced by `ChatSessionError.swift`. Update `ChatView.swift` error banner to use new type.

#### No changes to: `ChatMessage.swift`, `ChatConversation.swift`, `ChatContentBlock`
Engine mutates these directly (they are `@Observable` classes). Views observe them unchanged.

---

### A2. Claude Transport Abstraction

**Goal**: Isolate all process management into a protocol + implementation. Makes engine testable with mock transport.

#### New file: `SlothyTerminal/Chat/Transport/ChatTransport.swift`

```swift
/// Protocol for communicating with a Claude backend.
/// Implementations handle process lifecycle, stdin/stdout, and NDJSON parsing.
protocol ChatTransport: AnyObject {
  /// Start the transport. Calls back with events on the provided closures.
  func start(
    onEvent: @escaping (StreamEvent) -> Void,
    onReady: @escaping (String) -> Void,      // sessionId
    onError: @escaping (Error) -> Void,
    onTerminated: @escaping (TerminationReason) -> Void
  )

  /// Send a user message (text will be serialized to NDJSON internally).
  func send(message: String)

  /// Interrupt the current operation (SIGINT).
  func interrupt()

  /// Terminate the transport completely.
  func terminate()

  /// Whether the transport is currently running.
  var isRunning: Bool { get }
}
```

#### New file: `SlothyTerminal/Chat/Transport/ClaudeCLITransport.swift`

Extracts these methods from current `ChatState`:
- `startProcess()` (lines 99-210) → `start(...)`
- `writeUserMessage()` (lines 212-238) → `send(message:)`
- `terminateProcess()` (lines 81-94) → `terminate()`
- `buildEnvironment()` (lines 382-400) → private helper
- `resolveClaudePath()` (lines 402-455) → private helper
- `isBinaryExecutable()` (lines 457-485) → private helper
- Background reading task (lines 152-184) → internal to `start()`

```swift
/// Concrete transport using Foundation.Process + NDJSON over stdio.
class ClaudeCLITransport: ChatTransport {
  private let workingDirectory: URL
  private let resumeSessionId: String?

  private var process: Process?
  private var stdinPipe: Pipe?
  private var readingTask: Task<Void, Never>?
  private(set) var isRunning: Bool = false

  init(workingDirectory: URL, resumeSessionId: String? = nil) {
    self.workingDirectory = workingDirectory
    self.resumeSessionId = resumeSessionId
  }

  func start(
    onEvent: @escaping (StreamEvent) -> Void,
    onReady: @escaping (String) -> Void,
    onError: @escaping (Error) -> Void,
    onTerminated: @escaping (TerminationReason) -> Void
  ) {
    guard let executablePath = resolveClaudePath() else {
      onError(ChatSessionError.transportNotAvailable("Claude CLI not found"))
      return
    }

    let proc = Process()
    let stdin = Pipe()
    let stdout = Pipe()
    let stderr = Pipe()

    proc.executableURL = URL(fileURLWithPath: executablePath)
    proc.arguments = buildArguments()
    proc.currentDirectoryURL = workingDirectory
    proc.environment = buildEnvironment()
    proc.standardInput = stdin
    proc.standardOutput = stdout
    proc.standardError = stderr

    do {
      try proc.run()
    } catch {
      onError(ChatSessionError.transportStartFailed(error.localizedDescription))
      return
    }

    self.process = proc
    self.stdinPipe = stdin
    self.isRunning = true

    // Background stdout reading task
    readingTask = Task { [weak self] in
      let handle = stdout.fileHandleForReading
      do {
        for try await line in handle.bytes.lines {
          if Task.isCancelled { break }

          guard let event = StreamEventParser.parse(line: line) else {
            continue
          }

          // Intercept system event to extract sessionId
          if case .system(let sessionId) = event {
            onReady(sessionId)
          }

          onEvent(event)
        }
      } catch {
        if !Task.isCancelled {
          onError(error)
        }
      }

      self?.isRunning = false
    }

    // Process termination handler
    proc.terminationHandler = { [weak self] process in
      self?.isRunning = false

      if process.terminationStatus != 0 {
        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
        let stderrText = String(data: stderrData, encoding: .utf8)?
          .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        onTerminated(.crash(exitCode: process.terminationStatus, stderr: stderrText))
      } else {
        onTerminated(.normal)
      }
    }
  }

  func send(message: String) {
    guard let stdinPipe else { return }

    let messageJSON: [String: Any] = [
      "type": "user",
      "message": [
        "role": "user",
        "content": [
          ["type": "text", "text": message]
        ]
      ]
    ]

    guard let data = try? JSONSerialization.data(withJSONObject: messageJSON),
          var jsonString = String(data: data, encoding: .utf8)
    else { return }

    jsonString += "\n"
    if let writeData = jsonString.data(using: .utf8) {
      stdinPipe.fileHandleForWriting.write(writeData)
    }
  }

  func interrupt() {
    process?.interrupt()  // Sends SIGINT
  }

  func terminate() {
    readingTask?.cancel()
    readingTask = nil
    if let process, process.isRunning {
      process.terminate()
    }
    process = nil
    stdinPipe = nil
    isRunning = false
  }

  // MARK: - Private helpers (moved from ChatState)

  private func buildArguments() -> [String] {
    var args = [
      "-p",
      "--input-format", "stream-json",
      "--output-format", "stream-json",
      "--verbose",
      "--include-partial-messages",
    ]
    if let resumeSessionId {
      args += ["--resume", resumeSessionId]
    }
    return args
  }

  private func buildEnvironment() -> [String: String] {
    // Exact copy of ChatState.buildEnvironment() (lines 382-400)
  }

  private func resolveClaudePath() -> String? {
    // Exact copy of ChatState.resolveClaudePath() (lines 402-455)
  }

  private func isBinaryExecutable(atPath path: String) -> Bool {
    // Exact copy of ChatState.isBinaryExecutable() (lines 457-485)
  }
}
```

#### New file: `SlothyTerminal/Chat/Transport/MockChatTransport.swift`

For testing only (lives in `SlothyTerminalTests/` or conditionally compiled):

```swift
/// Mock transport that replays pre-recorded events. Used in engine tests.
class MockChatTransport: ChatTransport {
  var isRunning: Bool = false
  var sentMessages: [String] = []
  var interrupted: Bool = false
  var terminated: Bool = false

  private var onEvent: ((StreamEvent) -> Void)?
  private var onReady: ((String) -> Void)?
  private var onError: ((Error) -> Void)?
  private var onTerminated: ((TerminationReason) -> Void)?

  func start(...) { /* store callbacks, set isRunning */ }
  func send(message: String) { sentMessages.append(message) }
  func interrupt() { interrupted = true }
  func terminate() { terminated = true; isRunning = false }

  // Test helpers
  func simulateReady(sessionId: String) { onReady?(sessionId) }
  func simulateEvent(_ event: StreamEvent) { onEvent?(event) }
  func simulateError(_ error: Error) { onError?(error) }
  func simulateTerminated(_ reason: TerminationReason) { onTerminated?(reason) }
}
```

#### No structural changes to: `StreamEventParser.swift`, `StreamEvent.swift`
Reused as-is by `ClaudeCLITransport` in A2. In A5, add logging instrumentation only.

---

### A3. Persistence and Resume Foundation

**Goal**: Save session snapshots to disk. Restore on relaunch. Resume with `--resume <sessionId>`.

#### New file: `SlothyTerminal/Chat/Storage/ChatSessionStore.swift`

```swift
/// Persists chat sessions to ~/Library/Application Support/SlothyTerminal/chats/
class ChatSessionStore {
  private let baseDirectory: URL
  private var saveTimer: Timer?
  private let debounceInterval: TimeInterval = 1.0  // Longer than config (0.5s)

  init() {
    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    self.baseDirectory = appSupport
      .appendingPathComponent("SlothyTerminal", isDirectory: true)
      .appendingPathComponent("chats", isDirectory: true)
  }

  /// Save conversation snapshot (debounced).
  func save(_ conversation: ChatConversation, sessionId: String?) {
    saveTimer?.invalidate()
    saveTimer = Timer.scheduledTimer(withTimeInterval: debounceInterval, repeats: false) { [weak self] _ in
      self?.writeSnapshot(conversation, sessionId: sessionId)
    }
  }

  /// Immediately save (called on app quit).
  func saveImmediately(_ conversation: ChatConversation, sessionId: String?) {
    saveTimer?.invalidate()
    saveTimer = nil
    writeSnapshot(conversation, sessionId: sessionId)
  }

  /// Load the most recent session for a working directory.
  func loadSession(for workingDirectory: URL) -> ChatSessionSnapshot? {
    let index = loadIndex()
    guard let sessionId = index.sessions[workingDirectory.path] else { return nil }
    return loadSnapshot(sessionId: sessionId)
  }

  /// List all saved sessions.
  func listSessions() -> [ChatSessionSnapshot] { ... }

  /// Delete a session.
  func deleteSession(sessionId: String) { ... }

  // MARK: - Private

  private func writeSnapshot(_ conversation: ChatConversation, sessionId: String?) {
    guard let sessionId else { return }

    let snapshot = ChatSessionSnapshot(
      sessionId: sessionId,
      workingDirectory: conversation.workingDirectory.path,
      messages: conversation.messages.map { SerializedMessage(from: $0) },
      totalInputTokens: conversation.totalInputTokens,
      totalOutputTokens: conversation.totalOutputTokens,
      createdAt: conversation.messages.first?.timestamp ?? Date(),
      lastActiveAt: Date()
    )

    // Create directory if needed
    try? FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)

    // Write snapshot atomically
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    if let data = try? encoder.encode(snapshot) {
      let fileURL = baseDirectory.appendingPathComponent("\(sessionId).json")
      try? data.write(to: fileURL, options: .atomic)
    }

    // Update index
    updateIndex(workingDirectory: conversation.workingDirectory.path, sessionId: sessionId)

    Logger.chat.info("Saved session \(sessionId)")
  }

  private func loadSnapshot(sessionId: String) -> ChatSessionSnapshot? {
    let fileURL = baseDirectory.appendingPathComponent("\(sessionId).json")
    guard let data = try? Data(contentsOf: fileURL) else { return nil }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try? decoder.decode(ChatSessionSnapshot.self, from: data)
  }

  // Index: maps working directory path → most recent sessionId
  private func loadIndex() -> ChatSessionIndex { ... }
  private func updateIndex(workingDirectory: String, sessionId: String) { ... }
}
```

#### New file: `SlothyTerminal/Chat/Storage/ChatSessionSnapshot.swift`

```swift
/// Codable snapshot of a chat session for persistence.
struct ChatSessionSnapshot: Codable {
  let sessionId: String
  let workingDirectory: String
  let messages: [SerializedMessage]
  let totalInputTokens: Int
  let totalOutputTokens: Int
  let createdAt: Date
  let lastActiveAt: Date
}

/// Codable mirror of ChatMessage (since ChatMessage is @Observable class).
struct SerializedMessage: Codable {
  let id: UUID
  let role: String            // "user" or "assistant"
  let contentBlocks: [SerializedContentBlock]
  let timestamp: Date
  let inputTokens: Int
  let outputTokens: Int

  init(from message: ChatMessage) {
    self.id = message.id
    self.role = message.role.rawValue
    self.contentBlocks = message.contentBlocks.map { SerializedContentBlock(from: $0) }
    self.timestamp = message.timestamp
    self.inputTokens = message.inputTokens
    self.outputTokens = message.outputTokens
  }

  func toChatMessage() -> ChatMessage {
    ChatMessage(
      id: id,
      role: ChatRole(rawValue: role) ?? .user,
      contentBlocks: contentBlocks.map { $0.toChatContentBlock() },
      timestamp: timestamp,
      isStreaming: false,
      inputTokens: inputTokens,
      outputTokens: outputTokens
    )
  }
}

/// Codable mirror of ChatContentBlock.
struct SerializedContentBlock: Codable {
  let type: String  // "text", "thinking", "toolUse", "toolResult"
  let text: String?
  let id: String?
  let name: String?
  let input: String?
  let toolUseId: String?
  let content: String?

  init(from block: ChatContentBlock) { ... }
  func toChatContentBlock() -> ChatContentBlock { ... }
}

/// Index file mapping working directories to session IDs.
struct ChatSessionIndex: Codable {
  var sessions: [String: String] = [:]  // workingDirectory path → sessionId
}
```

#### Modified file: `SlothyTerminal/Chat/Models/ChatConversation.swift`

Add restoration method:

```swift
/// Restore conversation from a snapshot.
static func fromSnapshot(_ snapshot: ChatSessionSnapshot) -> ChatConversation {
  let conversation = ChatConversation(
    workingDirectory: URL(fileURLWithPath: snapshot.workingDirectory)
  )
  conversation.messages = snapshot.messages.map { $0.toChatMessage() }
  conversation.totalInputTokens = snapshot.totalInputTokens
  conversation.totalOutputTokens = snapshot.totalOutputTokens
  return conversation
}
```

#### Modified file: `SlothyTerminal/Chat/State/ChatState.swift`

Add store integration:
- Create `ChatSessionStore` instance
- After each `.turnComplete` command → call `store.save()`
- On init, check for existing session → offer resume
- On `terminateProcess()` → call `store.saveImmediately()`

#### Modified file: `SlothyTerminal/Chat/Transport/ClaudeCLITransport.swift`

Add `--resume <sessionId>` to arguments when `resumeSessionId` is non-nil (already shown in A2 above).

#### Modified file: `SlothyTerminal/App/AppState.swift`

Add resume variant:
```swift
func createChatTab(directory: URL, resumeSessionId: String? = nil, initialPrompt: String? = nil) {
  let tab = Tab(agentType: .claude, workingDirectory: directory, mode: .chat)
  if let resumeSessionId {
    tab.chatState?.resumeSession(sessionId: resumeSessionId)
  }
  tabs.append(tab)
  switchToTab(id: tab.id)
  if let prompt = initialPrompt, !prompt.isEmpty {
    tab.chatState?.sendMessage(prompt)
  }
}
```

---

### A4. Resilience Semantics

**Goal**: True cancel, retry, and crash recovery.

#### Modified file: `SlothyTerminal/Chat/Engine/ChatSessionEngine.swift`

Already designed in A1. Key behaviors:

**Cancel**:
- `handle(.userCancel)` → transition to `.cancelling` → command `.interruptTransport` (sends SIGINT)
- On subsequent `.transportStreamEvent(.messageStop)` or `.transportTerminated(.cancelled)` → transition to `.ready`
- Current message's `isStreaming` set to false, content preserved (partial response kept)

**Retry**:
- `handle(.userRetry)` → remove last assistant message → re-send `lastUserMessageText`
- Only valid in `.ready` state (after a completed or failed turn)
- If no `lastUserMessageText` stored, command is no-op

**Crash recovery**:
- On `.transportTerminated(.crash(...))` with `sessionId != nil` and `recoveryAttempts < maxRecoveryAttempts`:
  - Transition to `.recovering(attempt: n)`
  - Emit `.attemptRecovery(sessionId: ..., attempt: n)`
  - Adapter creates new `ClaudeCLITransport` with `resumeSessionId`
- On `.transportReady` after recovery → transition to `.ready`, reset `recoveryAttempts`
- On max retries exceeded → transition to `.failed(.maxRetriesExceeded)`
- Backoff: 1s, 2s, 4s (adapter handles delay before calling transport)

#### Modified file: `SlothyTerminal/Chat/State/ChatState.swift`

Add connection state derived property for UI:
```swift
var connectionState: ConnectionState {
  switch engine.sessionState {
  case .idle, .terminated: return .disconnected
  case .starting, .recovering: return .reconnecting
  case .ready, .sending, .streaming, .cancelling: return .connected
  case .failed: return .failed
  }
}

enum ConnectionState {
  case connected
  case disconnected
  case reconnecting
  case failed
}
```

---

### A5. Observability and Tests

#### Modified file: `SlothyTerminal/Services/Logger.swift`

Add chat category:
```swift
/// Logger for chat engine, transport, and storage operations.
static let chat = Logger(subsystem: subsystem, category: "Chat")
```

Add structured logging calls in:
- `ChatSessionEngine`: Log every state transition: `Logger.chat.info("State: \(old) → \(new) on event: \(event)")`
- `ClaudeCLITransport`: Log process start/stop, errors
- `ChatSessionStore`: Log save/load/errors
- `StreamEventParser`: Log parse failures: `Logger.chat.debug("Failed to parse line: \(line.prefix(100))")`

#### New file: `SlothyTerminalTests/ChatSessionEngineTests.swift`

Test the state machine with `MockChatTransport`:

```swift
@testable import SlothyTerminalLib

final class ChatSessionEngineTests: XCTestCase {
  private var engine: ChatSessionEngine!

  override func setUp() {
    engine = ChatSessionEngine(workingDirectory: URL(fileURLWithPath: "/tmp/test"))
  }

  // State transition tests
  func testInitialStateIsIdle() {
    XCTAssertEqual(engine.sessionState, .idle)
  }

  func testSendMessageTransitionsToSending() {
    let commands = engine.handle(.userSendMessage("hello"))
    XCTAssertEqual(engine.sessionState, .sending)
    XCTAssertTrue(commands.contains(where: { if case .sendMessage = $0 { return true }; return false }))
  }

  func testStreamEventTransitionsToStreaming() {
    _ = engine.handle(.userSendMessage("hello"))
    _ = engine.handle(.transportReady(sessionId: "test-123"))
    let delta = StreamEvent.contentBlockDelta(index: 0, deltaType: "text_delta", text: "Hi")
    _ = engine.handle(.transportStreamEvent(delta))
    XCTAssertEqual(engine.sessionState, .streaming)
  }

  func testResultTransitionsToReady() {
    _ = engine.handle(.userSendMessage("hello"))
    _ = engine.handle(.transportReady(sessionId: "test-123"))
    _ = engine.handle(.transportStreamEvent(.result(text: "done", inputTokens: 100, outputTokens: 50)))
    XCTAssertEqual(engine.sessionState, .ready)
  }

  func testCancelTransitionsToCancelling() {
    _ = engine.handle(.userSendMessage("hello"))
    _ = engine.handle(.userCancel)
    XCTAssertEqual(engine.sessionState, .cancelling)
  }

  func testClearResetsToIdle() {
    _ = engine.handle(.userSendMessage("hello"))
    _ = engine.handle(.userClear)
    XCTAssertEqual(engine.sessionState, .idle)
    XCTAssertTrue(engine.conversation.messages.isEmpty)
  }

  // Turn orchestration tests
  func testUserMessageAddedToConversation() {
    _ = engine.handle(.userSendMessage("hello"))
    XCTAssertEqual(engine.conversation.messages.count, 2) // user + assistant placeholder
    XCTAssertEqual(engine.conversation.messages[0].role, .user)
    XCTAssertEqual(engine.conversation.messages[1].role, .assistant)
    XCTAssertTrue(engine.conversation.messages[1].isStreaming)
  }

  func testTokensAccumulateOnResult() {
    _ = engine.handle(.userSendMessage("hello"))
    _ = engine.handle(.transportReady(sessionId: "s1"))
    _ = engine.handle(.transportStreamEvent(.result(text: "", inputTokens: 100, outputTokens: 50)))
    XCTAssertEqual(engine.conversation.totalInputTokens, 100)
    XCTAssertEqual(engine.conversation.totalOutputTokens, 50)
  }

  func testRetryRemovesLastAssistantMessage() {
    _ = engine.handle(.userSendMessage("hello"))
    _ = engine.handle(.transportReady(sessionId: "s1"))
    _ = engine.handle(.transportStreamEvent(.result(text: "", inputTokens: 100, outputTokens: 50)))
    XCTAssertEqual(engine.conversation.messages.count, 2)
    _ = engine.handle(.userRetry)
    // Last assistant removed, new one created
    XCTAssertEqual(engine.conversation.messages.count, 2) // user + new assistant placeholder
  }

  // Recovery tests
  func testCrashTriggersRecovery() {
    _ = engine.handle(.userSendMessage("hello"))
    _ = engine.handle(.transportReady(sessionId: "s1"))
    let commands = engine.handle(.transportTerminated(reason: .crash(exitCode: 1, stderr: "error")))
    XCTAssertEqual(engine.sessionState, .recovering(attempt: 1))
    XCTAssertTrue(commands.contains(where: { if case .attemptRecovery = $0 { return true }; return false }))
  }

  func testMaxRetriesExceeded() {
    _ = engine.handle(.userSendMessage("hello"))
    _ = engine.handle(.transportReady(sessionId: "s1"))
    _ = engine.handle(.transportTerminated(reason: .crash(exitCode: 1, stderr: "")))
    _ = engine.handle(.transportTerminated(reason: .crash(exitCode: 1, stderr: "")))
    _ = engine.handle(.transportTerminated(reason: .crash(exitCode: 1, stderr: "")))
    let commands = engine.handle(.transportTerminated(reason: .crash(exitCode: 1, stderr: "")))
    XCTAssertEqual(engine.sessionState, .failed(.maxRetriesExceeded(3)))
  }

  // Invalid transition tests
  func testSendInStreamingStateIsInvalid() {
    _ = engine.handle(.userSendMessage("hello"))
    // Engine should ignore or queue a second send while streaming
    let commands = engine.handle(.userSendMessage("another"))
    XCTAssertTrue(commands.isEmpty) // Rejected
  }
}
```

#### New file: `SlothyTerminalTests/StreamEventParserTests.swift`

```swift
@testable import SlothyTerminalLib

final class StreamEventParserTests: XCTestCase {
  func testParseSystemEvent() {
    let line = #"{"type":"system","session_id":"abc-123"}"#
    let event = StreamEventParser.parse(line: line)
    if case .system(let sid) = event { XCTAssertEqual(sid, "abc-123") }
    else { XCTFail("Expected system event") }
  }

  func testParseTextDelta() {
    let line = #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}}"#
    let event = StreamEventParser.parse(line: line)
    if case .contentBlockDelta(let idx, let dt, let text) = event {
      XCTAssertEqual(idx, 0)
      XCTAssertEqual(dt, "text_delta")
      XCTAssertEqual(text, "Hello")
    } else { XCTFail("Expected contentBlockDelta") }
  }

  func testParseResultWithCachedTokens() {
    let line = #"{"type":"result","result":"done","usage":{"input_tokens":100,"output_tokens":50,"cache_read_input_tokens":200}}"#
    let event = StreamEventParser.parse(line: line)
    if case .result(_, let input, let output) = event {
      XCTAssertEqual(input, 300)  // 100 + 200 cached
      XCTAssertEqual(output, 50)
    } else { XCTFail("Expected result") }
  }

  func testParseEmptyLine() {
    XCTAssertNil(StreamEventParser.parse(line: ""))
    XCTAssertNil(StreamEventParser.parse(line: "   "))
  }

  func testParseMalformedJSON() {
    XCTAssertNil(StreamEventParser.parse(line: "not json"))
    XCTAssertNil(StreamEventParser.parse(line: "{broken"))
  }

  func testParseUnknownType() {
    let line = #"{"type":"future_event","data":"something"}"#
    let event = StreamEventParser.parse(line: line)
    if case .unknown = event {
      XCTAssertTrue(true)
    } else {
      XCTFail("Expected unknown event")
    }
  }

  func testParseToolUseInAssistant() {
    let line = #"{"type":"assistant","message":{"usage":{"input_tokens":10,"output_tokens":5},"content":[{"type":"tool_use","id":"tu_1","name":"Bash","input":{"command":"ls"}}]}}"#
    let event = StreamEventParser.parse(line: line)
    if case .assistant(let blocks, _, _) = event {
      XCTAssertEqual(blocks.count, 1)
      XCTAssertEqual(blocks[0].name, "Bash")
    } else { XCTFail("Expected assistant") }
  }
}
```

#### New file: `SlothyTerminalTests/ChatSessionStoreTests.swift`

```swift
@testable import SlothyTerminalLib

final class ChatSessionStoreTests: XCTestCase {
  private var store: ChatSessionStore!
  private var tempDir: URL!

  override func setUp() {
    tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    store = ChatSessionStore(baseDirectory: tempDir)
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: tempDir)
  }

  func testSaveAndLoadRoundtrip() {
    let conversation = ChatConversation(workingDirectory: URL(fileURLWithPath: "/tmp/project"))
    let msg = ChatMessage(role: .user, contentBlocks: [.text("Hello")])
    conversation.addMessage(msg)
    conversation.totalInputTokens = 100

    store.saveImmediately(conversation, sessionId: "session-1")

    let loaded = store.loadSession(for: URL(fileURLWithPath: "/tmp/project"))
    XCTAssertNotNil(loaded)
    XCTAssertEqual(loaded?.sessionId, "session-1")
    XCTAssertEqual(loaded?.messages.count, 1)
    XCTAssertEqual(loaded?.totalInputTokens, 100)
  }

  func testLoadNonexistentSession() {
    let loaded = store.loadSession(for: URL(fileURLWithPath: "/tmp/nonexistent"))
    XCTAssertNil(loaded)
  }

  func testDeleteSession() {
    let conversation = ChatConversation(workingDirectory: URL(fileURLWithPath: "/tmp/project"))
    store.saveImmediately(conversation, sessionId: "session-1")
    store.deleteSession(sessionId: "session-1")
    let loaded = store.loadSession(for: URL(fileURLWithPath: "/tmp/project"))
    XCTAssertNil(loaded)
  }
}
```

Note: `ChatSessionStore` needs an `init(baseDirectory:)` overload for testing (production uses default Application Support path).

---

## Track B (P1): Product UX and Chat-First Experience

### B1. Promote Chat to Primary Entry

**Goal**: Chat is the default new-tab action. Terminal becomes secondary.

#### Modified file: `SlothyTerminal/App/SlothyTerminalApp.swift`

Lines 49-68 — reorder and reassign shortcuts:

```swift
// Current → New
// "New Terminal Tab"     Cmd+T           → Cmd+Shift+Option+T
// "New Claude Tab"       Cmd+Shift+T     → Cmd+Shift+T (unchanged, but labeled "Claude TUI")
// "New OpenCode Tab"     Cmd+Option+T    → Cmd+Option+T (unchanged)
// "New Claude Chat"      Cmd+Shift+Opt+T → Cmd+T (primary!)

CommandGroup(replacing: .newItem) {
  Button("New Chat") {
    appState.showChatFolderSelector()
  }
  .keyboardShortcut("t", modifiers: .command)

  Divider()

  Button("New Claude TUI Tab") {
    appState.showFolderSelector(for: .claude)
  }
  .keyboardShortcut("t", modifiers: [.command, .shift])

  Button("New OpenCode Tab") {
    appState.showFolderSelector(for: .opencode)
  }
  .keyboardShortcut("t", modifiers: [.command, .option])

  Button("New Terminal Tab") {
    appState.showFolderSelector(for: .terminal)
  }
  .keyboardShortcut("t", modifiers: [.command, .shift, .option])

  // ... rest unchanged
}
```

Also update the `onReceive(.newTabRequested)` to handle chat notifications.

#### Modified file: `SlothyTerminal/Views/TerminalContainerView.swift`

`EmptyTerminalView` (lines 148-184) — reorder buttons, chat first:

```swift
VStack(spacing: 12) {
  // Chat button FIRST and visually prominent
  ChatTabTypeButton {
    appState.showChatFolderSelector()
  }

  Divider()
    .padding(.horizontal, 40)

  // Terminal agents below
  ForEach(AgentType.allCases) { agentType in
    TabTypeButton(agentType: agentType) {
      appState.showFolderSelector(for: agentType)
    }
  }
}
```

`ChatTabTypeButton` (lines 240-295) — remove Beta badge:

Remove lines 258-265 (the "Beta" `Text` and its HStack). Change label to just "New Claude Chat".

#### Modified file: `SlothyTerminal/Models/Tab.swift`

Line 67: Change `"Chat (Beta)"` to `"Chat"`:
```swift
let prefix = mode == .chat ? "Chat" : agent.displayName
```

#### Modified file: `SlothyTerminal/Views/TabBarView.swift`

Change `"Chat β: "` to `"Chat: "` in the tab title rendering.

#### Modified file: `SlothyTerminal/Models/AppConfig.swift`

Add config field and shortcut action:

```swift
// In AppConfig struct, after chatSendKey:
/// Default mode for new tabs.
var defaultTabMode: DefaultTabMode = .chat

// New enum:
enum DefaultTabMode: String, Codable, CaseIterable {
  case chat
  case terminal

  var displayName: String {
    switch self {
    case .chat: return "Chat"
    case .terminal: return "Terminal"
    }
  }
}

// In ShortcutAction enum, add:
case newChatTab

// In displayName:
case .newChatTab: return "New Chat Tab"

// In defaultShortcut:
case .newChatTab: return "⌘T"

// Update newTerminalTab default:
case .newTerminalTab: return "⌘⇧⌥T"

// Update newClaudeTab display:
case .newClaudeTab: return "New Claude TUI Tab"

// In category:
case .newChatTab: return .tabs
```

#### Modified file: `SlothyTerminal/Views/SettingsView.swift`

Add picker in General settings section (near defaultAgent picker):

```swift
Picker("Default new tab", selection: $configManager.config.defaultTabMode) {
  ForEach(DefaultTabMode.allCases, id: \.self) { mode in
    Text(mode.displayName).tag(mode)
  }
}
```

#### Modified file: `SlothyTerminal/App/AppDelegate.swift`

Add "New Chat" as first dock menu item (before line 71):

```swift
let chatItem = NSMenuItem(
  title: "New Chat",
  action: #selector(newChatTab),
  keyEquivalent: ""
)
chatItem.target = self
menu.addItem(chatItem)

menu.addItem(NSMenuItem.separator())

// ... existing terminal/claude/opencode items
```

Add notification handler:
```swift
@objc private func newChatTab() {
  NotificationCenter.default.post(
    name: .newChatTabRequested,
    object: nil
  )
}
```

Add notification name:
```swift
static let newChatTabRequested = Notification.Name("newChatTabRequested")
```

#### Modified file: `SlothyTerminal/App/SlothyTerminalApp.swift`

Add receiver for the new notification:
```swift
.onReceive(NotificationCenter.default.publisher(for: .newChatTabRequested)) { _ in
  appState.showChatFolderSelector()
}
```

**Note**: Beta labels are only removed after A5 test gates pass (as specified in merged plan). During initial B1 work, keep a "Beta" indicator somewhere subtle (e.g., sidebar) until tests are green.

---

### B2. Rich Markdown Rendering

**Goal**: Fenced code blocks, lists, tables, blockquotes, headings render properly.

#### SPM dependency addition

Add to Xcode project package dependencies:
- Package: `https://github.com/apple/swift-markdown`
- Version: from 0.4.0
- Add `Markdown` product to SlothyTerminal target

#### New file: `SlothyTerminal/Chat/Views/Markdown/MarkdownRendererView.swift`

```swift
import SwiftUI
import Markdown

/// Renders a markdown string as a vertical stack of native SwiftUI block views.
/// During streaming, falls back to cheap inline rendering.
struct MarkdownRendererView: View {
  let text: String
  let isStreaming: Bool

  var body: some View {
    if isStreaming {
      // Cheap inline rendering during streaming
      InlineMarkdownView(text: text)
    } else {
      // Full AST rendering for completed messages
      let document = Document(parsing: text)
      MarkdownBlockStack(document: document)
    }
  }
}

/// Walks a Markdown Document and produces a VStack of block views.
struct MarkdownBlockStack: View {
  let document: Document

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(Array(document.children.enumerated()), id: \.offset) { _, child in
        MarkdownBlockView(markup: child)
      }
    }
  }
}

/// Routes a single Markup node to the appropriate view.
struct MarkdownBlockView: View {
  let markup: any Markup

  var body: some View {
    switch markup {
    case let heading as Heading:
      MarkdownHeadingView(heading: heading)
    case let paragraph as Paragraph:
      InlineMarkdownView(text: paragraph.plainText) // or render inline children
    case let codeBlock as CodeBlock:
      CodeBlockView(language: codeBlock.language, code: codeBlock.code)
    case let list as UnorderedList:
      MarkdownUnorderedListView(list: list)
    case let list as OrderedList:
      MarkdownOrderedListView(list: list)
    case let blockquote as BlockQuote:
      MarkdownBlockquoteView(blockquote: blockquote)
    case is ThematicBreak:
      Divider()
    case let table as Markdown.Table:
      MarkdownTableView(table: table)
    default:
      // Fallback for unknown block types
      Text(markup.format())
        .textSelection(.enabled)
    }
  }
}
```

#### New file: `SlothyTerminal/Chat/Views/Markdown/CodeBlockView.swift`

```swift
import SwiftUI

/// Renders a fenced code block with language label, copy button, and monospaced text.
struct CodeBlockView: View {
  let language: String?
  let code: String
  @State private var copied = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Header bar: language + copy button
      HStack {
        if let language, !language.isEmpty {
          Text(language)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.secondary)
        }
        Spacer()
        CopyButton(text: code)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      .background(Color(white: 0.12))

      // Code content
      ScrollView(.horizontal, showsIndicators: true) {
        Text(code)
          .font(.system(size: 12, design: .monospaced))
          .textSelection(.enabled)
          .padding(12)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .background(Color(white: 0.08))
    .cornerRadius(8)
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .stroke(Color.white.opacity(0.06), lineWidth: 1)
    )
  }
}
```

#### New file: `SlothyTerminal/Chat/Views/Markdown/InlineMarkdownView.swift`

```swift
import SwiftUI

/// Renders inline markdown (bold, italic, code, links) using AttributedString.
struct InlineMarkdownView: View {
  let text: String

  var body: some View {
    if let attributed = try? AttributedString(
      markdown: text,
      options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    ) {
      Text(attributed)
        .font(.system(size: 13))
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    } else {
      Text(text)
        .font(.system(size: 13))
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}
```

#### New file: `SlothyTerminal/Chat/Views/Markdown/MarkdownBlockViews.swift`

Contains: `MarkdownHeadingView`, `MarkdownUnorderedListView`, `MarkdownOrderedListView`, `MarkdownBlockquoteView`, `MarkdownTableView`. Each is a focused SwiftUI view that recursively renders child inline/block content.

#### Modified file: `SlothyTerminal/Chat/Views/MarkdownTextView.swift`

Replace body:
```swift
struct MarkdownTextView: View {
  let text: String
  var isStreaming: Bool = false

  var body: some View {
    MarkdownRendererView(text: text, isStreaming: isStreaming)
  }
}
```

#### Modified file: `SlothyTerminal/Chat/Views/MessageBubbleView.swift`

Pass `isStreaming` to markdown renderer:
```swift
case .text(let text):
  if !text.isEmpty {
    if renderAsMarkdown {
      MarkdownTextView(text: text, isStreaming: message.isStreaming)
    } else {
      // plain text unchanged
    }
  }
```

This requires `MessageBubbleView` to access `message.isStreaming` and pass it through `ContentBlockView`. Adjust `ContentBlockView` to accept `isStreaming: Bool`.

---

### B3. Tool Use Rendering

**Goal**: Tool-specific views instead of generic expandable text.

#### New file: `SlothyTerminal/Chat/Models/ToolInput.swift`

```swift
/// Parsed tool input for specialized rendering.
enum ToolInput {
  case bash(command: String)
  case read(filePath: String, offset: Int?, limit: Int?)
  case edit(filePath: String, oldString: String, newString: String)
  case write(filePath: String, content: String)
  case glob(pattern: String, path: String?)
  case grep(pattern: String, path: String?, glob: String?)
  case generic(name: String, rawJSON: String)

  /// Parse tool input JSON by tool name.
  static func parse(name: String, jsonString: String) -> ToolInput {
    guard let data = jsonString.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return .generic(name: name, rawJSON: jsonString)
    }

    switch name {
    case "Bash":
      return .bash(command: json["command"] as? String ?? jsonString)
    case "Read":
      return .read(
        filePath: json["file_path"] as? String ?? "",
        offset: json["offset"] as? Int,
        limit: json["limit"] as? Int
      )
    case "Edit":
      return .edit(
        filePath: json["file_path"] as? String ?? "",
        oldString: json["old_string"] as? String ?? "",
        newString: json["new_string"] as? String ?? ""
      )
    case "Write":
      return .write(
        filePath: json["file_path"] as? String ?? "",
        content: json["content"] as? String ?? ""
      )
    case "Glob":
      return .glob(
        pattern: json["pattern"] as? String ?? "",
        path: json["path"] as? String
      )
    case "Grep":
      return .grep(
        pattern: json["pattern"] as? String ?? "",
        path: json["path"] as? String,
        glob: json["glob"] as? String
      )
    default:
      return .generic(name: name, rawJSON: jsonString)
    }
  }
}
```

#### New file: `SlothyTerminal/Chat/Views/Tools/ToolBlockRouter.swift`

```swift
/// Groups tool_use + tool_result pairs and routes to specialized views.
struct ToolBlockRouter: View {
  let toolUse: ChatContentBlock    // .toolUse case
  let toolResult: ChatContentBlock? // .toolResult case, nil if still streaming

  var body: some View {
    // Extract tool name and input from the toolUse block
    guard case .toolUse(_, let name, let input) = toolUse else { return AnyView(EmptyView()) }

    let parsedInput = ToolInput.parse(name: name, jsonString: input)
    let resultContent: String? = {
      if case .toolResult(_, let content) = toolResult { return content }
      return nil
    }()

    VStack(alignment: .leading, spacing: 0) {
      switch parsedInput {
      case .bash(let command):
        BashToolView(command: command, output: resultContent)
      case .read(let path, _, _):
        FileToolView(action: "Read", filePath: path, content: resultContent)
      case .edit(let path, let old, let new):
        EditToolView(filePath: path, oldString: old, newString: new, result: resultContent)
      case .write(let path, let content):
        FileToolView(action: "Write", filePath: path, content: content)
      case .glob(let pattern, _):
        SearchToolView(type: "Glob", pattern: pattern, results: resultContent)
      case .grep(let pattern, _, _):
        SearchToolView(type: "Grep", pattern: pattern, results: resultContent)
      case .generic(let name, let rawJSON):
        GenericToolView(name: name, input: rawJSON, output: resultContent)
      }
    }
  }
}
```

#### New files: `BashToolView.swift`, `FileToolView.swift`, `EditToolView.swift`, `SearchToolView.swift`, `GenericToolView.swift`

All in `SlothyTerminal/Chat/Views/Tools/`. Each is a self-contained SwiftUI view with:
- Tool-specific header (icon + label)
- Expandable/collapsible content
- Copy button on relevant sections
- Monospaced font for code/output

#### Modified file: `SlothyTerminal/Chat/Views/MessageBubbleView.swift`

Replace `ContentBlockView` tool cases. Group `toolUse` + `toolResult` blocks:

```swift
// In ContentBlockView or a new wrapper:
// Instead of rendering each block independently, scan contentBlocks
// for toolUse/toolResult pairs and render them together via ToolBlockRouter.

// Add helper to ChatMessage:
func toolResultForUse(id: String) -> ChatContentBlock? {
  contentBlocks.first {
    if case .toolResult(let toolUseId, _) = $0, toolUseId == id { return true }
    return false
  }
}
```

The `MessageBubbleView` iteration logic needs to skip standalone `toolResult` blocks (since they're now rendered as part of their paired `toolUse`).

---

### B4. Interaction Polish

#### New file: `SlothyTerminal/Chat/Views/Components/CopyButton.swift`

```swift
import SwiftUI

/// Reusable copy-to-clipboard button with checkmark feedback.
struct CopyButton: View {
  let text: String
  @State private var copied = false

  var body: some View {
    Button {
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(text, forType: .string)
      copied = true
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
        copied = false
      }
    } label: {
      Image(systemName: copied ? "checkmark" : "doc.on.doc")
        .font(.system(size: 10))
        .foregroundColor(copied ? .green : .secondary)
    }
    .buttonStyle(.plain)
    .help("Copy to clipboard")
  }
}
```

#### Modified file: `SlothyTerminal/Chat/Views/MessageBubbleView.swift`

Add per-message metadata row:

```swift
// After content blocks, for assistant messages:
if message.role == .assistant && !message.isStreaming {
  HStack(spacing: 8) {
    Text(message.timestamp, style: .time)
      .font(.system(size: 10))
      .foregroundColor(.secondary.opacity(0.5))

    if message.inputTokens > 0 || message.outputTokens > 0 {
      Text("\(message.inputTokens) in / \(message.outputTokens) out")
        .font(.system(size: 10))
        .foregroundColor(.secondary.opacity(0.5))
    }

    Spacer()
  }
  .padding(.top, 4)
}
```

Improve `StreamingIndicatorView` to show context:

```swift
struct StreamingIndicatorView: View {
  var toolName: String?  // From ChatState.currentToolName
  // Show "Thinking...", "Running Bash...", "Reading file...", etc.
}
```

#### Modified file: `SlothyTerminal/Chat/Views/ChatView.swift`

Improve `ChatStatusBar`:
```swift
struct ChatStatusBar: View {
  @Binding var renderAsMarkdown: Bool
  let chatState: ChatState  // Add access to chatState

  var body: some View {
    HStack(spacing: 8) {
      // Connection state indicator
      Circle()
        .fill(connectionColor)
        .frame(width: 6, height: 6)

      // Token totals
      if chatState.conversation.totalInputTokens > 0 {
        Text("\(chatState.conversation.totalInputTokens + chatState.conversation.totalOutputTokens) tokens")
          .font(.system(size: 10))
          .foregroundColor(.secondary)
      }

      Spacer()

      // Clear conversation button
      if chatState.conversation.messages.count > 0 {
        Button { chatState.clearConversation() } label: {
          Image(systemName: "trash")
            .font(.system(size: 10))
            .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .help("Clear conversation")
      }

      // Markdown toggle (existing)
      // ...
    }
  }
}
```

Improve `ChatEmptyStateView` with prompt suggestions:

```swift
struct ChatEmptyStateView: View {
  let onSuggestionTap: (String) -> Void

  private let suggestions = [
    "Review this codebase",
    "Fix the failing tests",
    "Explain the architecture",
    "Help me refactor",
  ]

  var body: some View {
    VStack(spacing: 16) {
      // ... existing icon and title

      HStack(spacing: 8) {
        ForEach(suggestions, id: \.self) { suggestion in
          Button { onSuggestionTap(suggestion) } label: {
            Text(suggestion)
              .font(.system(size: 11))
              .padding(.horizontal, 10)
              .padding(.vertical, 6)
              .background(Color.secondary.opacity(0.1))
              .cornerRadius(12)
          }
          .buttonStyle(.plain)
        }
      }
    }
  }
}
```

#### Modified file: `SlothyTerminal/Chat/Views/ChatInputView.swift`

Add message history navigation:

```swift
struct ChatInputView: View {
  // ... existing properties

  @State private var messageHistory: [String] = []
  @State private var historyIndex: Int = -1

  // In onKeyPress handler, add:
  .onKeyPress(.upArrow, phases: .down) { _ in
    if historyIndex < messageHistory.count - 1 {
      historyIndex += 1
      inputText = messageHistory[messageHistory.count - 1 - historyIndex]
      return .handled
    }
    return .ignored
  }
  .onKeyPress(.downArrow, phases: .down) { _ in
    if historyIndex > 0 {
      historyIndex -= 1
      inputText = messageHistory[messageHistory.count - 1 - historyIndex]
      return .handled
    } else if historyIndex == 0 {
      historyIndex = -1
      inputText = ""
      return .handled
    }
    return .ignored
  }

  // In send():
  private func send() {
    guard canSend else { return }
    let text = inputText
    messageHistory.append(text)
    historyIndex = -1
    inputText = ""
    onSend(text)
  }
}
```

Increase min height from 36 to 44.

---

## Execution Order

```
Week 0:
  Phase 0 (Package.swift testability + compatibility spike)

Week 1:
  A1 (engine + state machine)
  A2 (transport abstraction)
  B1 (chat-first menu/shortcuts, keep Beta label)

Week 2:
  A3 (persistence + resume)
  A5 (engine tests + parser tests)
  B2 (markdown renderer) starts

Week 3:
  A4 (resilience: cancel/retry/recover)
  B2 (markdown renderer completes)
  B3 (tool rendering)

Week 4:
  A5 (integration + store tests)
  B4 (polish: copy, status bar, suggestions, input history)

Week 5-6:
  Stabilization, bug fixes from dogfooding, performance tuning
  Remove Beta labels after acceptance gates pass
```

## Acceptance Gates

Before removing Beta:
- [ ] `Package.swift` includes chat core sources required by tests
- [ ] Engine state transition tests pass (all valid/invalid transitions)
- [ ] Parser handles malformed/variant NDJSON without crash
- [ ] Store roundtrip test passes (save → load → compare)
- [ ] Process crash triggers recovery and resumes conversation
- [ ] App relaunch restores session and can continue
- [ ] Cancel sends SIGINT and returns to ready state
- [ ] Retry removes last response and re-sends
- [ ] Markdown renders code blocks, lists, blockquotes correctly
- [ ] Tool blocks render specialized views for Bash/Read/Edit/Write/Glob/Grep
- [ ] No regressions in terminal/TUI tabs

## New File Summary

| Path | Track | Purpose |
|------|-------|---------|
| `Chat/Engine/ChatSessionState.swift` | A1 | State enum |
| `Chat/Engine/ChatSessionEvent.swift` | A1 | Event enum + TerminationReason |
| `Chat/Engine/ChatSessionError.swift` | A1 | Error enum (replaces ChatError) |
| `Chat/Engine/ChatSessionEngine.swift` | A1 | State machine + turn orchestrator |
| `Chat/Engine/ChatSessionCommand.swift` | A1 | Command enum for adapter |
| `Chat/Transport/ChatTransport.swift` | A2 | Transport protocol |
| `Chat/Transport/ClaudeCLITransport.swift` | A2 | Foundation.Process implementation |
| `Chat/Storage/ChatSessionStore.swift` | A3 | Persistence manager |
| `Chat/Storage/ChatSessionSnapshot.swift` | A3 | Codable models |
| `Chat/Views/Markdown/MarkdownRendererView.swift` | B2 | AST-based renderer |
| `Chat/Views/Markdown/CodeBlockView.swift` | B2 | Fenced code blocks |
| `Chat/Views/Markdown/InlineMarkdownView.swift` | B2 | Inline formatting |
| `Chat/Views/Markdown/MarkdownBlockViews.swift` | B2 | Lists, blockquotes, tables, headings |
| `Chat/Models/ToolInput.swift` | B3 | Parsed tool input models |
| `Chat/Views/Tools/ToolBlockRouter.swift` | B3 | Routes to specialized tool views |
| `Chat/Views/Tools/BashToolView.swift` | B3 | Bash command + output |
| `Chat/Views/Tools/FileToolView.swift` | B3 | Read/Write file display |
| `Chat/Views/Tools/EditToolView.swift` | B3 | Edit with old/new strings |
| `Chat/Views/Tools/SearchToolView.swift` | B3 | Glob/Grep results |
| `Chat/Views/Tools/GenericToolView.swift` | B3 | Fallback for unknown tools |
| `Chat/Views/Components/CopyButton.swift` | B4 | Reusable copy button |
| `SlothyTerminalTests/ChatSessionEngineTests.swift` | A5 | Engine state machine tests |
| `SlothyTerminalTests/StreamEventParserTests.swift` | A5 | Parser tests |
| `SlothyTerminalTests/ChatSessionStoreTests.swift` | A5 | Storage roundtrip tests |

## UI Visualizations

### 1. Full Window Layout (After B1+B4)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐              ┌───┐       │
│  │💬 Chat: my-…│ │💬 Chat: api…│ │⬛ Terminal   │              │ + │       │
│  └─────────────┘ └─────────────┘ └─────────────┘              └───┘       │
├─────────────────────────────────────────────────┬───────────────────────────┤
│                                                 │  WORKING DIRECTORY       │
│  ● Connected  1,847 tokens        🗑  Markdown  │  ~/projects/my-app       │
│ ─────────────────────────────────────────────── │                          │
│                                                 │  ▸ Open in...            │
│  🔵 You                                        │                          │
│  Fix the authentication bug in the login flow   │  DIRECTORY TREE          │
│                                                 │  ├── src/                │
│  🟠 Claude                                     │  │   ├── auth/            │
│  I'll look at the authentication code. Let me   │  │   ├── components/     │
│  start by reading the login handler.            │  │   └── utils/          │
│                                                 │  ├── tests/              │
│  ┌─ Read ──────────────────────────────── 📋 ┐ │  └── package.json       │
│  │  📄 src/auth/login.ts                     │ │                          │
│  │  ┌──────────────────────────────────────┐ │ │  CHAT INFO               │
│  │  │  1  export async function login(     │ │ │  Messages: 4             │
│  │  │  2    email: string,                 │ │ │  Duration: 2m 34s        │
│  │  │  3    password: string               │ │ │                          │
│  │  │  4  ) {                              │ │ │  TOKEN USAGE             │
│  │  │  5    const user = await db.find...  │ │ │  Input:  1,234           │
│  │  └──────────────────────────────────────┘ │ │  Output:   613           │
│  └───────────────────────────────────────────┘ │                          │
│                                                 │                          │
│  I found the issue. The password comparison     │                          │
│  on line 12 uses `==` instead of a constant-    │                          │
│  time comparison. Here's the fix:               │                          │
│                                                 │                          │
│  ┌─ Edit ──────────────────────────────── 📋 ┐ │                          │
│  │  📝 src/auth/login.ts                     │ │                          │
│  │  - if (hash == storedHash) {              │ │                          │
│  │  + if (crypto.timingSafeEqual(            │ │                          │
│  │  +   Buffer.from(hash),                   │ │                          │
│  │  +   Buffer.from(storedHash)              │ │                          │
│  │  + )) {                                   │ │                          │
│  │  ──────────────────────────────────────── │ │                          │
│  │  ✓ Applied successfully                   │ │                          │
│  └───────────────────────────────────────────┘ │                          │
│                                                 │                          │
│  2:34 PM · 1,234 in / 613 out                  │                          │
│                                                 │                          │
│ ─────────────────────────────────────────────── │                          │
│ ┌───────────────────────────────────────┐ ┌──┐ │                          │
│ │ Type a message...                     │ │⬆ │ │                          │
│ └───────────────────────────────────────┘ └──┘ │                          │
├─────────────────────────────────────────────────┴───────────────────────────┤
│  ⎇ main                                                          v0.5.0   │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 2. Empty State — Chat First (B1)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                 ┌───┐      │
│  No tabs open                                                   │ + │      │
├─────────────────────────────────────────────────────────────────┴───┴──────┤
│                                                                             │
│                                                                             │
│                                                                             │
│                              💬                                             │
│                                                                             │
│                        Slothy Terminal                                       │
│                  Choose a tab type to get started                            │
│                                                                             │
│         ┌──────────────────────────────────────────────┐                    │
│         │  💬  New Claude Chat                         │                    │
│         │     Chat interface for Claude           ⌘T   │                    │
│         └──────────────────────────────────────────────┘                    │
│                                                                             │
│         ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─                    │
│                                                                             │
│         ┌──────────────────────────────────────────────┐                    │
│         │  ⬛  New Terminal Tab                         │                    │
│         │     Plain terminal session          ⌘⇧⌥T     │                    │
│         └──────────────────────────────────────────────┘                    │
│         ┌──────────────────────────────────────────────┐                    │
│         │  🧠  New Claude TUI Tab                      │                    │
│         │     Claude Code in terminal mode      ⌘⇧T    │                    │
│         └──────────────────────────────────────────────┘                    │
│         ┌──────────────────────────────────────────────┐                    │
│         │  🟢  New OpenCode Tab                        │                    │
│         │     OpenCode CLI                     ⌘⌥T     │                    │
│         └──────────────────────────────────────────────┘                    │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                   v0.5.0   │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 3. Chat Empty State with Suggestions (B4)

```
┌──────────────────────────────────────────────────────────────┐
│                                                              │
│                                                              │
│                                                              │
│                           💬                                 │
│                                                              │
│              Start a conversation with Claude                 │
│           Type a message below to begin. Enter to send.      │
│                                                              │
│   ┌────────────────┐ ┌──────────────────┐ ┌──────────────┐  │
│   │ Review this    │ │ Fix the failing  │ │ Explain the  │  │
│   │ codebase       │ │ tests            │ │ architecture │  │
│   └────────────────┘ └──────────────────┘ └──────────────┘  │
│                   ┌──────────────────┐                       │
│                   │ Help me refactor │                       │
│                   └──────────────────┘                       │
│                                                              │
│                                                              │
│ ──────────────────────────────────────────────────────────── │
│ ┌────────────────────────────────────────────────────┐ ┌──┐ │
│ │ Type a message...                                  │ │⬆ │ │
│ └────────────────────────────────────────────────────┘ └──┘ │
└──────────────────────────────────────────────────────────────┘
```

### 4. Chat Conversation with Resume Option (A3)

When a previous session exists for the directory:

```
┌──────────────────────────────────────────────────────────────┐
│                                                              │
│                           💬                                 │
│              Start a conversation with Claude                 │
│                                                              │
│        ┌──────────────────────────────────────────────┐      │
│        │  📂  Resume previous session                 │      │
│        │                                              │      │
│        │  Last active: 2 hours ago                    │      │
│        │  Messages: 12  ·  Tokens: 4,521              │      │
│        │  "Fix the authentication bug in..."          │      │
│        │                                              │      │
│        │           [ Resume ]   [ New Chat ]          │      │
│        └──────────────────────────────────────────────┘      │
│                                                              │
│   ┌────────────────┐ ┌──────────────────┐ ┌──────────────┐  │
│   │ Review this    │ │ Fix the failing  │ │ Explain the  │  │
│   │ codebase       │ │ tests            │ │ architecture │  │
│   └────────────────┘ └──────────────────┘ └──────────────┘  │
│                                                              │
│ ──────────────────────────────────────────────────────────── │
│ ┌────────────────────────────────────────────────────┐ ┌──┐ │
│ │ Type a message...                                  │ │⬆ │ │
│ └────────────────────────────────────────────────────┘ └──┘ │
└──────────────────────────────────────────────────────────────┘
```

### 5. Status Bar States (A4 + B4)

```
Connected (normal):
┌──────────────────────────────────────────────────────────────┐
│  🟢 Connected   1,847 tokens               🗑   Markdown    │
└──────────────────────────────────────────────────────────────┘

Streaming (tool in progress):
┌──────────────────────────────────────────────────────────────┐
│  🟢 Running Bash...  1,847 tokens           🗑   Markdown    │
└──────────────────────────────────────────────────────────────┘

Reconnecting after crash:
┌──────────────────────────────────────────────────────────────┐
│  🟡 Reconnecting (attempt 2/3)...           🗑   Markdown    │
└──────────────────────────────────────────────────────────────┘

Failed:
┌──────────────────────────────────────────────────────────────┐
│  🔴 Disconnected   [ Reconnect ]            🗑   Markdown    │
└──────────────────────────────────────────────────────────────┘

No session yet:
┌──────────────────────────────────────────────────────────────┐
│  ⚪ Idle                                          Markdown    │
└──────────────────────────────────────────────────────────────┘
```

### 6. Message Bubble — Text with Markdown (B2)

```
┌──────────────────────────────────────────────────────────────┐
│                                                              │
│  🟠 Claude                                                  │
│                                                              │
│  Here's how to implement the authentication middleware:      │
│                                                              │
│  ## Setup                                                    │
│                                                              │
│  First, install the required packages:                       │
│                                                              │
│  ┌─ bash ──────────────────────────────────────────── 📋 ┐  │
│  │  npm install jsonwebtoken bcrypt                       │  │
│  └───────────────────────────────────────────────────────┘  │
│                                                              │
│  Then create the middleware:                                  │
│                                                              │
│  ┌─ typescript ────────────────────────────────────── 📋 ┐  │
│  │  import jwt from 'jsonwebtoken';                       │  │
│  │                                                        │  │
│  │  export function authMiddleware(                        │  │
│  │    req: Request,                                       │  │
│  │    res: Response,                                      │  │
│  │    next: NextFunction                                  │  │
│  │  ) {                                                   │  │
│  │    const token = req.headers.authorization;            │  │
│  │    if (!token) {                                       │  │
│  │      return res.status(401).json({                     │  │
│  │        error: 'No token provided'                      │  │
│  │      });                                               │  │
│  │    }                                                   │  │
│  │    // ... verify token                                 │  │
│  │  }                                                     │  │
│  └───────────────────────────────────────────────────────┘  │
│                                                              │
│  Key points:                                                 │
│                                                              │
│  • Always validate the token signature                       │
│  • Use environment variables for the secret                  │
│  • Set reasonable expiration times                            │
│                                                              │
│  > **Note**: Never store JWTs in localStorage for            │
│  > sensitive applications. Use httpOnly cookies instead.      │
│                                                              │
│  2:34 PM · 1,234 in / 613 out                               │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

### 7. Tool Views — Bash (B3)

```
┌─ 🖥 Bash ──────────────────────────────────────────── 📋 ┐
│                                                           │
│  $ npm test -- --coverage                                 │
│                                                           │
│  ┌─ Output ────────────────────────────────────── 📋 ──┐ │
│  │  PASS  tests/auth.test.ts                           │ │
│  │  PASS  tests/login.test.ts                          │ │
│  │  FAIL  tests/register.test.ts                       │ │
│  │    ● should validate email format                   │ │
│  │      Expected: true                                 │ │
│  │      Received: false                                │ │
│  │                                                     │ │
│  │  Test Suites: 1 failed, 2 passed, 3 total          │ │
│  │  Tests:       1 failed, 8 passed, 9 total          │ │
│  └─────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────┘
```

### 8. Tool Views — Read File (B3)

```
┌─ 📄 Read ──────────────────────────────────── 📋 ┐
│                                                   │
│  src/auth/login.ts                                │
│                                                   │
│  ┌── typescript ──────────────────────── 📋 ──┐  │
│  │   1  import { db } from '../db';           │  │
│  │   2  import { hash } from '../utils';      │  │
│  │   3                                        │  │
│  │   4  export async function login(          │  │
│  │   5    email: string,                      │  │
│  │   6    password: string                    │  │
│  │   7  ) {                                   │  │
│  │   8    const user = await db.findUser(     │  │
│  │   9      email                             │  │
│  │  10    );                                  │  │
│  │  11    const h = hash(password);           │  │
│  │  12    if (h == user.passwordHash) {       │  │
│  │  13      return createSession(user);       │  │
│  │  14    }                                   │  │
│  │  15  }                                     │  │
│  └────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────┘
```

### 9. Tool Views — Edit File (B3)

```
┌─ 📝 Edit ──────────────────────────────────── 📋 ┐
│                                                    │
│  src/auth/login.ts                                 │
│                                                    │
│  ┌─ diff ───────────────────────────────────────┐ │
│  │  - if (h == user.passwordHash) {             │ │
│  │  + if (crypto.timingSafeEqual(               │ │
│  │  +   Buffer.from(h),                         │ │
│  │  +   Buffer.from(user.passwordHash)          │ │
│  │  + )) {                                      │ │
│  └──────────────────────────────────────────────┘ │
│                                                    │
│  ✅ Applied successfully                          │
└────────────────────────────────────────────────────┘
```

### 10. Tool Views — Glob/Grep Search (B3)

```
Glob:
┌─ 🔍 Glob ──────────────────────────── 📋 ┐
│                                            │
│  Pattern: **/*.test.ts                     │
│                                            │
│  📄 tests/auth.test.ts                    │
│  📄 tests/login.test.ts                   │
│  📄 tests/register.test.ts               │
│  📄 tests/utils/hash.test.ts             │
│                                            │
│  4 files found                             │
└────────────────────────────────────────────┘

Grep:
┌─ 🔍 Grep ──────────────────────────── 📋 ┐
│                                            │
│  Pattern: timingSafeEqual                  │
│  Path: src/                                │
│                                            │
│  📄 src/auth/login.ts                     │
│     12: if (crypto.timingSafeEqual(        │
│  📄 src/auth/register.ts                  │
│     45: return crypto.timingSafeEqual(     │
│                                            │
│  2 files, 2 matches                        │
└────────────────────────────────────────────┘
```

### 11. Tool Views — Generic Fallback (B3)

```
┌─ 🔧 WebFetch ──────────────────── ▸ ── 📋 ┐
│                                             │
│  {"url":"https://docs.example.com/api",     │
│   "prompt":"Extract the auth endpoint..."}  │
│                                             │
│  ┌─ Result ───────────────────── ▸ ─────┐  │
│  │  The API documentation shows three   │  │
│  │  auth endpoints: POST /login, ...    │  │
│  └──────────────────────────────────────┘  │
└─────────────────────────────────────────────┘
```

### 12. Thinking Block — Collapsed vs Expanded (B2)

```
Collapsed (default):
┌──────────────────────────────────────────────────────────────┐
│  🧠  Thinking... Let me analyze the authentication flow...   │
└──────────────────────────────────────────────────────────────┘

Expanded (on click):
┌──────────────────────────────────────────────────────────────┐
│  🧠  Thinking                                          ▾    │
│  ───────────────────────────────────────────────────────     │
│  The user wants to fix an authentication bug. Let me         │
│  think about what could cause this:                          │
│                                                              │
│  1. The login function uses == for hash comparison,          │
│     which is vulnerable to timing attacks and might          │
│     also have type coercion issues.                          │
│                                                              │
│  2. There's no rate limiting on the login endpoint.          │
│                                                              │
│  3. The session token generation doesn't include             │
│     proper entropy.                                          │
│                                                              │
│  I'll focus on the hash comparison first as that's           │
│  the most critical security issue.                           │
└──────────────────────────────────────────────────────────────┘
```

### 13. Streaming States (B4)

```
Waiting for response (no content yet):
┌──────────────────────────────────────────────────────────────┐
│  🟠 Claude                                                  │
│                                                              │
│  ● ● ○                                                      │
└──────────────────────────────────────────────────────────────┘

Thinking in progress:
┌──────────────────────────────────────────────────────────────┐
│  🟠 Claude                                                  │
│                                                              │
│  🧠  Thinking...                                            │
└──────────────────────────────────────────────────────────────┘

Tool running:
┌──────────────────────────────────────────────────────────────┐
│  🟠 Claude                                                  │
│                                                              │
│  Some analysis text already streamed...                      │
│                                                              │
│  ┌─ 🖥 Bash ──────────────────────────────────────────────┐ │
│  │  $ npm test                                             │ │
│  │  ⏳ Running...                                          │ │
│  └─────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────┘

Text streaming (tokens arriving):
┌──────────────────────────────────────────────────────────────┐
│  🟠 Claude                                                  │
│                                                              │
│  I found the issue. The password comparison on line 12       │
│  uses `==` instead of a constant-time comparison. This▌      │
└──────────────────────────────────────────────────────────────┘
```

### 14. Chat Input Area (B4)

```
Default state:
┌──────────────────────────────────────────────────────────────┐
│ ┌────────────────────────────────────────────────────┐ ┌──┐ │
│ │ Type a message...                                  │ │⬆ │ │
│ │                                                    │ │  │ │
│ └────────────────────────────────────────────────────┘ └──┘ │
│                                         Enter to send       │
└──────────────────────────────────────────────────────────────┘

With multi-line text (auto-expands):
┌──────────────────────────────────────────────────────────────┐
│ ┌────────────────────────────────────────────────────┐ ┌──┐ │
│ │ Can you help me with this? I need to:              │ │⬆ │ │
│ │                                                    │ │  │ │
│ │ 1. Fix the auth bug                                │ │  │ │
│ │ 2. Add rate limiting                               │ │  │ │
│ │ 3. Write tests for both                            │ │  │ │
│ └────────────────────────────────────────────────────┘ └──┘ │
│                                    Shift+Enter for new line  │
└──────────────────────────────────────────────────────────────┘

During streaming (stop button):
┌──────────────────────────────────────────────────────────────┐
│ ┌────────────────────────────────────────────────────┐ ┌──┐ │
│ │ Type a message...                                  │ │🔴│ │
│ │                                                    │ │  │ │
│ └────────────────────────────────────────────────────┘ └──┘ │
│                                               Esc to stop    │
└──────────────────────────────────────────────────────────────┘
```

### 15. Tab Bar — Chat vs Terminal (B1)

```
┌─────────────────────────────────────────────────────────────────────────┐
│ ┌───────────────┐ ┌─────────────────┐ ┌──────────────┐          ┌───┐ │
│ │ 💬 Chat: app  │ │ 💬 Chat: api    │ │ ⬛ Terminal   │          │ + │ │
│ │          [x]  │ │          [x]    │ │         [x]  │          └───┘ │
│ └───────────────┘ └─────────────────┘ └──────────────┘                │
└─────────────────────────────────────────────────────────────────────────┘

Legend:
  💬  = Chat mode (bubble icon)
  🧠  = Claude TUI (brain icon)
  ⬛  = Terminal (terminal icon)
  🟢  = OpenCode (opencode icon)
```

### 16. Error Banner (A4)

```
┌──────────────────────────────────────────────────────────────┐
│  ⚠️  Process crashed (exit code 1). Reconnecting...     ✕   │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│  ⚠️  Connection failed after 3 attempts.  [ Reconnect ]  ✕  │
└──────────────────────────────────────────────────────────────┘
```

### 17. Message with Retry Button (A4 + B4)

```
┌──────────────────────────────────────────────────────────────┐
│                                                              │
│  🟠 Claude                                                  │
│                                                              │
│  I'll look at the auth code now—                             │
│                                                              │
│  ⚠️ Response interrupted                                    │
│                                                              │
│  2:34 PM                                   [ 🔄 Retry ]     │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

### 18. Settings — Default Tab Mode (B1)

```
┌──────────────────────────────────────────────────────────────┐
│  General                                                     │
│  ──────────────────────────────────────────────────────────  │
│                                                              │
│  STARTUP                                                     │
│                                                              │
│  Default new tab       [ Chat            ▾]                  │
│  Default agent (TUI)   [ Claude          ▾]                  │
│  Show sidebar          [✓]                                   │
│                                                              │
│  CHAT                                                        │
│                                                              │
│  Send key              [ Enter           ▾]                  │
│                                                              │
│  APPEARANCE                                                  │
│                                                              │
│  Color scheme          [ Dark            ▾]                  │
│  Font family           [ SF Mono         ▾]                  │
│  Font size             [ 13              ▾]                  │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

### 19. Sidebar — Chat Mode (B4)

```
┌──────────────────────────┐
│  WORKING DIRECTORY       │
│  ┌────────────────────┐  │
│  │ 📁 ~/projects/app  │  │
│  └────────────────────┘  │
│                          │
│  ▸ Open in...            │
│                          │
│  DIRECTORY TREE          │
│  ├── src/                │
│  │   ├── auth/           │
│  │   │   ├── login.ts    │
│  │   │   └── register.ts │
│  │   ├── components/     │
│  │   └── utils/          │
│  ├── tests/              │
│  │   ├── auth.test.ts    │
│  │   └── login.test.ts   │
│  ├── package.json        │
│  └── tsconfig.json       │
│                          │
│  CHAT INFO               │
│  ┌────────────────────┐  │
│  │ Messages:  12      │  │
│  │ Duration:  5m 23s  │  │
│  └────────────────────┘  │
│                          │
│  TOKEN USAGE             │
│  ┌────────────────────┐  │
│  │ Input:   3,847     │  │
│  │ Output:  1,204     │  │
│  │ ─────────────────  │  │
│  │ Total:   5,051     │  │
│  └────────────────────┘  │
│                          │
│  SESSION                 │
│  ┌────────────────────┐  │
│  │ ID: abc-123...     │  │
│  │ 🟢 Connected       │  │
│  └────────────────────┘  │
└──────────────────────────┘
```

### 20. Dock Menu (B1)

```
┌─────────────────────────┐
│  New Chat               │
│  ─────────────────────  │
│  New Terminal Tab        │
│  New Claude TUI Tab      │
│  New OpenCode Tab        │
│  ─────────────────────  │
│  Recent Folders        ▸ │
│    ~/projects/app        │
│    ~/projects/api        │
│    ~/projects/lib        │
└─────────────────────────┘
```

### 21. File Menu (B1)

```
┌─────────────────────────────┐
│  New Chat              ⌘T   │
│  ───────────────────────    │
│  New Claude TUI Tab   ⌘⇧T   │
│  New OpenCode Tab     ⌘⌥T   │
│  New Terminal Tab    ⌘⇧⌥T   │
│  ───────────────────────    │
│  Open Folder...       ⌘O   │
│  ───────────────────────    │
│  Close Tab            ⌘W   │
└─────────────────────────────┘
```

### Component Hierarchy Diagram

```
MainView
├── TabBarView
│   ├── TabItemView (💬 Chat: app)        ← chat icon, no "β"
│   ├── TabItemView (💬 Chat: api)
│   ├── TabItemView (⬛ Terminal)
│   └── NewTabButton (+)
│
├── HStack
│   ├── TerminalContainerView
│   │   ├── EmptyTerminalView              ← chat-first button order
│   │   │   ├── ChatTabTypeButton          ← primary, no "Beta" badge
│   │   │   ├── Divider
│   │   │   └── TabTypeButton (×3)         ← terminal, claude TUI, opencode
│   │   │
│   │   └── ActiveTerminalView
│   │       ├── ChatView                   ← for .chat mode tabs
│   │       │   ├── ChatStatusBar          ← connection + tokens + clear + md toggle
│   │       │   ├── ChatEmptyStateView     ← suggestions chips
│   │       │   │   OR
│   │       │   ├── ChatMessageListView
│   │       │   │   └── MessageBubbleView (×N)
│   │       │   │       ├── RoleAvatarView
│   │       │   │       ├── ContentBlockView (×N)
│   │       │   │       │   ├── MarkdownRendererView     ← B2: full AST
│   │       │   │       │   │   ├── MarkdownHeadingView
│   │       │   │       │   │   ├── CodeBlockView        ← with CopyButton
│   │       │   │       │   │   ├── InlineMarkdownView
│   │       │   │       │   │   ├── MarkdownBlockquoteView
│   │       │   │       │   │   ├── MarkdownListView
│   │       │   │       │   │   └── MarkdownTableView
│   │       │   │       │   ├── ThinkingBlockView        ← expandable
│   │       │   │       │   └── ToolBlockRouter           ← B3: groups use+result
│   │       │   │       │       ├── BashToolView
│   │       │   │       │       ├── FileToolView
│   │       │   │       │       ├── EditToolView
│   │       │   │       │       ├── SearchToolView
│   │       │   │       │       └── GenericToolView
│   │       │   │       ├── MessageMetadataRow            ← B4: time + tokens
│   │       │   │       └── StreamingIndicatorView        ← B4: context-aware
│   │       │   ├── ChatErrorBanner
│   │       │   └── ChatInputView          ← B4: history, larger
│   │       │
│   │       └── StandaloneTerminalView     ← for .terminal mode tabs
│   │
│   └── SidebarView
│       └── ChatSidebarView               ← B4: session info + connection
│
└── StatusBarView                          ← git branch + version
```

## Modified File Summary

| Path | Tracks | Changes |
|------|--------|---------|
| `Chat/State/ChatState.swift` | A1,A3,A4 | Rewrite: thin adapter over engine+transport |
| `Chat/State/ChatError.swift` | A1 | Delete (replaced by ChatSessionError) |
| `Chat/Models/ChatConversation.swift` | A3 | Add `fromSnapshot()` |
| `Chat/Views/MarkdownTextView.swift` | B2 | Delegate to MarkdownRendererView |
| `Chat/Views/MessageBubbleView.swift` | B2,B3,B4 | New renderer, tool routing, metadata row |
| `Chat/Views/ChatView.swift` | B1,B4 | Status bar, empty state suggestions |
| `Chat/Views/ChatInputView.swift` | B4 | History, sizing |
| `Services/Logger.swift` | A5 | Add `.chat` category |
| `App/SlothyTerminalApp.swift` | B1 | Shortcuts, menu order |
| `App/AppState.swift` | A3,B1 | Resume variant, chat notification |
| `App/AppDelegate.swift` | B1 | Dock menu chat item |
| `Views/TerminalContainerView.swift` | B1 | Empty state reorder, remove Beta |
| `Views/TabBarView.swift` | B1 | Remove β prefix |
| `Models/Tab.swift` | B1 | Remove "(Beta)" from title |
| `Models/AppConfig.swift` | B1 | defaultTabMode, newChatTab shortcut |
| `Views/SettingsView.swift` | B1 | Default tab mode picker |
| `Chat/Views/ChatMessageListView.swift` | B3 | Pass isStreaming to content views |
