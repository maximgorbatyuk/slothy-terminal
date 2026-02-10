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
  private var sessionId: String?

  /// Model and mode can change per-send (OpenCode spawns per message).
  var currentModel: ChatModelSelection?
  var currentMode: ChatMode?

  private var process: Process?
  private var readingTask: Task<Void, Never>?
  private(set) var isRunning: Bool = false

  /// Mapper context tracking block indices and text block state within a turn.
  private var mapperContext = OpenCodeMapperContext()

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
    currentMode: ChatMode? = nil
  ) {
    self.workingDirectory = workingDirectory
    self.sessionId = resumeSessionId
    self.currentModel = currentModel
    self.currentMode = currentMode
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

    let args = buildArguments(message: message)

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

          let streamEvents = OpenCodeEventMapper.map(
            parsed.event,
            context: &self.mapperContext
          )

          for streamEvent in streamEvents {
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

      let stderrText: String
      self.stderrLock.lock()
      stderrText = String(data: self.stderrBuffer, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      self.stderrLock.unlock()

      if process.terminationStatus == 0 {
        Logger.chat.info("OpenCode process exited normally")
        /// Normal exit — transport stays alive for the next message.
        /// Do NOT call onTerminated here.
      } else {
        Logger.chat.error(
          "OpenCode process crashed, exit=\(process.terminationStatus), stderr=\(stderrText.prefix(500))"
        )
        self.isRunning = false
        self.onTerminated?(.crash(
          exitCode: process.terminationStatus,
          stderr: stderrText
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
      process.terminate()
    }

    process = nil
    isRunning = false
    onTerminated?(.normal)
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

    if let currentMode {
      args.append(contentsOf: ["--agent", currentMode == .plan ? "plan" : "build"])
    }

    args.append(message)
    return args
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
    if let envPath = ProcessInfo.processInfo.environment["OPENCODE_PATH"],
       FileManager.default.isExecutableFile(atPath: envPath)
    {
      return envPath
    }

    let commonPaths = [
      "\(NSHomeDirectory())/.local/bin/opencode",
      "\(NSHomeDirectory())/go/bin/opencode",
      "/usr/local/bin/opencode",
      "/opt/homebrew/bin/opencode",
    ]

    for path in commonPaths {
      if FileManager.default.isExecutableFile(atPath: path) {
        return path
      }
    }

    /// Last resort: use `which`.
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

    return nil
  }
}
