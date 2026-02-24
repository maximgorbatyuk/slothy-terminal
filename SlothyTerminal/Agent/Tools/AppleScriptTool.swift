import Foundation

/// Executes AppleScript or JavaScript for Automation (JXA) via `osascript`.
///
/// Enables the agent to interact with macOS applications through
/// their scripting interfaces — controlling app windows, querying
/// app state, automating workflows, and more.
struct AppleScriptTool: AgentTool {
  let id = "applescript"

  let toolDescription = """
    Execute AppleScript or JavaScript for Automation (JXA) on macOS. \
    Use this to control applications, get window positions, \
    manipulate Finder, automate workflows, or query app state. \
    Supports both AppleScript and JXA (via the language parameter).
    """

  let parameters = ToolParameterSchema(
    type: "object",
    properties: [
      "script": .init(
        type: "string",
        description: """
          The AppleScript or JXA source code to execute. \
          For AppleScript: 'tell application "Finder" to get name of every window'. \
          For JXA: 'Application("Finder").windows().name()'.
          """,
        enumValues: nil
      ),
      "language": .init(
        type: "string",
        description: "Scripting language: \"AppleScript\" (default) or \"JavaScript\"",
        enumValues: ["AppleScript", "JavaScript"]
      ),
    ],
    required: ["script"]
  )

  /// Maximum script execution time in seconds.
  private let timeout: TimeInterval = 30

  func execute(
    arguments: [String: JSONValue],
    context: ToolContext
  ) async throws -> ToolResult {
    guard case .string(let script) = arguments["script"] else {
      return ToolResult(output: "Error: script is required", isError: true)
    }

    var args: [String] = []

    /// Set language if specified.
    if case .string(let lang) = arguments["language"],
       lang == "JavaScript"
    {
      args.append(contentsOf: ["-l", "JavaScript"])
    }

    /// Pass script via -e flag.
    args.append(contentsOf: ["-e", script])

    let process = Process()
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()

    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = args
    process.currentDirectoryURL = context.workingDirectory
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    do {
      try process.run()
    } catch {
      return ToolResult(
        output: "Error: Failed to launch osascript: \(error.localizedDescription)",
        isError: true
      )
    }

    /// Read pipes concurrently to prevent deadlock.
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

    /// Wait with timeout.
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
        output: "Error: Script timed out after \(Int(timeout))s",
        isError: true
      )
    }

    readGroup.wait()
    let outStr = String(data: outData, encoding: .utf8) ?? ""
    let errStr = String(data: errData, encoding: .utf8) ?? ""

    if process.terminationStatus == 0 {
      let result = outStr.trimmingCharacters(in: .whitespacesAndNewlines)
      return ToolResult(output: result.isEmpty ? "(no output)" : result)
    }

    return ToolResult(
      output: "Error: osascript failed (exit \(process.terminationStatus))\n\(errStr)",
      isError: true
    )
  }
}
