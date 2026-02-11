import Foundation

/// Service for querying Git repository information.
final class GitService {
  /// Shared singleton instance.
  static let shared = GitService()

  private init() {}

  /// Returns the current Git branch name for the given directory.
  /// - Parameter directory: The directory to check.
  /// - Returns: The branch name, or nil if not a Git repository.
  func getCurrentBranch(in directory: URL) async -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["rev-parse", "--abbrev-ref", "HEAD"]
    process.currentDirectoryURL = directory

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice

    do {
      try process.run()
      process.waitUntilExit()

      guard process.terminationStatus == 0 else {
        return nil
      }

      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      let output = String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines)

      guard let branch = output, !branch.isEmpty else {
        return nil
      }

      return branch
    } catch {
      return nil
    }
  }

  /// Returns the list of modified/untracked files in the given directory.
  /// - Parameter directory: The directory to check.
  /// - Returns: An array of modified files, or empty if not a git repo or on error.
  func getModifiedFiles(in directory: URL) async -> [GitModifiedFile] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["status", "--porcelain"]
    process.currentDirectoryURL = directory

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice

    do {
      try process.run()
      process.waitUntilExit()

      guard process.terminationStatus == 0 else {
        return []
      }

      let data = pipe.fileHandleForReading.readDataToEndOfFile()

      guard let output = String(data: data, encoding: .utf8) else {
        return []
      }

      return parsePortcelainOutput(output)
    } catch {
      return []
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
