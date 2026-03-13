import Foundation

/// Service for parsing and mutating a repository working tree for the Make Commit UI.
final class GitWorkingTreeService {
  static let shared = GitWorkingTreeService()

  private init() {}

  func pushArguments(
    currentBranch: String,
    upstreamBranch: String?
  ) -> [String] {
    guard
      let upstreamBranch,
      !upstreamBranch.isEmpty
    else {
      return ["push", "--set-upstream", "origin", currentBranch]
    }

    return ["push"]
  }

  func getLastCommitMessage(in directory: URL) async -> String? {
    let repositoryRoot = await repositoryRoot(for: directory)
    let result = await GitProcessRunner.runResult(
      ["log", "-1", "--pretty=%B"],
      in: repositoryRoot
    )

    guard result.isSuccess, !result.stdout.isEmpty else {
      return nil
    }

    return result.stdout
  }

  func stageFile(path: String, in directory: URL) async -> GitProcessResult {
    await runMutation(["add", "--", path], in: directory)
  }

  func unstageFile(path: String, in directory: URL) async -> GitProcessResult {
    await runMutation(["restore", "--staged", "--", path], in: directory)
  }

  func discardTrackedChanges(path: String, in directory: URL) async -> GitProcessResult {
    await runMutation(["restore", "--", path], in: directory)
  }

  func discardStagedChanges(path: String, in directory: URL) async -> GitProcessResult {
    await runMutation(
      ["restore", "--staged", "--worktree", "--source=HEAD", "--", path],
      in: directory
    )
  }

  func push(in directory: URL) async -> GitProcessResult {
    let repositoryRoot = await repositoryRoot(for: directory)
    guard let currentBranch = await currentBranch(in: repositoryRoot) else {
      return .failure(stderr: "Unable to determine the current branch.")
    }

    let upstreamBranch = await currentUpstreamBranch(in: repositoryRoot)
    let arguments = pushArguments(
      currentBranch: currentBranch,
      upstreamBranch: upstreamBranch
    )

    return await GitProcessRunner.runResult(arguments, in: repositoryRoot)
  }

  func createAndSwitchBranch(
    named branchName: String,
    in directory: URL
  ) async -> GitProcessResult {
    await runMutation(["switch", "-c", branchName], in: directory)
  }

  func parseStatusOutput(
    _ output: String,
    scopePath: String? = nil
  ) -> GitWorkingTreeSnapshot {
    let normalizedScopePath = normalizeScopePath(scopePath)
    var visibleChanges: [GitScopedChange] = []
    var hasStagedChangesOutsideScope = false

    for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
      guard let change = parseStatusLine(String(line), scopePath: normalizedScopePath) else {
        continue
      }

      let isInScope = isPath(change.repoRelativePath, within: normalizedScopePath)

      if isInScope {
        visibleChanges.append(change)
      } else if change.hasStagedEntry {
        hasStagedChangesOutsideScope = true
      }
    }

    return GitWorkingTreeSnapshot(
      changes: visibleChanges,
      scopePath: normalizedScopePath,
      hasStagedChangesOutsideScope: hasStagedChangesOutsideScope
    )
  }

  private func parseStatusLine(
    _ line: String,
    scopePath: String?
  ) -> GitScopedChange? {
    guard line.count >= 4 else {
      return nil
    }

    let characters = Array(line)

    guard
      let indexStatus = GitStatusColumn(statusCharacter: characters[0]),
      let workTreeStatus = GitStatusColumn(statusCharacter: characters[1])
    else {
      return nil
    }

    let rawPath = String(characters.dropFirst(3))
    let repoRelativePath = normalizedStatusPath(from: rawPath)
    let displayPath = displayPath(for: repoRelativePath, scopePath: scopePath)

    return GitScopedChange(
      repoRelativePath: repoRelativePath,
      displayPath: displayPath,
      indexStatus: indexStatus,
      workTreeStatus: workTreeStatus
    )
  }

  private func normalizedStatusPath(from rawPath: String) -> String {
    guard let arrowRange = rawPath.range(of: " -> ") else {
      return rawPath
    }

    return String(rawPath[arrowRange.upperBound...])
  }

  private func normalizeScopePath(_ scopePath: String?) -> String? {
    guard let scopePath else {
      return nil
    }

    let trimmed = scopePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

    guard !trimmed.isEmpty, trimmed != "." else {
      return nil
    }

    return trimmed
  }

  private func isPath(_ path: String, within scopePath: String?) -> Bool {
    guard let scopePath else {
      return true
    }

    return path == scopePath || path.hasPrefix("\(scopePath)/")
  }

  private func displayPath(for path: String, scopePath: String?) -> String {
    guard let scopePath else {
      return path
    }

    let prefix = "\(scopePath)/"

    guard path.hasPrefix(prefix) else {
      return path
    }

    return String(path.dropFirst(prefix.count))
  }

  private func repositoryRoot(for directory: URL) async -> URL {
    guard let path = await GitProcessRunner.run(
      ["rev-parse", "--show-toplevel"],
      in: directory
    ) else {
      return directory
    }

    return URL(fileURLWithPath: path)
  }

  private func currentBranch(in directory: URL) async -> String? {
    let branch = await GitProcessRunner.run(
      ["rev-parse", "--abbrev-ref", "HEAD"],
      in: directory
    )

    guard branch != "HEAD" else {
      return nil
    }

    return branch
  }

  private func currentUpstreamBranch(in directory: URL) async -> String? {
    await GitProcessRunner.run(
      ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"],
      in: directory
    )
  }

  private func runMutation(
    _ arguments: [String],
    in directory: URL
  ) async -> GitProcessResult {
    let repositoryRoot = await repositoryRoot(for: directory)
    return await GitProcessRunner.runResult(arguments, in: repositoryRoot)
  }
}
