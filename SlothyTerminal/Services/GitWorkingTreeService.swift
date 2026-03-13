import Foundation

/// Service for parsing and mutating a repository working tree for the Make Commit UI.
final class GitWorkingTreeService {
  static let shared = GitWorkingTreeService()

  private init() {}

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
}
