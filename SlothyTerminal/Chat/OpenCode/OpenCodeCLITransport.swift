import Foundation
import OSLog

/// Transport for OpenCode CLI using `opencode run --format json`.
///
/// Unlike Claude CLI (persistent process, messages via stdin), OpenCode
/// spawns **one process per message** (message as positional arg).
/// Session continuity is maintained via `--session <id>`.
///
/// The transport stays "running" between messages — only the per-message
/// subprocess starts and stops. `terminate()` kills the current subprocess
/// and marks the transport as finished.
class OpenCodeCLITransport: ChatTransport {
  private let workingDirectory: URL
  private let executablePathOverride: String?
  private var sessionId: String?

  /// Model and mode can change per-send (OpenCode spawns per message).
  var currentModel: ChatModelSelection?
  var currentMode: ChatMode?

  /// Interactive guidance mode for clarifying-question-first behavior.
  var askModeEnabled: Bool

  private var process: Process?
  private var readingTask: Task<Void, Never>?
  private(set) var isRunning: Bool = false

  /// Set `true` in `terminate()` before sending SIGTERM so the
  /// termination handler can distinguish manual shutdown from a crash
  /// and invoke `onTerminated` exactly once with the correct reason.
  private var didRequestTerminate: Bool = false

  /// Mapper context tracking block indices and text block state within a turn.
  private var mapperContext = OpenCodeMapperContext()

  /// Tracks if the current turn reached terminal `result`.
  private var didReceiveResultInCurrentTurn = false

  /// Captures the latest explicit OpenCode `error` event message.
  private var streamErrorMessage: String?

  /// Captures non-JSON stdout lines (stack traces, warnings) for diagnostics.
  private var stdoutDiagnostics: [String] = []
  private let maxDiagnosticLines = 20

  /// Accumulated stderr output for crash diagnostics.
  private var stderrBuffer = Data()
  private let stderrLock = NSLock()

  private var onEvent: ((StreamEvent) -> Void)?
  private var onReady: ((String) -> Void)?
  private var onError: ((Error) -> Void)?
  private var onTerminated: ((TerminationReason) -> Void)?

  init(
    workingDirectory: URL,
    resumeSessionId: String? = nil,
    currentModel: ChatModelSelection? = nil,
    currentMode: ChatMode? = nil,
    askModeEnabled: Bool = false,
    executablePathOverride: String? = nil
  ) {
    self.workingDirectory = workingDirectory
    self.sessionId = resumeSessionId
    self.currentModel = currentModel
    self.currentMode = currentMode
    self.askModeEnabled = askModeEnabled
    self.executablePathOverride = executablePathOverride?
      .trimmingCharacters(in: .whitespacesAndNewlines)
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
    self.isRunning = true

    /// No process to spawn yet — ready immediately only when we already
    /// have a resume session ID.
    if let sessionId,
       !sessionId.isEmpty
    {
      onReady(sessionId)
    }
  }

  func send(message: String) {
    guard isRunning else {
      Logger.chat.warning("OpenCode send() called but transport is not running")
      return
    }

    guard let executablePath = resolveOpenCodePath() else {
      Logger.chat.error("OpenCode CLI not found at any expected path")
      onError?(ChatSessionError.transportNotAvailable("OpenCode CLI not found"))
      return
    }

    Logger.chat.info("Spawning OpenCode process at: \(executablePath)")

    let args = buildArguments(message: messageForCLI(message))

    Logger.chat.debug("→ OpenCode send (chars=\(message.count)): \(message.prefix(500))")
    Logger.chat.debug("→ OpenCode args: \(args.joined(separator: " "))")

    let proc = Process()
    let stdout = Pipe()
    let stderr = Pipe()

    proc.executableURL = URL(fileURLWithPath: executablePath)
    proc.arguments = args
    proc.currentDirectoryURL = workingDirectory
    proc.environment = buildEnvironment()
    proc.standardOutput = stdout
    proc.standardError = stderr

    /// Reset per-turn state.
    mapperContext = OpenCodeMapperContext()
    didReceiveResultInCurrentTurn = false
    streamErrorMessage = nil
    stdoutDiagnostics = []
    stderrLock.lock()
    stderrBuffer = Data()
    stderrLock.unlock()

    do {
      try proc.run()
    } catch {
      Logger.chat.error("Failed to start OpenCode: \(error.localizedDescription)")
      onError?(ChatSessionError.transportStartFailed(error.localizedDescription))
      return
    }

    Logger.chat.info("OpenCode process started, pid=\(proc.processIdentifier)")
    self.process = proc

    /// Drain stderr to prevent pipe buffer deadlock.
    stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
      let data = handle.availableData

      guard !data.isEmpty,
            let self
      else {
        return
      }

      if let text = String(data: data, encoding: .utf8) {
        Logger.chat.debug("OpenCode stderr: \(text.prefix(500))")
      }

      self.stderrLock.lock()
      self.stderrBuffer.append(data)
      self.stderrLock.unlock()
    }

