import Foundation

/// Assembles the system prompt from agent definition, tool descriptions,
/// macOS system context, project detection, and user profile.
///
/// The system prompt is built in sections:
/// 1. Identity and platform context
/// 2. Agent's custom system prompt (if any)
/// 3. macOS capabilities guide
/// 4. Working directory and project context
/// 5. User profile (preferred apps, custom instructions)
/// 6. Tool descriptions (summary of available tools)
/// 7. Agent mode constraints
enum SystemPromptBuilder {

  /// Builds a complete system prompt for the given agent and context.
  ///
  /// - Parameters:
  ///   - agent: The agent definition providing base prompt and mode.
  ///   - tools: The available tools (for generating descriptions).
  ///   - workingDirectory: The project directory path.
  ///   - profile: Optional user profile for personalized context.
  /// - Returns: The assembled system prompt string.
  static func build(
    agent: AgentDefinition,
    tools: [AgentTool],
    workingDirectory: URL,
    profile: AgentProfile? = nil
  ) -> String {
    var sections: [String] = []

    /// 1. Identity and platform.
    sections.append(buildIdentity())

    /// 2. Agent's custom system prompt.
    if let custom = agent.systemPrompt {
      sections.append(custom)
    }

    /// 3. macOS capabilities.
    sections.append(buildMacOSGuide())

    /// 4. Working directory and project context.
    sections.append(buildProjectContext(workingDirectory: workingDirectory))

    /// 5. User profile.
    if let profile,
       let profileSection = buildProfileSection(profile)
    {
      sections.append(profileSection)
    }

    /// 6. Tool descriptions.
    if !tools.isEmpty {
      let toolList = tools.map { tool in
        "- \(tool.id): \(tool.toolDescription)"
      }.joined(separator: "\n")

      sections.append("Available tools:\n\(toolList)")
    }

    /// 7. Mode constraints.
    switch agent.mode {
    case .readOnly:
      sections.append(
        "You are in read-only mode. Do not modify any files or execute destructive commands."
      )

    case .subagent:
      sections.append(
        "You are running as a subagent. Complete the task and return a concise result."
      )

    case .primary:
      break
    }

    return sections.joined(separator: "\n\n")
  }

  // MARK: - Section builders

  /// Platform identity and core behavior.
  private static func buildIdentity() -> String {
    let osVersion = ProcessInfo.processInfo.operatingSystemVersionString

    return """
      You are a macOS coding assistant running natively on the user's machine. \
      You have full access to the local filesystem, installed applications, \
      and system tools. You can open apps, run commands, edit files, \
      browse the web, and automate workflows.

      Platform: macOS \(osVersion)
      Architecture: \(machineArchitecture())
      """
  }

  /// Guide for macOS-specific capabilities.
  private static func buildMacOSGuide() -> String {
    """
    # macOS System Capabilities

    You have dedicated tools for common macOS operations:

    **Opening apps and files** (use the `open` tool):
    - Open a project: `open` with target="/path/to/project.xcodeproj" application="Xcode"
    - Open a URL: `open` with target="https://example.com"
    - Open in a specific app: `open` with target="/path/to/file" application="Visual Studio Code"
    - Open Finder at a path: `open` with target="/path/to/directory"

    **Automating applications** (use the `applescript` tool):
    - Query app state: `tell application "Safari" to get URL of current tab of window 1`
    - Control windows: `tell application "Finder" to close every window`
    - Get running apps: `tell application "System Events" to get name of every process whose background only is false`
    - Interact with apps: `tell application "Terminal" to do script "echo hello"`

    **System queries** (use the `system_info` tool):
    - List running apps: category="running_apps"
    - Check installed tools: category="installed_tools"
    - System specs: category="system"
    - Disk usage: category="disk"

    **General commands** (use the `bash` tool):
    - Git operations, builds, package management, file manipulation
    - Any shell command the user's account can execute

    When asked to "open" something, prefer the `open` tool over bash.
    When asked about system state, prefer `system_info` over bash.
    When asked to automate an app, prefer `applescript` over bash.
    """
  }

