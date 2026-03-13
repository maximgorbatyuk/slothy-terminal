import Foundation

struct GitProcessResult {
  let stdout: String
  let stderr: String
  let terminationStatus: Int32

  var isSuccess: Bool {
    terminationStatus == 0
  }

  static func failure(
    stderr: String,
    terminationStatus: Int32 = 1
  ) -> GitProcessResult {
    GitProcessResult(
      stdout: "",
      stderr: stderr,
      terminationStatus: terminationStatus
    )
  }
}

/// Shared utility for running git commands off the main thread.
/// Used by `GitService` and `GitStatsService` to avoid duplicating process logic.
enum GitProcessRunner {
  /// Runs a git command and returns trimmed stdout, or nil on failure.
  /// Reads pipe data before waiting for exit to prevent deadlocks
  /// when output exceeds the pipe buffer size.
  static func run(_ arguments: [String], in directory: URL) async -> String? {
    let result = await runResult(arguments, in: directory)

    guard result.isSuccess, !result.stdout.isEmpty else {
      return nil
    }

    return result.stdout
  }

  /// Runs a git command and returns stdout, stderr, and exit status.
  static func runResult(_ arguments: [String], in directory: URL) async -> GitProcessResult {
    await withCheckedContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
          try process.run()
          let (stdoutData, stderrData) = readProcessOutput(
            stdoutPipe: stdoutPipe,
            stderrPipe: stderrPipe
          )
          process.waitUntilExit()

          continuation.resume(
            returning: GitProcessResult(
              stdout: trimmedOutput(from: stdoutData),
              stderr: trimmedOutput(from: stderrData),
              terminationStatus: process.terminationStatus
            )
          )
        } catch {
          continuation.resume(
            returning: GitProcessResult.failure(stderr: error.localizedDescription)
          )
        }
      }
    }
  }

  private static func readProcessOutput(
    stdoutPipe: Pipe,
    stderrPipe: Pipe
  ) -> (stdout: Data, stderr: Data) {
    let group = DispatchGroup()
    var stdoutData = Data()
    var stderrData = Data()

    group.enter()
    DispatchQueue.global(qos: .userInitiated).async {
      stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
      group.leave()
    }

    group.enter()
    DispatchQueue.global(qos: .userInitiated).async {
      stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
      group.leave()
    }

    group.wait()
    return (stdoutData, stderrData)
  }

  private static func trimmedOutput(from data: Data) -> String {
    String(data: data, encoding: .utf8)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  }
}
