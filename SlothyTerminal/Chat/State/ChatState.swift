import Foundation

/// Manages a chat session with Claude CLI using a single persistent Foundation.Process.
/// Uses `--input-format stream-json --output-format stream-json` for bidirectional NDJSON.
@Observable
class ChatState {
  var conversation: ChatConversation
  var isLoading: Bool = false
  var error: ChatError?
  var sessionId: String?

  /// The persistent Claude process.
  private var process: Process?

  /// Stdin pipe for sending user messages to the process.
  private var stdinPipe: Pipe?

  /// Whether the process is running and ready to accept messages.
  private var isProcessRunning: Bool = false

  /// The currently streaming assistant message.
  private var currentMessage: ChatMessage?

  /// The task reading stdout lines.
  private var readingTask: Task<Void, Never>?

  init(workingDirectory: URL) {
    self.conversation = ChatConversation(workingDirectory: workingDirectory)
  }

  /// Sends a user message and waits for the assistant response.
  @MainActor
  func sendMessage(_ text: String) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !trimmed.isEmpty else {
      return
    }

    /// Add user message to conversation.
    let userMessage = ChatMessage(role: .user, contentBlocks: [.text(trimmed)])
    conversation.addMessage(userMessage)

    error = nil
    isLoading = true

    /// Create assistant message placeholder.
    let assistantMessage = ChatMessage(role: .assistant, isStreaming: true)
    conversation.addMessage(assistantMessage)
    currentMessage = assistantMessage

    /// Ensure the process is running, then send the message.
    if !isProcessRunning {
      startProcess()
    }

