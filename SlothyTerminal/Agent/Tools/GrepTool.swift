import Foundation

/// Content search tool that searches file contents for a regex pattern.
///
/// Uses `grep -rn` under the hood. Returns matching lines with
/// file paths and line numbers.
struct GrepTool: AgentTool {
  let id = "grep"

  let toolDescription = """
    Search file contents for a regex pattern. \
    Returns matching lines with file paths and line numbers.
    """

  let parameters = ToolParameterSchema(
    type: "object",
    properties: [
      "pattern": .init(
        type: "string",
        description: "Regular expression pattern to search for",
        enumValues: nil
      ),
      "path": .init(
        type: "string",
        description: "File or directory to search in (defaults to working directory)",
        enumValues: nil
      ),
      "glob": .init(
        type: "string",
        description: "File glob to filter (e.g., \"*.swift\", \"*.ts\")",
        enumValues: nil
      ),
    ],
    required: ["pattern"]
  )

  /// Maximum output size in characters.
  private let maxOutputSize = 30_000

  func execute(
    arguments: [String: JSONValue],
    context: ToolContext
  ) async throws -> ToolResult {
    guard case .string(let pattern) = arguments["pattern"] else {
      return ToolResult(output: "Error: pattern is required", isError: true)
    }

    let searchPath: String
    if case .string(let path) = arguments["path"] {
      searchPath = path
    } else {
      searchPath = context.workingDirectory.path
    }

    var grepArgs = ["-rn", "--color=never"]

    if case .string(let globPattern) = arguments["glob"] {
      grepArgs.append(contentsOf: ["--include", globPattern])
    }

    grepArgs.append(contentsOf: [pattern, searchPath])

    let process = Process()
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()

    process.executableURL = URL(fileURLWithPath: "/usr/bin/grep")
    process.arguments = grepArgs
    process.currentDirectoryURL = context.workingDirectory
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    do {
      try process.run()
    } catch {
      return ToolResult(
        output: "Error: Failed to launch grep: \(error.localizedDescription)",
        isError: true
      )
    }

    process.waitUntilExit()

    let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
    var output = String(data: outData, encoding: .utf8) ?? ""
    let errStr = String(data: errData, encoding: .utf8) ?? ""

    /// grep exit code 1 means no matches, which is not an error.
    if process.terminationStatus > 1 {
      return ToolResult(
        output: "Error: grep failed: \(errStr)",
        isError: true
      )
    }

    if output.isEmpty {
      return ToolResult(output: "No matches found for pattern: \(pattern)")
    }

    if output.count > maxOutputSize {
      output = String(output.prefix(maxOutputSize))
        + "\n... (output truncated)"
    }

    return ToolResult(output: output)
  }
}
