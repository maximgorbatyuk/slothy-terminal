import Foundation

/// Queries macOS system information without requiring the agent to
/// compose shell commands from scratch.
///
/// Supports several query categories: running apps, installed tools,
/// system specs, disk usage, and network state.
struct SystemInfoTool: AgentTool {
  let id = "system_info"

  let toolDescription = """
    Query macOS system information. \
    Returns structured info about running applications, \
    installed developer tools, system specs, disk usage, or network state. \
    Use instead of composing shell commands for common system queries.
    """

  let parameters = ToolParameterSchema(
    type: "object",
    properties: [
      "category": .init(
        type: "string",
        description: """
          What to query: \
          "running_apps" — list currently running applications, \
          "installed_tools" — check for common developer tools (git, node, python, etc.), \
          "system" — OS version, architecture, memory, \
          "disk" — disk usage for the boot volume, \
          "network" — active network interfaces and IPs, \
          "env" — key environment variables (PATH, HOME, SHELL), \
          "displays" — connected displays and resolutions
          """,
        enumValues: [
          "running_apps",
          "installed_tools",
          "system",
          "disk",
          "network",
          "env",
          "displays",
        ]
      ),
    ],
    required: ["category"]
  )

  func execute(
    arguments: [String: JSONValue],
    context: ToolContext
  ) async throws -> ToolResult {
    guard case .string(let category) = arguments["category"] else {
      return ToolResult(output: "Error: category is required", isError: true)
    }

    switch category {
    case "running_apps":
      return await queryRunningApps()

    case "installed_tools":
      return await queryInstalledTools()

    case "system":
      return await querySystemSpecs()

    case "disk":
      return await runCommand("/bin/df", arguments: ["-h", "/"])

    case "network":
      return await runCommand("/sbin/ifconfig", arguments: ["-a"])

    case "env":
      return queryEnvironment()

    case "displays":
      return await runCommand(
        "/usr/sbin/system_profiler",
        arguments: ["SPDisplaysDataType", "-detailLevel", "mini"]
      )

    default:
      return ToolResult(
        output: "Error: Unknown category '\(category)'. Use one of: running_apps, installed_tools, system, disk, network, env, displays",
        isError: true
      )
    }
  }

  // MARK: - Private

  /// Lists currently running applications via NSWorkspace-compatible approach.
  private func queryRunningApps() async -> ToolResult {
    await runCommand(
      "/usr/bin/osascript",
      arguments: [
        "-e",
        """
        tell application "System Events"
          set appList to name of every application process whose background only is false
        end tell
        return appList
        """,
      ]
    )
  }

  /// Checks common developer tools for availability.
  private func queryInstalledTools() async -> ToolResult {
    let tools = [
      "git", "swift", "xcodebuild", "node", "npm", "python3",
      "ruby", "cargo", "go", "java", "docker", "brew",
      "pod", "flutter", "code", "cursor",
    ]

    var results: [String] = []
    for tool in tools {
      let path = await whichTool(tool)
      if let path {
        results.append("\(tool): \(path)")
      } else {
        results.append("\(tool): not found")
      }
    }

    return ToolResult(output: results.joined(separator: "\n"))
  }

  /// Queries basic system specs.
  private func querySystemSpecs() async -> ToolResult {
    let info = ProcessInfo.processInfo
    var lines: [String] = []

    lines.append("OS: macOS \(info.operatingSystemVersionString)")
    lines.append("Architecture: \(machineArchitecture())")
    lines.append("Physical Memory: \(info.physicalMemory / (1024 * 1024 * 1024)) GB")
    lines.append("Processor Count: \(info.processorCount)")
    lines.append("Active Processor Count: \(info.activeProcessorCount)")
    lines.append("Host Name: \(info.hostName)")
    lines.append("User: \(info.userName)")

    return ToolResult(output: lines.joined(separator: "\n"))
  }

  /// Returns key environment variables.
  private func queryEnvironment() -> ToolResult {
    let keys = [
      "PATH", "HOME", "SHELL", "USER", "LANG",
      "TERM", "EDITOR", "VISUAL", "XPC_SERVICE_NAME",
    ]

    let env = ProcessInfo.processInfo.environment
    var lines: [String] = []

    for key in keys {
      let value = env[key] ?? "(not set)"
      lines.append("\(key)=\(value)")
    }

    return ToolResult(output: lines.joined(separator: "\n"))
  }

  /// Runs a command and returns its output.
  private func runCommand(
    _ executable: String,
    arguments args: [String] = []
  ) async -> ToolResult {
    let process = Process()
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()

    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = args
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    do {
      try process.run()
    } catch {
      return ToolResult(
        output: "Error: Failed to run \(executable): \(error.localizedDescription)",
        isError: true
      )
    }

    process.waitUntilExit()

    let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
    let outStr = String(data: outData, encoding: .utf8) ?? ""
    let errStr = String(data: errData, encoding: .utf8) ?? ""

    if process.terminationStatus == 0 {
      return ToolResult(output: outStr.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    return ToolResult(
      output: "Error: \(executable) failed (exit \(process.terminationStatus))\n\(errStr)",
      isError: true
    )
  }

  /// Checks if a tool is available on PATH.
  private func whichTool(_ tool: String) async -> String? {
    let process = Process()
    let pipe = Pipe()

    process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
    process.arguments = [tool]
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice

    do {
      try process.run()
    } catch {
      return nil
    }

    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
      return nil
    }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Returns the machine architecture string.
  private func machineArchitecture() -> String {
    var sysinfo = utsname()
    uname(&sysinfo)
    return withUnsafePointer(to: &sysinfo.machine) {
      $0.withMemoryRebound(to: CChar.self, capacity: 1) {
        String(cString: $0)
      }
    }
  }
}
