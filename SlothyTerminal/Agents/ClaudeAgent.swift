import SwiftUI

/// Claude AI agent implementation.
struct ClaudeAgent: AIAgent {
  let type: AgentType = .claude

  let accentColor = Color(red: 0.85, green: 0.47, blue: 0.34)
  let iconName = "brain.head.profile"
  let displayName = "Claude"
  let contextWindowLimit = 200_000

  /// Resolves the Claude CLI executable path, preferring native Mach-O
  /// binaries over Node.js script wrappers.
  var command: String {
    if let envPath = ProcessInfo.processInfo.environment["CLAUDE_PATH"],
       FileManager.default.isExecutableFile(atPath: envPath)
    {
      return envPath
    }

    if let resolved = resolveClaudePath() {
      return resolved
    }

    return "claude"
  }

  var defaultArgs: [String] {
    []
  }

  var environmentVariables: [String: String] {
    var env: [String: String] = [:]

    if let apiKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] {
      env["ANTHROPIC_API_KEY"] = apiKey
    }

    env["TERM"] = "xterm-256color"
    env["COLORTERM"] = "truecolor"

    return env
  }

  func parseStats(from output: String) -> UsageUpdate? {
    let parser = StatsParser.shared
    return parser.parseClaudeOutput(output)
  }

  func isAvailable() -> Bool {
    /// Check if CLAUDE_PATH is set and valid.
    if let envPath = ProcessInfo.processInfo.environment["CLAUDE_PATH"] {
      return FileManager.default.isExecutableFile(atPath: envPath)
    }

    /// Check common installation paths, preferring native installs.
    let commonPaths = [
      "\(NSHomeDirectory())/.local/bin/claude",
      "\(NSHomeDirectory())/.claude/local/claude",
      "\(NSHomeDirectory())/bin/claude",
      "/usr/local/bin/claude",
      "/opt/homebrew/bin/claude",
    ]

    for path in commonPaths {
      if FileManager.default.isExecutableFile(atPath: path) {
        return true
      }
    }

    return false
  }

  // MARK: - Private

  /// Common search paths ordered to prefer native installations.
  private static let searchPaths = [
    "\(NSHomeDirectory())/.local/bin/claude",
    "\(NSHomeDirectory())/.claude/local/claude",
    "\(NSHomeDirectory())/bin/claude",
    "/usr/local/bin/claude",
    "/opt/homebrew/bin/claude",
  ]

  /// Resolves the best Claude CLI path, preferring Mach-O binaries.
  private func resolveClaudePath() -> String? {
    /// First pass: prefer native Mach-O executables.
    for path in Self.searchPaths {
      if FileManager.default.isExecutableFile(atPath: path),
         isBinaryExecutable(atPath: path)
      {
        return path
      }
    }

    /// Second pass: any executable.
    for path in Self.searchPaths {
      if FileManager.default.isExecutableFile(atPath: path) {
        return path
      }
    }

    return nil
  }

  /// Checks whether a file is a Mach-O binary (not a script).
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
