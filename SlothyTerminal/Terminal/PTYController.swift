import Foundation

/// Error types for PTY operations.
enum PTYError: Error, LocalizedError {
  case forkFailed
  case execFailed
  case writeFailed
  case invalidFileDescriptor
  case processNotRunning
  case encodingFailed

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

    case .encodingFailed:
      return "Failed to encode string as UTF-8"
    }
  }
}

/// Thread-safe storage for AsyncStream continuation.
/// Isolates the continuation from MainActor to allow safe access from detached tasks.
private final class ContinuationHolder: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: AsyncStream<Data>.Continuation?

  func set(_ newValue: AsyncStream<Data>.Continuation?) {
    lock.lock()
    defer { lock.unlock() }
    continuation = newValue
  }

  func get() -> AsyncStream<Data>.Continuation? {
    lock.lock()
    defer { lock.unlock() }
    return continuation
  }

  func finish() {
    lock.lock()
    let cont = continuation
    continuation = nil
    lock.unlock()
    cont?.finish()
  }

  func yield(_ data: Data) {
    lock.lock()
    let cont = continuation
    lock.unlock()
    cont?.yield(data)
  }
}

/// Thread-safe holder for the child process ID and master file descriptor.
/// Allows `deinit` (which is nonisolated) to clean up process resources
/// that would otherwise be inaccessible behind MainActor isolation.
private final class ProcessResourceHolder: @unchecked Sendable {
  private let lock = NSLock()
  private var masterFD: Int32 = -1
  private var childPID: pid_t = 0

  func set(fd: Int32, pid: pid_t) {
    lock.lock()
    defer { lock.unlock() }
    masterFD = fd
    childPID = pid
  }

  func setFD(_ fd: Int32) {
    lock.lock()
    defer { lock.unlock() }
    masterFD = fd
  }

  func setPID(_ pid: pid_t) {
    lock.lock()
    defer { lock.unlock() }
    childPID = pid
  }

  func getFD() -> Int32 {
    lock.lock()
    defer { lock.unlock() }
    return masterFD
  }

  func getPID() -> pid_t {
    lock.lock()
    defer { lock.unlock() }
    return childPID
  }

  /// Terminates the child process (if alive) and closes the master FD.
  /// Safe to call from any isolation context, including `deinit`.
  func cleanup() {
    lock.lock()
    let fd = masterFD
    let pid = childPID
    masterFD = -1
    childPID = 0
    lock.unlock()

    if pid > 0 {
      if fd >= 0 {
        close(fd)
      }
      kill(-pid, SIGTERM)

      var status: Int32 = 0
      if waitpid(pid, &status, WNOHANG) == 0 {
        kill(-pid, SIGKILL)
        waitpid(pid, &status, 0)
      }
    } else if fd >= 0 {
      close(fd)
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

  /// Thread-safe holder for the output continuation.
  private let continuationHolder = ContinuationHolder()

  /// Thread-safe holder for process resources, enabling cleanup from `deinit`.
  private let processResources = ProcessResourceHolder()

  /// Safety net: clean up child process and file descriptor if the controller
  /// is deallocated without an explicit `terminate()` call.
  /// Note: readTask is not cancelled here because it is MainActor-isolated.
  /// It will exit on its own — the [weak self] reference becomes nil, and
  /// cleanup() closes the FD which breaks the read loop.
  deinit {
    continuationHolder.finish()
    processResources.cleanup()
  }

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
      processResources.set(fd: masterFD, pid: pid)

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
      throw PTYError.encodingFailed
    }

    try write(data)
  }

  /// Returns an async stream of data from the PTY.
  func read() -> AsyncStream<Data> {
    let holder = continuationHolder

    return AsyncStream { continuation in
      holder.set(continuation)

      continuation.onTermination = { _ in
        holder.set(nil)
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

    continuationHolder.finish()

    if childPID > 0 {
      /// Close master FD first — the kernel sends SIGHUP to the child's
      /// session when the master side of the PTY is closed.
      if masterFD >= 0 {
        close(masterFD)
        masterFD = -1
      }

      /// Send SIGTERM to the entire process group so sub-processes
      /// spawned by the agent (e.g. language servers) are also signaled.
      kill(-childPID, SIGTERM)

      /// Poll for up to ~100 ms to let the process exit gracefully.
      var status: Int32 = 0
      for _ in 0..<10 {
        if waitpid(childPID, &status, WNOHANG) != 0 {
          childPID = 0
          processResources.set(fd: -1, pid: 0)
          isRunning = false
          return
        }
        usleep(10_000)
      }

      /// Still alive — force kill the process group and reap.
      kill(-childPID, SIGKILL)
      waitpid(childPID, &status, 0)
      childPID = 0
    }

    if masterFD >= 0 {
      close(masterFD)
      masterFD = -1
    }

    /// Mark process resources as cleaned up so deinit won't double-close.
    processResources.set(fd: -1, pid: 0)
    isRunning = false
  }

  /// Starts the background task for reading PTY output.
  private func startReading() {
    let holder = continuationHolder
    let resources = processResources

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
          holder.yield(data)
        } else if bytesRead == 0 {
          /// EOF — process has exited. Reap to avoid zombies.
          resources.setPID(0)
          await MainActor.run {
            if self.childPID > 0 {
              var status: Int32 = 0
              waitpid(self.childPID, &status, WNOHANG)
              self.childPID = 0
            }
            self.isRunning = false
          }
          holder.finish()
          break
        } else if errno != EAGAIN && errno != EWOULDBLOCK {
          /// Real error — reap to avoid zombies.
          resources.setPID(0)
          await MainActor.run {
            if self.childPID > 0 {
              var status: Int32 = 0
              waitpid(self.childPID, &status, WNOHANG)
              self.childPID = 0
            }
            self.isRunning = false
          }
          holder.finish()
          break
        }

        /// Small delay to prevent busy-waiting.
        try? await Task.sleep(for: .milliseconds(10))
      }
    }
  }
}
