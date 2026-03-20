import Foundation
import os

/// Shared service for invoking the OpenCode CLI for model discovery.
enum OpenCodeCLIService {
  private static let modelsTimeout: TimeInterval = 15

  /// Runs `opencode models` and parses the output into model selections.
  static func loadModels(timeout: TimeInterval = modelsTimeout) async -> [ChatModelSelection] {
    let result = await GitProcessRunner.runProcessResult(
      executableURL: URL(fileURLWithPath: "/usr/bin/env"),
      arguments: ["opencode", "models"],
      in: nil,
      environment: makeEnvironment(),
      timeout: timeout
    )

    guard result.isSuccess else {
      guard !result.wasCancelled else {
        return []
      }

      let errorText = result.stderr.isEmpty ? "unknown error" : String(result.stderr.prefix(200))
      Logger.app.warning("OpenCode model list failed: \(errorText)")
      return []
    }

    return parseModels(from: result.stdout)
  }

  static func parseModels(from output: String) -> [ChatModelSelection] {
    var seen = Set<String>()
    var models: [ChatModelSelection] = []

    for line in output.split(whereSeparator: \.isNewline) {
      let value = line.trimmingCharacters(in: .whitespacesAndNewlines)

      guard !value.isEmpty else {
        continue
      }

      let parts = value.split(separator: "/", maxSplits: 1).map(String.init)

      guard parts.count == 2 else {
        continue
      }

      let providerID = parts[0]
      let modelID = parts[1]

      guard !providerID.isEmpty, !modelID.isEmpty else {
        continue
      }

      let key = "\(providerID)/\(modelID)"

      guard !seen.contains(key) else {
        continue
      }

      seen.insert(key)

      models.append(ChatModelSelection(
        providerID: providerID,
        modelID: modelID,
        displayName: key
      ))
    }

    return models.sorted { $0.displayName < $1.displayName }
  }

  private static func makeEnvironment() -> [String: String] {
    var env = ProcessInfo.processInfo.environment
    let extraPaths = [
      "/opt/homebrew/bin",
      "/usr/local/bin",
      "\(NSHomeDirectory())/.local/bin",
    ]
    let existingPath = env["PATH"] ?? "/usr/bin:/bin"
    env["PATH"] = (extraPaths + [existingPath]).joined(separator: ":")
    return env
  }
}
