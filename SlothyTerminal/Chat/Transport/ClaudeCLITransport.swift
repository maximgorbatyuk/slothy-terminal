import Foundation
import OSLog

/// Concrete transport using Foundation.Process + NDJSON over stdio.
///
/// Extracted from `ChatState` to isolate all process management,
/// making the engine testable with a mock transport.
class ClaudeCLITransport: ChatTransport {
  private let workingDirectory: URL
  private let resumeSessionId: String?

  private var process: Process?
  private var stdinPipe: Pipe?
  private var readingTask: Task<Void, Never>?
  private(set) var isRunning: Bool = false

  /// Accumulated stderr output, drained asynchronously to prevent
  /// pipe buffer deadlock when the CLI writes verbose output.
  private var stderrBuffer = Data()
  private let stderrLock = NSLock()

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
      Logger.chat.error("Claude CLI not found at any expected path")
      onError(ChatSessionError.transportNotAvailable("Claude CLI not found"))
      return
    }

    Logger.chat.info("Starting Claude CLI at: \(executablePath)")

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
      Logger.chat.error("Failed to start Claude CLI: \(error.localizedDescription)")
      onError(ChatSessionError.transportStartFailed(error.localizedDescription))
      return
    }

    Logger.chat.info("Claude CLI started, pid=\(proc.processIdentifier)")

    self.process = proc
    self.stdinPipe = stdin
    self.isRunning = true

    /// Drain stderr asynchronously to prevent pipe buffer deadlock.
    /// Without this, the CLI can block when the 16KB pipe buffer fills
    /// (especially with --verbose output), hanging the entire session.
    stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
      let data = handle.availableData

      guard !data.isEmpty,
            let self
      else {
        return
      }

      if let text = String(data: data, encoding: .utf8) {
        Logger.chat.debug("⚠ stderr: \(text.prefix(500))")
      }

      self.stderrLock.lock()
      self.stderrBuffer.append(data)
      self.stderrLock.unlock()
    }

    /// Background stdout reading task.
    readingTask = Task { [weak self] in
      let handle = stdout.fileHandleForReading
      do {
        for try await line in handle.bytes.lines {
          if Task.isCancelled {
            break
          }

          Logger.chat.debug("← recv: \(line.prefix(500))")

          guard let event = StreamEventParser.parse(line: line) else {
            Logger.chat.debug("← (unparsed, skipped)")
            continue
          }

          /// Intercept system event to extract sessionId.
          if case .system(let sessionId) = event {
            Logger.chat.info("Transport ready, sessionId=\(sessionId)")
            onReady(sessionId)
          }

          onEvent(event)
        }
      } catch {
        if !Task.isCancelled {
          Logger.chat.error("Stdout reading error: \(error.localizedDescription)")
          onError(error)
        }
      }

      self?.isRunning = false
    }

    /// Process termination handler.
    proc.terminationHandler = { [weak self] process in
      self?.isRunning = false

      /// Stop draining stderr.
      stderr.fileHandleForReading.readabilityHandler = nil

      let stderrText: String
      if let self {
        self.stderrLock.lock()
        stderrText = String(data: self.stderrBuffer, encoding: .utf8)?
          .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.stderrLock.unlock()
      } else {
        stderrText = ""
      }

      if process.terminationStatus == 0 {
        Logger.chat.info("Claude CLI exited normally")
        onTerminated(.normal)
      } else {
        Logger.chat.error(
          "Claude CLI crashed, exit=\(process.terminationStatus), stderr=\(stderrText.prefix(500))"
        )
        onTerminated(.crash(exitCode: process.terminationStatus, stderr: stderrText))
      }
    }
  }

  func send(message: String) {
    guard let stdinPipe else {
      Logger.chat.warning("send() called but stdinPipe is nil")
      return
    }

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
    else {
      Logger.chat.error("Failed to serialize message JSON")
      return
    }

    jsonString += "\n"

    if let writeData = jsonString.data(using: .utf8) {
      Logger.chat.debug("→ send (\(writeData.count) bytes): \(jsonString.prefix(500))")
      stdinPipe.fileHandleForWriting.write(writeData)
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
    stdinPipe = nil
    isRunning = false
  }

  // MARK: - Private helpers

  private func buildArguments() -> [String] {
    var args = [
      "-p",
      "--input-format", "stream-json",
      "--output-format", "stream-json",
      "--verbose",
      "--include-partial-messages",
    ]

    if let resumeSessionId {
      args.append(contentsOf: ["--resume", resumeSessionId])
    }

    return args
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

    /// Prefer binary executables (Mach-O) over scripts.
    for path in commonPaths {
      if FileManager.default.isExecutableFile(atPath: path),
         isBinaryExecutable(atPath: path)
      {
        return path
      }
    }

    /// Fallback to any executable.
    for path in commonPaths {
      if FileManager.default.isExecutableFile(atPath: path) {
        return path
      }
    }

    /// Last resort: use `which`.
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
