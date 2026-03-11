import Foundation

/// Shared utility for running git commands off the main thread.
/// Used by `GitService` and `GitStatsService` to avoid duplicating process logic.
enum GitProcessRunner {
  /// Runs a git command and returns trimmed stdout, or nil on failure.
  /// Reads pipe data before waiting for exit to prevent deadlocks
  /// when output exceeds the pipe buffer size.
  static func run(_ arguments: [String], in directory: URL) async -> String? {
    await withCheckedContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
          try process.run()
          let data = pipe.fileHandleForReading.readDataToEndOfFile()
          process.waitUntilExit()

          guard process.terminationStatus == 0 else {
            continuation.resume(returning: nil)
            return
          }

          let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

          guard let result = output, !result.isEmpty else {
            continuation.resume(returning: nil)
            return
          }

          continuation.resume(returning: result)
        } catch {
          continuation.resume(returning: nil)
        }
      }
    }
  }
}
