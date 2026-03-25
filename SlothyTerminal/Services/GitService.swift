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

  // MARK: - Private

  /// Runs a git command off the cooperative thread pool and returns trimmed stdout.
  private func runGit(_ arguments: [String], in directory: URL) async -> String? {
    await GitProcessRunner.run(arguments, in: directory)
  }

}
