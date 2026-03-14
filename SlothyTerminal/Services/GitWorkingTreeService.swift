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

  /// Validates a branch name against common git ref-format rules.
  func isValidBranchName(_ branchName: String) -> Bool {
    let trimmed = branchName.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !trimmed.isEmpty else {
      return false
    }

    let invalidSubstrings = ["..", " ", "~", "^", ":", "?", "*", "[", "\\", "@{", "//"]
    for invalid in invalidSubstrings {
      guard !trimmed.contains(invalid) else {
        return false
      }
    }

    guard !trimmed.hasPrefix("/"),
          !trimmed.hasSuffix("/"),
          !trimmed.hasSuffix("."),
          !trimmed.hasSuffix(".lock"),
          trimmed != "@"
    else {
      return false
    }

    let hasControlCharacters = trimmed.unicodeScalars.contains {
      CharacterSet.controlCharacters.contains($0)
    }

    guard !hasControlCharacters else {
      return false
    }

    return true
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

  func getHeadHash(in directory: URL) async -> String? {
    let repositoryRoot = await repositoryRoot(for: directory)
    return await GitProcessRunner.run(
      ["rev-parse", "HEAD"],
      in: repositoryRoot
    )
  }

  /// Performs `git reset --soft` to the given target.
  ///
  /// Callers must ensure `target` is a safe ref (commit hash or `HEAD~N`).
  func softReset(to target: String, in directory: URL) async -> GitProcessResult {
    await runMutation(["reset", "--soft", target], in: directory)
  }

  func stageFile(path: String, in directory: URL) async -> GitProcessResult {
    await runMutation(["add", "--", path], in: directory)
  }

  func stageFiles(paths: [String], in directory: URL) async -> GitProcessResult {
    await runMutation(["add", "--"] + paths, in: directory)
  }

  func unstageFile(path: String, in directory: URL) async -> GitProcessResult {
    await runMutation(["restore", "--staged", "--", path], in: directory)
  }

  func unstageFiles(paths: [String], in directory: URL) async -> GitProcessResult {
    await runMutation(["restore", "--staged", "--"] + paths, in: directory)
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
    for change: GitScopedChange,
    section: GitChangeSection,
    in directory: URL
  ) async -> GitDiffDocument {
    if section == .unstaged, change.isUntracked {
      return await loadUntrackedDiff(
        path: change.repoRelativePath,
        in: directory
      )
    }

    let repositoryRoot = await repositoryRoot(for: directory)
    let arguments: [String]

    switch section {
    case .staged:
      arguments = ["diff", "-U10000", "--cached", "--", change.repoRelativePath]

    case .unstaged:
      arguments = ["diff", "-U10000", "--", change.repoRelativePath]
    }

    let result = await GitProcessRunner.runResult(arguments, in: repositoryRoot)

    guard result.isSuccess else {
      return GitDiffDocument()
    }

    let document = parseDiffOutput(result.stdout)

    if document.isEmpty {
      return await loadFallbackDiff(
        path: change.repoRelativePath,
        section: section,
        in: repositoryRoot
      )
    }

    return document
  }

  func makeUntrackedDiffDocument(from fileContents: String) -> GitDiffDocument {
    var lines = fileContents.components(separatedBy: "\n")
    if fileContents.hasSuffix("\n") {
      lines.removeLast()
    }

    let rows = lines.enumerated().map { index, line in
      GitDiffRow(
        id: "untracked-row-\(index)",
        oldLineNumber: nil,
        newLineNumber: index + 1,
        leftText: "",
        rightText: line,
        kind: .addition
      )
    }

    return GitDiffDocument(rows: rows)
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
    let repoRelativePath = normalizedStatusPath(
      from: rawPath,
      isRename: indexStatus == .renamed || workTreeStatus == .renamed
    )
    let displayPath = displayPath(for: repoRelativePath, scopePath: scopePath)

    return GitScopedChange(
      repoRelativePath: repoRelativePath,
      displayPath: displayPath,
      indexStatus: indexStatus,
      workTreeStatus: workTreeStatus
    )
  }

  private func normalizedStatusPath(
    from rawPath: String,
    isRename: Bool
  ) -> String {
    let path: String
    if isRename, let arrowRange = rawPath.range(of: " -> ") {
      path = String(rawPath[arrowRange.upperBound...])
    } else {
      path = rawPath
    }

    return unquotedStatusPath(path)
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

  /// Fallback when `git diff` produces an empty document for a non-binary file.
  /// Loads the file content directly so the user sees something meaningful.
  private func loadFallbackDiff(
    path: String,
    section: GitChangeSection,
    in repositoryRoot: URL
  ) async -> GitDiffDocument {
    let contents: String?

    switch section {
    case .staged:
      let result = await GitProcessRunner.runResult(
        ["show", ":\(path)"],
        in: repositoryRoot
      )
      contents = result.isSuccess ? result.stdout : nil

    case .unstaged:
      let fileURL = repositoryRoot.appendingPathComponent(path)

      guard let data = try? Data(contentsOf: fileURL) else {
        return GitDiffDocument()
      }

      guard let text = String(data: data, encoding: .utf8) else {
        return GitDiffDocument(isBinary: true)
      }

      contents = text
    }

    guard let contents, !contents.isEmpty else {
      return GitDiffDocument()
    }

    return makeUntrackedDiffDocument(from: contents)
  }

  private func loadUntrackedDiff(
    path: String,
    in directory: URL
  ) async -> GitDiffDocument {
    let repositoryRoot = await repositoryRoot(for: directory)
    let fileURL = repositoryRoot.appendingPathComponent(path)

    guard let data = try? Data(contentsOf: fileURL) else {
      return GitDiffDocument()
    }

    guard let contents = String(data: data, encoding: .utf8) else {
      return GitDiffDocument(isBinary: true)
    }

    return makeUntrackedDiffDocument(from: contents)
  }

  private func unquotedStatusPath(_ path: String) -> String {
    guard path.count >= 2, path.first == "\"", path.last == "\"" else {
      return path
    }

    let body = path.dropFirst().dropLast()
    var result = ""
    var index = body.startIndex

    while index < body.endIndex {
      let character = body[index]
      guard character == "\\" else {
        result.append(character)
        index = body.index(after: index)
        continue
      }

      let escapeIndex = body.index(after: index)
      guard escapeIndex < body.endIndex else {
        result.append("\\")
        break
      }

      let escape = body[escapeIndex]
      switch escape {
      case "\"":
        result.append("\"")
        index = body.index(after: escapeIndex)

      case "\\":
        result.append("\\")
        index = body.index(after: escapeIndex)

      case "n":
        result.append("\n")
        index = body.index(after: escapeIndex)

      case "r":
        result.append("\r")
        index = body.index(after: escapeIndex)

      case "t":
        result.append("\t")
        index = body.index(after: escapeIndex)

      case "0"..."7":
        var octalDigits = String(escape)
        var scanIndex = body.index(after: escapeIndex)
        while scanIndex < body.endIndex, octalDigits.count < 3 {
          let next = body[scanIndex]
          guard ("0"..."7").contains(next) else {
            break
          }

          octalDigits.append(next)
          scanIndex = body.index(after: scanIndex)
        }

        if let scalarValue = UInt8(octalDigits, radix: 8) {
          result.append(Character(UnicodeScalar(scalarValue)))
        }
        index = scanIndex

      default:
        result.append(escape)
        index = body.index(after: escapeIndex)
      }
    }

    return result
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
