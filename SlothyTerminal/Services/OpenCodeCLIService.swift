import Foundation
import os

/// Shared service for invoking the OpenCode CLI for model discovery.
enum OpenCodeCLIService {

  /// Runs `opencode models` and parses the output into model selections.
  /// Must be called off the main thread (blocking I/O).
  static func loadModels() -> [ChatModelSelection] {
    let process = Process()
    let stdout = Pipe()
    let stderr = Pipe()

    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["opencode", "models"]
    process.standardOutput = stdout
    process.standardError = stderr

    var env = ProcessInfo.processInfo.environment
    let extraPaths = [
      "/opt/homebrew/bin",
      "/usr/local/bin",
      "\(NSHomeDirectory())/.local/bin",
    ]
    let existingPath = env["PATH"] ?? "/usr/bin:/bin"
    env["PATH"] = (extraPaths + [existingPath]).joined(separator: ":")
    process.environment = env

    do {
      try process.run()
    } catch {
      Logger.app.warning("OpenCode model list failed to start: \(error.localizedDescription)")
      return []
    }

    let timeoutSeconds: Double = 15
    let deadline = DispatchTime.now() + timeoutSeconds
    let done = DispatchSemaphore(value: 0)

    DispatchQueue.global().async {
      process.waitUntilExit()
      done.signal()
    }

    if done.wait(timeout: deadline) == .timedOut {
      process.terminate()
      Logger.app.warning("OpenCode model list timed out after \(timeoutSeconds)s")
      return []
    }

    guard process.terminationStatus == 0 else {
      let errorText = String(
        data: stderr.fileHandleForReading.readDataToEndOfFile(),
        encoding: .utf8
      ) ?? ""
      Logger.app.warning("OpenCode model list failed: \(errorText.prefix(200))")
      return []
    }

    let outputData = stdout.fileHandleForReading.readDataToEndOfFile()

    guard let output = String(data: outputData, encoding: .utf8) else {
      return []
    }

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
}
