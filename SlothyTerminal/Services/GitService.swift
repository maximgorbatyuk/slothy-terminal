import Foundation

/// Service for querying Git repository information.
final class GitService {
  /// Shared singleton instance.
  static let shared = GitService()

  private init() {}

  /// Returns the Git repository root for the given directory.
  /// - Parameter directory: The directory to check.
  /// - Returns: The repository root URL, or nil if not a Git repository.
  func getRepositoryRoot(for directory: URL) async -> URL? {
    guard let path = await runGit(["rev-parse", "--show-toplevel"], in: directory) else {
      return nil
    }

    return URL(fileURLWithPath: path)
  }

  /// Returns the current Git branch name for the given directory.
  /// - Parameter directory: The directory to check.
  /// - Returns: The branch name, or nil if not a Git repository.
  func getCurrentBranch(in directory: URL) async -> String? {
    await runGit(["rev-parse", "--abbrev-ref", "HEAD"], in: directory)
  }

  /// Returns the list of modified/untracked files in the given directory.
  /// - Parameter directory: The directory to check.
  /// - Returns: An array of modified files, or empty if not a git repo or on error.
  func getModifiedFiles(in directory: URL) async -> [GitModifiedFile] {
    guard let output = await runGit(["status", "--porcelain"], in: directory) else {
      return []
    }

    return parsePortcelainOutput(output)
  }

  // MARK: - Private

  /// Runs a git command off the cooperative thread pool and returns trimmed stdout.
  private func runGit(_ arguments: [String], in directory: URL) async -> String? {
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
          process.waitUntilExit()

          guard process.terminationStatus == 0 else {
            continuation.resume(returning: nil)
            return
          }

          let data = pipe.fileHandleForReading.readDataToEndOfFile()
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

  /// Parses `git status --porcelain` output into `GitModifiedFile` values.
  private func parsePortcelainOutput(_ output: String) -> [GitModifiedFile] {
    var files: [GitModifiedFile] = []

    for line in output.components(separatedBy: "\n") {
      guard line.count >= 4 else {
        continue
      }

      let indexStatus = line[line.startIndex]
      let workTreeStatus = line[line.index(after: line.startIndex)]
      let path = String(line.dropFirst(3))

      /// Prefer working tree status; fall back to index status.
      let statusChar: Character
      if workTreeStatus != " " && workTreeStatus != "?" && workTreeStatus != "!" {
        statusChar = workTreeStatus
      } else {
        statusChar = indexStatus
      }

      guard let status = GitFileStatus(rawValue: String(statusChar)) else {
        continue
      }

      /// Handle renames: "R  old -> new" — use the new path.
      let filePath: String
      if status == .renamed, let arrowRange = path.range(of: " -> ") {
        filePath = String(path[arrowRange.upperBound...])
      } else {
        filePath = path
      }

      files.append(GitModifiedFile(path: filePath, status: status))
    }

    return files
  }
}
