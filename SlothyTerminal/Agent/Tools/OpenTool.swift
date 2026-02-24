import Foundation

/// Opens files, applications, directories, or URLs on macOS.
///
/// Wraps the macOS `open` command with structured parameters,
/// giving the LLM explicit guidance on how to launch apps,
/// open projects in IDEs, and navigate to URLs.
struct OpenTool: AgentTool {
  let id = "open"

  let toolDescription = """
    Open a file, directory, application, or URL on macOS. \
    Can open a file in its default app, launch a specific application, \
    open a project directory in an IDE, or open a URL in the default browser. \
    Examples: open a .xcodeproj in Xcode, open a URL in Arc, \
    open a directory in Finder, launch an app by name.
    """

  let parameters = ToolParameterSchema(
    type: "object",
    properties: [
      "target": .init(
        type: "string",
        description: """
          The file path, directory path, or URL to open. \
          Use absolute paths for files and directories.
          """,
        enumValues: nil
      ),
      "application": .init(
        type: "string",
        description: """
          Application name to open the target with \
          (e.g., "Xcode", "Visual Studio Code", "Cursor", "Arc"). \
          If omitted, the default app for the file type is used.
          """,
        enumValues: nil
      ),
      "new_instance": .init(
        type: "boolean",
        description: "Open a new instance of the application even if one is running",
        enumValues: nil
      ),
      "background": .init(
        type: "boolean",
        description: "Open in background without bringing the app to the foreground",
        enumValues: nil
      ),
      "args": .init(
        type: "string",
        description: """
          Additional arguments to pass to the application after --, \
          space-separated (e.g., "--goto file.swift:42")
          """,
        enumValues: nil
      ),
    ],
    required: ["target"]
  )

  func execute(
    arguments: [String: JSONValue],
    context: ToolContext
  ) async throws -> ToolResult {
    guard case .string(let target) = arguments["target"] else {
      return ToolResult(output: "Error: target is required", isError: true)
    }

    var args: [String] = []

    /// Application flag.
    if case .string(let app) = arguments["application"] {
      args.append(contentsOf: ["-a", app])
    }

    /// New instance flag.
    if case .bool(true) = arguments["new_instance"] {
      args.append("-n")
    }

    /// Background flag.
    if case .bool(true) = arguments["background"] {
      args.append("-g")
    }

    /// The target (file/dir/URL).
    args.append(target)

    /// Extra arguments passed to the application after --.
    if case .string(let extraArgs) = arguments["args"] {
      args.append("--")
      args.append(contentsOf: extraArgs.components(separatedBy: " "))
    }

    let process = Process()
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()

    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = args
    process.currentDirectoryURL = context.workingDirectory
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    do {
      try process.run()
    } catch {
      return ToolResult(
        output: "Error: Failed to launch open: \(error.localizedDescription)",
        isError: true
      )
    }

    process.waitUntilExit()

    let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
    let outStr = String(data: outData, encoding: .utf8) ?? ""
    let errStr = String(data: errData, encoding: .utf8) ?? ""

    if process.terminationStatus == 0 {
      let description = describeAction(target: target, app: arguments["application"])
      return ToolResult(output: description + (outStr.isEmpty ? "" : "\n" + outStr))
    }

    return ToolResult(
      output: "Error: open failed (exit \(process.terminationStatus))\n\(errStr)",
      isError: true
    )
  }

  // MARK: - Private

  /// Produces a human-readable summary of what was opened.
  private func describeAction(target: String, app: JSONValue?) -> String {
    let appName: String?
    if case .string(let name) = app {
      appName = name
    } else {
      appName = nil
    }

    if let appName {
      return "Opened \(target) in \(appName)"
    }

    if target.hasPrefix("http://") || target.hasPrefix("https://") {
      return "Opened URL: \(target)"
    }

    return "Opened \(target)"
  }
}
