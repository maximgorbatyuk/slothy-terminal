import Darwin
import Foundation

struct GitProcessResult {
  let stdout: String
  let stderr: String
  let terminationStatus: Int32

  var isSuccess: Bool {
    terminationStatus == 0
  }

  var didTimeOut: Bool {
    terminationStatus == 124
  }

  var wasCancelled: Bool {
    terminationStatus == 130
  }

  static func failure(
    stderr: String,
    terminationStatus: Int32 = 1
  ) -> GitProcessResult {
    GitProcessResult(
      stdout: "",
      stderr: stderr,
      terminationStatus: terminationStatus
    )
  }
}

/// Shared utility for running git commands off the main thread.
/// Used by `GitService` and `GitStatsService` to avoid duplicating process logic.
enum GitProcessRunner {
  private static let defaultTimeout: TimeInterval = 30

  /// Runs a git command and returns trimmed stdout, or nil on failure.
  static func run(
    _ arguments: [String],
    in directory: URL,
    timeout: TimeInterval = defaultTimeout
  ) async -> String? {
    let result = await runResult(arguments, in: directory, timeout: timeout)

    guard result.isSuccess, !result.stdout.isEmpty else {
      return nil
    }

    return result.stdout
  }

  /// Runs a git command and returns stdout, stderr, and exit status.
  static func runResult(
    _ arguments: [String],
    in directory: URL,
    timeout: TimeInterval = defaultTimeout
  ) async -> GitProcessResult {
    await runProcessResult(
      executableURL: URL(fileURLWithPath: "/usr/bin/git"),
      arguments: arguments,
      in: directory,
      environment: nil,
      timeout: timeout
    )
  }

  static func runProcessResult(
    executableURL: URL,
    arguments: [String],
    in directory: URL?,
    environment: [String: String]?,
    timeout: TimeInterval?
  ) async -> GitProcessResult {
    let operation = ProcessExecutionOperation(
      executableURL: executableURL,
      arguments: arguments,
      directory: directory,
      environment: environment,
      timeout: timeout
    )

    return await withTaskCancellationHandler {
      await operation.run()
    } onCancel: {
      operation.cancel()
    }
  }

  fileprivate static func trimmedOutput(from data: Data) -> String {
    String(data: data, encoding: .utf8)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  }

  fileprivate static func appendMessage(_ message: String, to output: String) -> String {
    guard !message.isEmpty else {
      return output
    }

    guard !output.isEmpty else {
      return message
    }

    return "\(output)\n\(message)"
  }

  fileprivate static func timeoutDescription(_ timeout: TimeInterval) -> String {
    if timeout.rounded() == timeout {
      return "\(Int(timeout))s"
    }

    return "\(timeout)s"
  }
}

private final class ProcessExecutionOperation: @unchecked Sendable {
  private enum RequestedTermination {
    case none
    case timedOut(TimeInterval)
    case cancelled
  }

  private let process = Process()
  private let stdoutPipe = Pipe()
  private let stderrPipe = Pipe()
  private let timeout: TimeInterval?
  private let lock = NSLock()

  private var stdoutData = Data()
  private var stderrData = Data()
  private var continuation: CheckedContinuation<GitProcessResult, Never>?
  private var timeoutWorkItem: DispatchWorkItem?
  private var requestedTermination: RequestedTermination = .none
  private var hasCompleted = false
  private var hasStarted = false
  private let readerGroup = DispatchGroup()

  init(
    executableURL: URL,
    arguments: [String],
    directory: URL?,
    environment: [String: String]?,
    timeout: TimeInterval?
  ) {
    self.timeout = timeout
    process.executableURL = executableURL
    process.arguments = arguments
    process.currentDirectoryURL = directory
    process.environment = environment
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe
  }

  func run() async -> GitProcessResult {
    await withCheckedContinuation { continuation in
      storeContinuation(continuation)

      switch currentTerminationRequest() {
      case .cancelled:
        complete(with: cancellationResult())
        return

      case .timedOut(let timeout):
        complete(with: timeoutResult(after: timeout))
        return

      case .none:
        break
      }

      do {
        try process.run()
      } catch {
        complete(with: GitProcessResult.failure(stderr: error.localizedDescription))
        return
      }

      markStarted()
      startReadingOutput()
      scheduleTimeoutIfNeeded()
      terminateIfRequested()
      waitForTermination()
    }
  }

  func cancel() {
    requestTermination(.cancelled)
  }

  private func storeContinuation(_ continuation: CheckedContinuation<GitProcessResult, Never>) {
    lock.lock()
    self.continuation = continuation
    lock.unlock()
  }

  private func currentTerminationRequest() -> RequestedTermination {
    lock.lock()
    let request = requestedTermination
    lock.unlock()
    return request
  }

