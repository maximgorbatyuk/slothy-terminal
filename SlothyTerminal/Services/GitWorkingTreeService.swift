import Foundation

/// Service for parsing and mutating a repository working tree for the Make Commit UI.
final class GitWorkingTreeService {
  static let shared = GitWorkingTreeService()

  private struct BufferedDiffLine {
    let lineNumber: Int
    let text: String
  }

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

  func isValidBranchName(_ branchName: String) -> Bool {
    !branchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
    guard isValidBranchName(branchName) else {
      return .failure(stderr: "Branch name must not be blank.")
    }

    return await runMutation(["switch", "-c", branchName], in: directory)
  }

  func commit(
    message: String,
    amend: Bool,
    in directory: URL
  ) async -> GitProcessResult {
    let arguments = amend
      ? ["commit", "--amend", "-m", message]
      : ["commit", "-m", message]

    return await runMutation(arguments, in: directory)
  }

  func deleteUntrackedFile(
    path: String,
    in directory: URL
  ) async -> GitProcessResult {
    let repositoryRoot = await repositoryRoot(for: directory)
    let fileURL = repositoryRoot.appendingPathComponent(path)

    do {
      try FileManager.default.removeItem(at: fileURL)
      return GitProcessResult(
        stdout: "",
        stderr: "",
        terminationStatus: 0
      )
    } catch {
      return .failure(stderr: error.localizedDescription)
    }
  }

  func loadSnapshot(in directory: URL) async -> GitWorkingTreeSnapshot {
    let repositoryRoot = await repositoryRoot(for: directory)
    let scopePath = scopePath(
      for: directory,
      repositoryRoot: repositoryRoot
    )
    let result = await GitProcessRunner.runResult(
      ["status", "--porcelain=v1", "--untracked-files=all"],
      in: repositoryRoot
    )

    guard result.isSuccess else {
      return GitWorkingTreeSnapshot(
        changes: [],
        scopePath: scopePath
      )
    }

    return parseStatusOutput(
      result.stdout,
      scopePath: scopePath
    )
  }

  func parseUnifiedDiff(_ output: String) -> [GitDiffRow] {
    var rows: [GitDiffRow] = []
    var oldLineNumber: Int?
    var newLineNumber: Int?
    var deletionBuffer: [BufferedDiffLine] = []
    var additionBuffer: [BufferedDiffLine] = []
    var rowID = 0

    func makeRowID() -> String {
      defer {
        rowID += 1
      }

      return "diff-row-\(rowID)"
    }

    func flushBuffers() {
      let pairedCount = max(deletionBuffer.count, additionBuffer.count)

      guard pairedCount > 0 else {
        return
      }

      for index in 0..<pairedCount {
        let deletion = index < deletionBuffer.count ? deletionBuffer[index] : nil
        let addition = index < additionBuffer.count ? additionBuffer[index] : nil

        switch (deletion, addition) {
        case let (.some(deletion), .some(addition)):
          rows.append(
            GitDiffRow(
              id: makeRowID(),
              oldLineNumber: deletion.lineNumber,
              newLineNumber: addition.lineNumber,
              leftText: deletion.text,
              rightText: addition.text,
              kind: .modification
            )
          )

        case let (.some(deletion), .none):
          rows.append(
            GitDiffRow(
              id: makeRowID(),
              oldLineNumber: deletion.lineNumber,
              newLineNumber: nil,
              leftText: deletion.text,
              rightText: "",
              kind: .deletion
            )
          )

        case let (.none, .some(addition)):
          rows.append(
            GitDiffRow(
              id: makeRowID(),
              oldLineNumber: nil,
              newLineNumber: addition.lineNumber,
              leftText: "",
              rightText: addition.text,
              kind: .addition
            )
          )

        case (.none, .none):
          break
        }
      }

      deletionBuffer.removeAll(keepingCapacity: true)
      additionBuffer.removeAll(keepingCapacity: true)
    }

    for rawLine in output.split(separator: "\n", omittingEmptySubsequences: false) {
      let line = String(rawLine)

      if let hunkRange = parseHunkHeader(line) {
        flushBuffers()
        oldLineNumber = hunkRange.oldStart
        newLineNumber = hunkRange.newStart
        continue
      }

      guard
        let prefix = line.first,
        oldLineNumber != nil || newLineNumber != nil
      else {
        continue
      }

      switch prefix {
      case " ":
        flushBuffers()
        rows.append(
          GitDiffRow(
            id: makeRowID(),
            oldLineNumber: oldLineNumber,
            newLineNumber: newLineNumber,
            leftText: String(line.dropFirst()),
            rightText: String(line.dropFirst()),
            kind: .context
          )
        )
        oldLineNumber = oldLineNumber.map { $0 + 1 }
        newLineNumber = newLineNumber.map { $0 + 1 }

      case "-":
        deletionBuffer.append(
          BufferedDiffLine(
            lineNumber: oldLineNumber ?? 0,
            text: String(line.dropFirst())
          )
        )
        oldLineNumber = oldLineNumber.map { $0 + 1 }

      case "+":
        additionBuffer.append(
          BufferedDiffLine(
            lineNumber: newLineNumber ?? 0,
            text: String(line.dropFirst())
          )
        )
        newLineNumber = newLineNumber.map { $0 + 1 }

      case "\\":
        continue

      default:
        continue
      }
    }

    flushBuffers()
    return rows
  }

  func parseDiffOutput(_ output: String) -> GitDiffDocument {
    let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !trimmedOutput.isEmpty else {
      return GitDiffDocument()
    }

    if trimmedOutput.contains("Binary files ") && trimmedOutput.contains(" differ") {
      return GitDiffDocument(isBinary: true)
    }

    return GitDiffDocument(rows: parseUnifiedDiff(output))
  }

  func loadDiff(
    for section: GitChangeSection,
    path: String,
    in directory: URL
  ) async -> GitDiffDocument {
    let repositoryRoot = await repositoryRoot(for: directory)
    let arguments: [String]

    switch section {
    case .staged:
      arguments = ["diff", "--cached", "--", path]

    case .unstaged:
      arguments = ["diff", "--", path]
    }

    let result = await GitProcessRunner.runResult(arguments, in: repositoryRoot)

    guard result.isSuccess else {
      return GitDiffDocument()
    }

    return parseDiffOutput(result.stdout)
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

  private func scopePath(
    for directory: URL,
    repositoryRoot: URL
  ) -> String? {
    let repositoryPath = repositoryRoot.standardizedFileURL.path
    let directoryPath = directory.standardizedFileURL.path

    guard directoryPath != repositoryPath else {
      return nil
    }

    let prefix = "\(repositoryPath)/"
    guard directoryPath.hasPrefix(prefix) else {
      return nil
    }

    return String(directoryPath.dropFirst(prefix.count))
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

  private func parseHunkHeader(_ line: String) -> (oldStart: Int, newStart: Int)? {
    guard line.hasPrefix("@@") else {
      return nil
    }

    let components = line.split(separator: " ")

    guard components.count >= 3 else {
      return nil
    }

    guard
      let oldStart = parseHunkRangeComponent(String(components[1]), prefix: "-"),
      let newStart = parseHunkRangeComponent(String(components[2]), prefix: "+")
    else {
      return nil
    }

    return (oldStart, newStart)
  }

  private func parseHunkRangeComponent(
    _ component: String,
    prefix: Character
  ) -> Int? {
    guard component.first == prefix else {
      return nil
    }

    let range = component.dropFirst().split(separator: ",", maxSplits: 1)
    guard let start = range.first else {
      return nil
    }

    return Int(start)
  }
}