    /// Read stdout line-by-line in background.
    readingTask = Task { [weak self] in
      let handle = stdout.fileHandleForReading
      var capturedSessionId = false

      do {
        for try await line in handle.bytes.lines {
          if Task.isCancelled {
            break
          }

          Logger.chat.debug("OpenCode recv: \(line.prefix(500))")

          guard let self else {
            continue
          }

          guard let parsed = OpenCodeStreamEventParser.parse(line: line) else {
            self.appendStdoutDiagnostic(line)
            Logger.chat.debug("← OpenCode (unparsed, skipped)")
            continue
          }

          /// Capture sessionID from the first event that has one.
          if !capturedSessionId,
             let newSessionId = parsed.sessionID,
             !newSessionId.isEmpty
          {
            capturedSessionId = true
            self.sessionId = newSessionId
            Logger.chat.info("OpenCode transport ready, sessionId=\(newSessionId)")
            self.onReady?(newSessionId)
          }

          if case .error(let part) = parsed.event {
            let diagnostic = part.message.isEmpty ? part.name : part.message
            self.streamErrorMessage = diagnostic
            Logger.chat.error("OpenCode error event: \(diagnostic.prefix(500))")
            continue
          }

          let streamEvents = OpenCodeEventMapper.map(
            parsed.event,
            context: &self.mapperContext
          )

          for streamEvent in streamEvents {
            if case .result = streamEvent {
              self.didReceiveResultInCurrentTurn = true
            }

            self.onEvent?(streamEvent)
          }
        }
      } catch {
        if !Task.isCancelled {
          Logger.chat.error("OpenCode stdout reading error: \(error.localizedDescription)")
          self?.onError?(error)
        }
      }
    }

    /// Handle process termination.
    proc.terminationHandler = { [weak self] process in
      guard let self else {
        return
      }

      /// Stop draining stderr.
      stderr.fileHandleForReading.readabilityHandler = nil
      self.process = nil

      let manualTerminate = self.didRequestTerminate
      self.didRequestTerminate = false

      if manualTerminate {
        Logger.chat.info("OpenCode process terminated by user request")
        self.isRunning = false
        self.onTerminated?(.normal)
        return
      }

      let stderrText: String
      self.stderrLock.lock()
      stderrText = String(data: self.stderrBuffer, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      self.stderrLock.unlock()

      let diagnosticText = self.combinedDiagnosticMessage(stderrText: stderrText)

      if process.terminationStatus == 0 {
        if self.didReceiveResultInCurrentTurn {
          Logger.chat.info("OpenCode process exited normally")
          /// Normal exit — transport stays alive for the next message.
          /// Do NOT call onTerminated here.
        } else {
          let message = diagnosticText.isEmpty
            ? "OpenCode exited before producing a response"
            : diagnosticText
          Logger.chat.error("OpenCode turn failed without result: \(message.prefix(500))")
          self.isRunning = false
          self.onTerminated?(.crash(exitCode: 1, stderr: message))
        }
      } else {
        let message = diagnosticText.isEmpty
          ? "OpenCode exited with status \(process.terminationStatus)"
          : diagnosticText
        Logger.chat.error(
          "OpenCode process crashed, exit=\(process.terminationStatus), detail=\(message.prefix(500))"
        )
        self.isRunning = false
        self.onTerminated?(.crash(
          exitCode: process.terminationStatus,
          stderr: message
        ))
      }
    }
  }