  private func markStarted() {
    lock.lock()
    hasStarted = true
    lock.unlock()
  }

  private func startReadingOutput() {
    readerGroup.enter()
    DispatchQueue.global(qos: .utility).async { [self] in
      let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
      appendOutputData(data, isStdout: true)
      readerGroup.leave()
    }

    readerGroup.enter()
    DispatchQueue.global(qos: .utility).async { [self] in
      let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
      appendOutputData(data, isStdout: false)
      readerGroup.leave()
    }
  }

  private func appendOutputData(_ data: Data, isStdout: Bool) {
    lock.lock()
    if isStdout {
      stdoutData = data
    } else {
      stderrData = data
    }
    lock.unlock()
  }

  private func scheduleTimeoutIfNeeded() {
    guard let timeout else {
      return
    }

    let workItem = DispatchWorkItem { [weak self] in
      self?.requestTermination(.timedOut(timeout))
    }

    lock.lock()
    timeoutWorkItem = workItem
    lock.unlock()

    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: workItem)
  }

  private func requestTermination(_ termination: RequestedTermination) {
    var timeoutWorkItem: DispatchWorkItem?

    lock.lock()
    if hasCompleted {
      lock.unlock()
      return
    }

    if !hasStarted {
      if case .none = requestedTermination {
        requestedTermination = termination
      }

      timeoutWorkItem = self.timeoutWorkItem
      self.timeoutWorkItem = nil
      lock.unlock()

      timeoutWorkItem?.cancel()
      return
    }

    if !process.isRunning {
      lock.unlock()
      return
    }

    if case .none = requestedTermination {
      requestedTermination = termination
    }

    timeoutWorkItem = self.timeoutWorkItem
    self.timeoutWorkItem = nil
    lock.unlock()

    timeoutWorkItem?.cancel()

    process.terminate()
    scheduleForcedTerminationIfNeeded()
  }

  private func terminateIfRequested() {
    let request = currentTerminationRequest()

    switch request {
    case .none:
      return

    case .timedOut, .cancelled:
      requestTermination(request)
    }
  }

  private func scheduleForcedTerminationIfNeeded() {
    let pid = process.processIdentifier

    guard pid > 0 else {
      return
    }

    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) { [weak self] in
      guard let self else {
        return
      }

      self.lock.lock()
      let shouldKill = !self.hasCompleted && self.process.isRunning
      self.lock.unlock()

      guard shouldKill else {
        return
      }

      kill(pid, SIGKILL)
    }
  }

  private func waitForTermination() {
    DispatchQueue.global(qos: .userInitiated).async { [self] in
      process.waitUntilExit()
      readerGroup.wait()
      handleTermination()
    }
  }

  private func handleTermination() {
    lock.lock()
    let request = requestedTermination
    let stdout = GitProcessRunner.trimmedOutput(from: stdoutData)
    var stderr = GitProcessRunner.trimmedOutput(from: stderrData)
    let exitStatus = process.terminationStatus
    lock.unlock()

    let result: GitProcessResult
    switch request {
    case .none:
      result = GitProcessResult(
        stdout: stdout,
        stderr: stderr,
        terminationStatus: exitStatus
      )

    case .timedOut(let timeout):
      stderr = GitProcessRunner.appendMessage(
        "Process timed out after \(GitProcessRunner.timeoutDescription(timeout))",
        to: stderr
      )
      result = GitProcessResult(stdout: stdout, stderr: stderr, terminationStatus: 124)

    case .cancelled:
      stderr = GitProcessRunner.appendMessage("Process cancelled", to: stderr)
      result = GitProcessResult(stdout: stdout, stderr: stderr, terminationStatus: 130)
    }

    complete(with: result)
  }

  private func timeoutResult(after timeout: TimeInterval) -> GitProcessResult {
    GitProcessResult.failure(
      stderr: "Process timed out after \(GitProcessRunner.timeoutDescription(timeout))",
      terminationStatus: 124
    )
  }

  private func cancellationResult() -> GitProcessResult {
    GitProcessResult.failure(stderr: "Process cancelled", terminationStatus: 130)
  }

  private func complete(with result: GitProcessResult) {
    var continuation: CheckedContinuation<GitProcessResult, Never>?
    var timeoutWorkItem: DispatchWorkItem?

    lock.lock()
    if hasCompleted {
      lock.unlock()
      return
    }

    hasCompleted = true
    continuation = self.continuation
    self.continuation = nil
    timeoutWorkItem = self.timeoutWorkItem
    self.timeoutWorkItem = nil
    lock.unlock()

    timeoutWorkItem?.cancel()
    continuation?.resume(returning: result)
  }
}
