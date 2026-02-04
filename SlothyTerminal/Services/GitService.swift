import Foundation

/// Service for querying Git repository information.
final class GitService {
  /// Shared singleton instance.
  static let shared = GitService()

  private init() {}

  /// Returns the current Git branch name for the given directory.
  /// - Parameter directory: The directory to check.
  /// - Returns: The branch name, or nil if not a Git repository.
  func getCurrentBranch(in directory: URL) -> String? {
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
}