  /// Detects project type from the working directory and provides context.
  private static func buildProjectContext(workingDirectory: URL) -> String {
    var lines: [String] = [
      "Working directory: \(workingDirectory.path)"
    ]

    let fm = FileManager.default
    let path = workingDirectory.path

    /// Detect project type.
    var projectTypes: [String] = []

    if fm.fileExists(atPath: "\(path)/Package.swift") {
      projectTypes.append("Swift Package (Package.swift)")
    }

    let xcodeprojs = (try? fm.contentsOfDirectory(atPath: path))?
      .filter { $0.hasSuffix(".xcodeproj") } ?? []
    if !xcodeprojs.isEmpty {
      projectTypes.append("Xcode Project (\(xcodeprojs.first!))")
    }

    let xcworkspaces = (try? fm.contentsOfDirectory(atPath: path))?
      .filter { $0.hasSuffix(".xcworkspace") } ?? []
    if !xcworkspaces.isEmpty {
      projectTypes.append("Xcode Workspace (\(xcworkspaces.first!))")
    }

    if fm.fileExists(atPath: "\(path)/package.json") {
      projectTypes.append("Node.js (package.json)")
    }

    if fm.fileExists(atPath: "\(path)/Cargo.toml") {
      projectTypes.append("Rust (Cargo.toml)")
    }

    if fm.fileExists(atPath: "\(path)/go.mod") {
      projectTypes.append("Go (go.mod)")
    }

    if fm.fileExists(atPath: "\(path)/Podfile") {
      projectTypes.append("CocoaPods (Podfile)")
    }

    if fm.fileExists(atPath: "\(path)/Gemfile") {
      projectTypes.append("Ruby (Gemfile)")
    }

    if fm.fileExists(atPath: "\(path)/requirements.txt") ||
       fm.fileExists(atPath: "\(path)/pyproject.toml")
    {
      projectTypes.append("Python")
    }

    if fm.fileExists(atPath: "\(path)/docker-compose.yml") ||
       fm.fileExists(atPath: "\(path)/Dockerfile")
    {
      projectTypes.append("Docker")
    }

    if !projectTypes.isEmpty {
      lines.append("Project type: \(projectTypes.joined(separator: ", "))")
    }

    /// Check for git repo.
    if fm.fileExists(atPath: "\(path)/.git") {
      lines.append("Git repository: yes")
    }

    return lines.joined(separator: "\n")
  }

  /// Builds a section from the user's agent profile.
  private static func buildProfileSection(_ profile: AgentProfile) -> String? {
    var lines: [String] = []

    if let ide = profile.preferredIDE {
      lines.append("Preferred IDE: \(ide) — use this when opening projects or code files.")
    }

    if !profile.projectRoots.isEmpty {
      let roots = profile.projectRoots.map { "  - \($0)" }.joined(separator: "\n")
      lines.append("Known project directories:\n\(roots)")
    }

    if !profile.preferredApps.isEmpty {
      let apps = profile.preferredApps.map { "  - \($0.key): \($0.value)" }
        .joined(separator: "\n")
      lines.append("Preferred applications:\n\(apps)")
    }

    if let instructions = profile.customInstructions,
       !instructions.isEmpty
    {
      lines.append("# User Instructions\n\(instructions)")
    }

    guard !lines.isEmpty else {
      return nil
    }

    return "# User Profile\n\n" + lines.joined(separator: "\n\n")
  }

  // MARK: - Helpers

  /// Returns the machine architecture string.
  private static func machineArchitecture() -> String {
    var sysinfo = utsname()
    uname(&sysinfo)
    return withUnsafePointer(to: &sysinfo.machine) {
      $0.withMemoryRebound(to: CChar.self, capacity: 1) {
        String(cString: $0)
      }
    }
  }
}