    writeUserMessage(trimmed)
  }

  /// Cancels the current streaming response.
  func cancelResponse() {
    if let message = currentMessage {
      message.isStreaming = false
    }

    currentMessage = nil
    isLoading = false
  }

  /// Clears the conversation and terminates the process.
  func clearConversation() {
    terminateProcess()
    conversation.clear()
    sessionId = nil
    error = nil
    isLoading = false
    currentMessage = nil
  }

  /// Terminates the persistent process. Called when closing the tab.
  func terminateProcess() {
    readingTask?.cancel()
    readingTask = nil

    if let process,
       process.isRunning
    {
      process.terminate()
    }

    process = nil
    stdinPipe = nil
    isProcessRunning = false
  }

  // MARK: - Private

  @MainActor
  private func startProcess() {
    guard let executablePath = resolveClaudePath() else {
      error = .claudeNotFound
      isLoading = false
      currentMessage?.isStreaming = false
      currentMessage = nil
      return
    }

    let proc = Process()
    let stdin = Pipe()
    let stdout = Pipe()
    let stderr = Pipe()

    proc.executableURL = URL(fileURLWithPath: executablePath)
    proc.arguments = [
      "-p",
      "--input-format", "stream-json",
      "--output-format", "stream-json",
      "--verbose",
      "--include-partial-messages",
    ]
    proc.currentDirectoryURL = conversation.workingDirectory
    proc.environment = buildEnvironment()
    proc.standardInput = stdin
    proc.standardOutput = stdout
    proc.standardError = stderr

    do {
      try proc.run()
    } catch {
      self.error = .processFailure(error.localizedDescription)
      isLoading = false
      currentMessage?.isStreaming = false
      currentMessage = nil
      return
    }

    self.process = proc
    self.stdinPipe = stdin
    self.isProcessRunning = true

    /// Start reading stdout in a background task.
    readingTask = Task { [weak self] in
      let handle = stdout.fileHandleForReading
      do {
        for try await line in handle.bytes.lines {
          if Task.isCancelled {
            break
          }

          guard let event = StreamEventParser.parse(line: line) else {
            continue
          }

          await self?.handleStreamEvent(event)
        }
      } catch {
        if !Task.isCancelled {
          await MainActor.run {
            self?.error = .processFailure(error.localizedDescription)
          }
        }
      }

      /// Process ended.
      await MainActor.run {
        self?.isProcessRunning = false
        self?.currentMessage?.isStreaming = false
        self?.currentMessage = nil

        if self?.isLoading == true {
          self?.isLoading = false
        }
      }
    }

    /// Handle unexpected process termination.
    proc.terminationHandler = { [weak self] process in
      Task { @MainActor in
        self?.isProcessRunning = false

        if process.terminationStatus != 0,
           self?.error == nil
        {
          let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
          let stderrText = String(data: stderrData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

          if !stderrText.isEmpty {
            self?.error = .processFailure(stderrText)
          }
        }

        if self?.isLoading == true {
          self?.currentMessage?.isStreaming = false
          self?.currentMessage = nil
          self?.isLoading = false
        }
      }
    }
  }

  private func writeUserMessage(_ text: String) {
    guard let stdinPipe else {
      return
    }

    let messageJSON: [String: Any] = [
      "type": "user",
      "message": [
        "role": "user",
        "content": [
          ["type": "text", "text": text]
        ]
      ]
    ]

    guard let data = try? JSONSerialization.data(withJSONObject: messageJSON),
          var jsonString = String(data: data, encoding: .utf8)
    else {
      return
    }

    jsonString += "\n"

    if let writeData = jsonString.data(using: .utf8) {
      stdinPipe.fileHandleForWriting.write(writeData)
    }
  }

  @MainActor
  private func handleStreamEvent(_ event: StreamEvent) {
    switch event {
    case .system(let sid):
      sessionId = sid

    case .assistant(let content, let inputTokens, let outputTokens):
      guard let message = currentMessage else {
        return
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

    case .result(_, let inputTokens, let outputTokens):
      guard let message = currentMessage else {
        return
      }

      /// Finalize the message.
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
      isLoading = false

    /// Legacy per-message streaming events — still handle for compatibility.
    case .messageStart(let inputTokens):
      currentMessage?.inputTokens = inputTokens

    case .contentBlockStart(let index, let blockType, let id):
      guard let message = currentMessage else {
        return
      }

      let block: ChatContentBlock
      switch blockType {
      case "thinking":
        block = .thinking("")

      case "tool_use":
        block = .toolUse(id: id ?? "", name: "", input: "")

      default:
        block = .text("")
      }

      /// Ensure contentBlocks array is large enough for this index.
      while message.contentBlocks.count <= index {
        message.contentBlocks.append(.text(""))
      }

      message.contentBlocks[index] = block

    case .contentBlockDelta(let index, let deltaType, let text):
      guard let message = currentMessage,
            index < message.contentBlocks.count
      else {
        return
      }

      let existing = message.contentBlocks[index]
      switch (existing, deltaType) {
      case (.text(let current), "text_delta"):
        message.contentBlocks[index] = .text(current + text)

      case (.thinking(let current), "thinking_delta"):
        message.contentBlocks[index] = .thinking(current + text)

      case (.toolUse(let id, let name, let input), "input_json_delta"):
        message.contentBlocks[index] = .toolUse(id: id, name: name, input: input + text)

      default:
        break
      }

    case .contentBlockStop:
      break

    case .messageDelta(_, let outputTokens):
      currentMessage?.outputTokens = outputTokens

    case .messageStop:
      currentMessage?.isStreaming = false
      currentMessage = nil
      isLoading = false

    case .unknown:
      break
    }
  }

  private func buildEnvironment() -> [String: String] {
    var env = ProcessInfo.processInfo.environment

    let extraPaths = [
      "/opt/homebrew/bin",
      "/usr/local/bin",
      "\(NSHomeDirectory())/.local/bin",
      "\(NSHomeDirectory())/.claude/local",
    ]

    let existingPath = env["PATH"] ?? "/usr/bin:/bin"
    let combinedPath = (extraPaths + [existingPath]).joined(separator: ":")
    env["PATH"] = combinedPath

    env["TERM"] = "xterm-256color"
    env["COLORTERM"] = "truecolor"

    return env
  }

  private func resolveClaudePath() -> String? {
    if let envPath = ProcessInfo.processInfo.environment["CLAUDE_PATH"],
       FileManager.default.isExecutableFile(atPath: envPath)
    {
      return envPath
    }

    let commonPaths = [
      "\(NSHomeDirectory())/.local/bin/claude",
      "\(NSHomeDirectory())/.claude/local/claude",
      "\(NSHomeDirectory())/bin/claude",
      "/usr/local/bin/claude",
      "/opt/homebrew/bin/claude",
    ]

    for path in commonPaths {
      if FileManager.default.isExecutableFile(atPath: path),
         isBinaryExecutable(atPath: path)
      {
        return path
      }
    }

    for path in commonPaths {
      if FileManager.default.isExecutableFile(atPath: path) {
        return path
      }
    }

    let whichProcess = Process()
    let pipe = Pipe()
    whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
    whichProcess.arguments = ["claude"]
    whichProcess.standardOutput = pipe
    whichProcess.environment = buildEnvironment()

    do {
      try whichProcess.run()
      whichProcess.waitUntilExit()

      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      let path = String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines)

      if let path,
         !path.isEmpty,
         FileManager.default.isExecutableFile(atPath: path)
      {
        return path
      }
    } catch {}

    return nil
  }

  private func isBinaryExecutable(atPath path: String) -> Bool {
    let resolvedPath: String
    do {
      resolvedPath = try FileManager.default.destinationOfSymbolicLink(atPath: path)
    } catch {
      resolvedPath = path
    }

    guard let fileHandle = FileHandle(forReadingAtPath: resolvedPath) else {
      return false
    }

    defer { fileHandle.closeFile() }

    let magic = fileHandle.readData(ofLength: 4)

    guard magic.count >= 4 else {
      return false
    }

    let magicBytes = [UInt8](magic)
    let machO64: [UInt8] = [0xCF, 0xFA, 0xED, 0xFE]
    let machO64Reversed: [UInt8] = [0xFE, 0xED, 0xFA, 0xCF]
    let fatBinary: [UInt8] = [0xCA, 0xFE, 0xBA, 0xBE]

    return magicBytes == machO64
      || magicBytes == machO64Reversed
      || magicBytes == fatBinary
  }
}
