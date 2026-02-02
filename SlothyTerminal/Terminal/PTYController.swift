import Foundation

/// Error types for PTY operations.
enum PTYError: Error, LocalizedError {
  case forkFailed
  case execFailed
  case writeFailed
  case invalidFileDescriptor
  case processNotRunning

  var errorDescription: String? {
    switch self {
    case .forkFailed:
      return "Failed to create pseudo-terminal"
    case .execFailed:
      return "Failed to execute command"
    case .writeFailed:
      return "Failed to write to terminal"
    case .invalidFileDescriptor:
      return "Invalid file descriptor"
    case .processNotRunning:
      return "Process is not running"
    }
  }
}

/// Controller for managing a pseudo-terminal (PTY) session.
/// Wraps POSIX forkpty() to spawn and communicate with child processes.
@Observable
@MainActor
class PTYController {
  private var masterFD: Int32 = -1
  private var childPID: pid_t = 0
  private var readTask: Task<Void, Never>?
  private(set) var isRunning: Bool = false

  /// Stream of data received from the PTY.
  private nonisolated(unsafe) var outputContinuation: AsyncStream<Data>.Continuation?

  /// Spawns a new process in a pseudo-terminal.
  /// - Parameters:
  ///   - command: The command to execute.
  ///   - args: Arguments to pass to the command.
  ///   - workingDirectory: The working directory for the process.
  ///   - environment: Additional environment variables.
  func spawn(
    command: String,
    args: [String] = [],
    workingDirectory: URL,
    environment: [String: String] = [:]
  ) async throws {
    guard !isRunning else {
      return
    }

    /// Prepare arguments array for execv.
    let argv = [command] + args
    let cArgs = argv.map { strdup($0) } + [nil]
    defer {
      for arg in cArgs {
        free(arg)
      }
    }

    /// Prepare environment.
    var env = ProcessInfo.processInfo.environment
    for (key, value) in environment {
      env[key] = value
    }
    let cEnv = env.map { strdup("\($0.key)=\($0.value)") } + [nil]
    defer {
      for e in cEnv {
        free(e)
      }
    }

    /// Window size for the PTY.
    var winSize = winsize(
      ws_row: 24,
      ws_col: 80,
      ws_xpixel: 0,
      ws_ypixel: 0
    )

    /// Fork the process with a PTY.
    let pid = forkpty(&masterFD, nil, nil, &winSize)

    if pid < 0 {
      throw PTYError.forkFailed
    } else if pid == 0 {
      /// Child process.
      /// Change to working directory.
      FileManager.default.changeCurrentDirectoryPath(workingDirectory.path)

      /// Execute the command.
      execve(command, cArgs, cEnv)

      /// If execve returns, it failed.
      _exit(1)
    } else {
      /// Parent process.
      childPID = pid
      isRunning = true

      /// Set non-blocking mode on master file descriptor.
      let flags = fcntl(masterFD, F_GETFL)
      _ = fcntl(masterFD, F_SETFL, flags | O_NONBLOCK)

      /// Start reading from the PTY.
      startReading()
    }
  }

  /// Writes data to the PTY.
  /// - Parameter data: The data to write.
  func write(_ data: Data) throws {
    guard isRunning,
          masterFD >= 0
    else {
      throw PTYError.processNotRunning
    }

    let result = data.withUnsafeBytes { buffer in
      Darwin.write(masterFD, buffer.baseAddress, buffer.count)
    }

    if result < 0 {
      throw PTYError.writeFailed
    }
  }

  /// Writes a string to the PTY.
  /// - Parameter string: The string to write.
  func write(_ string: String) throws {
    guard let data = string.data(using: .utf8) else {
      return
    }

    try write(data)
  }

  /// Returns an async stream of data from the PTY.
  func read() -> AsyncStream<Data> {
    AsyncStream { continuation in
      self.outputContinuation = continuation

      continuation.onTermination = { [weak self] _ in
        self?.outputContinuation = nil
      }
    }
  }

  /// Resizes the PTY window.
  /// - Parameters:
  ///   - cols: Number of columns.
  ///   - rows: Number of rows.
  func resize(cols: Int, rows: Int) {
    guard masterFD >= 0 else {
      return
    }

    var winSize = winsize(
      ws_row: UInt16(rows),
      ws_col: UInt16(cols),
      ws_xpixel: 0,
      ws_ypixel: 0
    )

    _ = ioctl(masterFD, TIOCSWINSZ, &winSize)
  }

  /// Terminates the PTY session and child process.
  func terminate() {
    readTask?.cancel()
    readTask = nil

    outputContinuation?.finish()
    outputContinuation = nil

    if childPID > 0 {
      kill(childPID, SIGTERM)

      /// Give the process a moment to terminate gracefully.
      var status: Int32 = 0
      let waitResult = waitpid(childPID, &status, WNOHANG)

      if waitResult == 0 {
        /// Process hasn't exited yet, force kill.
        kill(childPID, SIGKILL)
        waitpid(childPID, &status, 0)
      }

      childPID = 0
    }

    if masterFD >= 0 {
      close(masterFD)
      masterFD = -1
    }

    isRunning = false
  }

  /// Starts the background task for reading PTY output.
  private func startReading() {
    readTask = Task.detached { [weak self] in
      guard let self else {
        return
      }

      let bufferSize = 4096
      var buffer = [UInt8](repeating: 0, count: bufferSize)

      while !Task.isCancelled {
        let fd = await self.masterFD

        guard fd >= 0 else {
          break
        }

        let bytesRead = Darwin.read(fd, &buffer, bufferSize)

        if bytesRead > 0 {
          let data = Data(buffer[0..<bytesRead])
          _ = await MainActor.run {
            self.outputContinuation?.yield(data)
          }
        } else if bytesRead == 0 {
          /// EOF - process has exited.
          await MainActor.run {
            self.isRunning = false
            self.outputContinuation?.finish()
          }
          break
        } else if errno != EAGAIN && errno != EWOULDBLOCK {
          /// Real error occurred.
          await MainActor.run {
            self.isRunning = false
            self.outputContinuation?.finish()
          }
          break
        }

        /// Small delay to prevent busy-waiting.
        try? await Task.sleep(for: .milliseconds(10))
      }
    }
  }
}
