import Foundation

/// Executes a bash command and returns stdout/stderr.
///
/// Supports configurable timeout and captures the working directory
/// from the tool context.
struct BashTool: AgentTool {
  let id = "bash"

  let toolDescription = """
    Execute a bash command and return stdout/stderr. \
    The working directory persists between calls.
    """

  let parameters = ToolParameterSchema(
    type: "object",
    properties: [
      "command": .init(
        type: "string",
        description: "The bash command to execute",
        enumValues: nil
      ),
      "timeout": .init(
        type: "integer",
        description: "Timeout in milliseconds (default 120000, max 600000)",
        enumValues: nil
      ),
    ],
    required: ["command"]
  )

  /// Default timeout in seconds.
  private let defaultTimeout: TimeInterval = 120

  /// Maximum allowed timeout in seconds.
  private let maxTimeout: TimeInterval = 600

  func execute(
    arguments: [String: JSONValue],
    context: ToolContext
  ) async throws -> ToolResult {
    guard case .string(let command) = arguments["command"] else {
      return ToolResult(output: "Error: command is required", isError: true)
    }

    var timeout = defaultTimeout
    if case .number(let ms) = arguments["timeout"] {
      timeout = min(ms / 1000, maxTimeout)
    }

    let process = Process()
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()

    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = ["-c", command]
    process.currentDirectoryURL = context.workingDirectory
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    do {
      try process.run()
    } catch {
      return ToolResult(
        output: "Error: Failed to launch process: \(error.localizedDescription)",
        isError: true
      )
    }

    /// Read pipes concurrently to prevent deadlock when output fills
    /// the pipe buffer (waitUntilExit would block forever otherwise).
    var outData = Data()
    var errData = Data()
    let outHandle = stdoutPipe.fileHandleForReading
    let errHandle = stderrPipe.fileHandleForReading

    let readGroup = DispatchGroup()
    readGroup.enter()
    DispatchQueue.global().async {
      outData = outHandle.readDataToEndOfFile()
      readGroup.leave()
    }
    readGroup.enter()
    DispatchQueue.global().async {
      errData = errHandle.readDataToEndOfFile()
      readGroup.leave()
    }

    let deadline = DispatchTime.now() + timeout
    let waitGroup = DispatchGroup()
    waitGroup.enter()
    DispatchQueue.global().async {
      process.waitUntilExit()
      waitGroup.leave()
    }

    if waitGroup.wait(timeout: deadline) == .timedOut {
      process.terminate()
      readGroup.wait()
      return ToolResult(
        output: "Error: Command timed out after \(Int(timeout))s",
        isError: true
      )
    }

    readGroup.wait()
    let outStr = String(data: outData, encoding: .utf8) ?? ""
    let errStr = String(data: errData, encoding: .utf8) ?? ""

    let exitCode = process.terminationStatus

    if exitCode == 0 {
      return ToolResult(output: outStr)
    }

    let combined = """
      Exit code: \(exitCode)
      stdout:
      \(outStr)
      stderr:
      \(errStr)
      """

    return ToolResult(output: combined, isError: true)
  }
}
