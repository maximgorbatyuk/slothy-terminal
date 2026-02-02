import SwiftUI

/// GLM (ChatGLM) AI agent implementation.
struct GLMAgent: AIAgent {
  let type: AgentType = .glm

  /// GLM's accent color (blue).
  let accentColor = Color(red: 0.29, green: 0.62, blue: 1.0)

  let iconName = "cpu"
  let displayName = "GLM"

  /// GLM's context window (varies by model, using common default).
  let contextWindowLimit = 128_000

  /// Path to the GLM CLI executable.
  var command: String {
    /// Check environment variable first, then common paths.
    if let envPath = ProcessInfo.processInfo.environment["GLM_PATH"],
       FileManager.default.isExecutableFile(atPath: envPath)
    {
      return envPath
    }

    /// Check common installation paths.
    let commonPaths = [
      "/usr/local/bin/glm",
      "/opt/homebrew/bin/glm",
      "\(NSHomeDirectory())/.local/bin/glm",
      "\(NSHomeDirectory())/bin/glm",
      "/usr/local/bin/chatglm",
      "/opt/homebrew/bin/chatglm"
    ]

    for path in commonPaths {
      if FileManager.default.isExecutableFile(atPath: path) {
        return path
      }
    }

    /// Default path.
    return "/usr/local/bin/glm"
  }

  /// Default arguments for GLM CLI.
  var defaultArgs: [String] {
    []
  }

  /// Environment variables for GLM.
  var environmentVariables: [String: String] {
    var env: [String: String] = [:]

    /// Pass through API key if set.
    if let apiKey = ProcessInfo.processInfo.environment["GLM_API_KEY"] {
      env["GLM_API_KEY"] = apiKey
    }

    /// Also check for ZHIPU API key (GLM provider).
    if let apiKey = ProcessInfo.processInfo.environment["ZHIPU_API_KEY"] {
      env["ZHIPU_API_KEY"] = apiKey
    }

    /// Enable color output.
    env["TERM"] = "xterm-256color"
    env["COLORTERM"] = "truecolor"

    return env
  }

  /// Parses GLM CLI output for usage statistics.
  func parseStats(from output: String) -> UsageUpdate? {
    let parser = StatsParser.shared
    return parser.parseGLMOutput(output)
  }

  /// Formats a startup message for GLM sessions.
  func formatStartupMessage() -> String? {
    nil
  }

  /// Checks if GLM CLI is installed and available.
  func isAvailable() -> Bool {
    FileManager.default.isExecutableFile(atPath: command)
  }
}

// MARK: - GLM-specific Parsing Helpers

extension GLMAgent {
  /// Detects if the output indicates a new message was sent.
  func detectNewMessage(in output: String) -> Bool {
    let messageIndicators = [
      "User:",
      "Assistant:",
      ">>> ",
      "Q:",
      "A:"
    ]

    return messageIndicators.contains { output.contains($0) }
  }

  /// Extracts the model name from GLM output if present.
  func extractModelName(from output: String) -> String? {
    /// Look for model indicators like "glm-4" or "chatglm3".
    let patterns = [
      "glm-[0-9]+",
      "chatglm[0-9]+"
    ]

    for pattern in patterns {
      guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
        continue
      }

      let range = NSRange(output.startIndex..., in: output)
      if let match = regex.firstMatch(in: output, options: [], range: range),
         let matchRange = Range(match.range, in: output)
      {
        return String(output[matchRange])
      }
    }

    return nil
  }
}