  func interrupt() {
    if let process,
       process.isRunning
    {
      process.interrupt()
    }
  }

  func terminate() {
    readingTask?.cancel()
    readingTask = nil

    if let process,
       process.isRunning
    {
      didRequestTerminate = true
      process.terminate()
    } else {
      /// No running process — terminationHandler won't fire,
      /// so invoke the callback directly.
      isRunning = false
      onTerminated?(.normal)
    }
  }

  // MARK: - Private helpers

  private func buildArguments(message: String) -> [String] {
    var args = ["run", "--format", "json"]

    if let sessionId,
       !sessionId.isEmpty
    {
      args.append(contentsOf: ["--session", sessionId])
    }

    if let currentModel {
      args.append(contentsOf: ["--model", currentModel.cliModelString])
    }

    if currentMode == .plan {
      /// `build` is the OpenCode default; only pass explicit agent for `plan`
      /// to keep compatibility with older CLI versions.
      args.append(contentsOf: ["--agent", "plan"])
    }

    args.append(message)
    return args
  }

  /// Wraps the user message with ask-mode directive when enabled.
  /// Note: The directive is prepended before the user message. While a crafted
  /// user message could theoretically confuse interpretation, this is acceptable
  /// since the user controls their own input and the directive is internal.
  private func messageForCLI(_ userMessage: String) -> String {
    guard askModeEnabled else {
      return userMessage
    }

    let directive = """
    Ask mode is enabled for this conversation.
    Ask clarifying questions before implementing when requirements are ambiguous or missing.
    Wait for the user's reply before finalizing a plan or writing code.
    If the user's message is answering your previous question, incorporate it and continue.
    """

    return "\(directive)\n\nUser message:\n\(userMessage)"
  }

  private func buildEnvironment() -> [String: String] {
    var env = ProcessInfo.processInfo.environment

    let extraPaths = [
      "/opt/homebrew/bin",
      "/usr/local/bin",
      "\(NSHomeDirectory())/.local/bin",
    ]

    let existingPath = env["PATH"] ?? "/usr/bin:/bin"
    let combinedPath = (extraPaths + [existingPath]).joined(separator: ":")
    env["PATH"] = combinedPath

    env["TERM"] = "xterm-256color"
    env["COLORTERM"] = "truecolor"

    return env
  }

  private func resolveOpenCodePath() -> String? {
    if let executablePathOverride,
       !executablePathOverride.isEmpty,
       FileManager.default.isExecutableFile(atPath: executablePathOverride)
    {
      return executablePathOverride
    }

    if let envPath = ProcessInfo.processInfo.environment["OPENCODE_PATH"],
       FileManager.default.isExecutableFile(atPath: envPath)
    {
      return envPath
    }

    /// Prefer shell PATH resolution to match user expectations.
    let whichProcess = Process()
    let pipe = Pipe()
    whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
    whichProcess.arguments = ["opencode"]
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

    let commonPaths = [
      "/opt/homebrew/bin/opencode",
      "/usr/local/bin/opencode",
      "\(NSHomeDirectory())/.local/bin/opencode",
      "\(NSHomeDirectory())/go/bin/opencode",
    ]

    for path in commonPaths {
      if FileManager.default.isExecutableFile(atPath: path) {
        return path
      }
    }

    return nil
  }

  private func appendStdoutDiagnostic(_ line: String) {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !trimmed.isEmpty else {
      return
    }

    stdoutDiagnostics.append(trimmed)

    if stdoutDiagnostics.count > maxDiagnosticLines {
      stdoutDiagnostics.removeFirst(stdoutDiagnostics.count - maxDiagnosticLines)
    }
  }

  private func combinedDiagnosticMessage(stderrText: String) -> String {
    if let streamErrorMessage,
       !streamErrorMessage.isEmpty
    {
      return streamErrorMessage
    }

    if !stderrText.isEmpty {
      return stderrText
    }

    if !stdoutDiagnostics.isEmpty {
      return stdoutDiagnostics.joined(separator: "\n")
    }

    return ""
  }
}
