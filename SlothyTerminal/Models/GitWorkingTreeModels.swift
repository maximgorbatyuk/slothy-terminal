import Foundation

/// Git porcelain status value for a single status column.
enum GitStatusColumn: Character {
  case unmodified = " "
  case modified = "M"
  case added = "A"
  case deleted = "D"
  case renamed = "R"
  case copied = "C"
  case untracked = "?"
  case unmerged = "U"
  case ignored = "!"

  init?(statusCharacter: Character) {
    self.init(rawValue: statusCharacter)
  }

  var badge: String {
    switch self {
    case .unmodified:
      return ""

    default:
      return String(rawValue)
    }
  }
}

/// Visible sections in the Make Commit change list.
enum GitChangeSection: String, CaseIterable, Identifiable {
  case staged
  case unstaged

  var id: String { rawValue }
}

/// A repository change entry scoped for the Make Commit UI.
struct GitScopedChange: Identifiable, Equatable {
  var id: String { repoRelativePath }

  let repoRelativePath: String
  let displayPath: String
  let indexStatus: GitStatusColumn
  let workTreeStatus: GitStatusColumn

  var hasStagedEntry: Bool {
    indexStatus != .unmodified && indexStatus != .untracked
  }

  var hasUnstagedEntry: Bool {
    workTreeStatus != .unmodified
  }

  var isUntracked: Bool {
    indexStatus == .untracked || workTreeStatus == .untracked
  }

  var filename: String {
    (repoRelativePath as NSString).lastPathComponent
  }

  var secondaryDisplayPath: String? {
    guard displayPath != filename else {
      return nil
    }

    return displayPath
  }

  func hasEntry(in section: GitChangeSection) -> Bool {
    switch section {
    case .staged:
      return hasStagedEntry

    case .unstaged:
      return hasUnstagedEntry
    }
  }

  func status(in section: GitChangeSection) -> GitStatusColumn {
    switch section {
    case .staged:
      return indexStatus

    case .unstaged:
      return workTreeStatus
    }
  }
}

/// Parsed git working tree state for a scoped directory.
struct GitWorkingTreeSnapshot: Equatable {
  let changes: [GitScopedChange]
  let scopePath: String?
  let hasStagedChangesOutsideScope: Bool

  init(
    changes: [GitScopedChange],
    scopePath: String? = nil,
    hasStagedChangesOutsideScope: Bool = false
  ) {
    self.changes = changes
    self.scopePath = scopePath
    self.hasStagedChangesOutsideScope = hasStagedChangesOutsideScope
  }

  var hasStagedChangesInScope: Bool {
    changes.contains { $0.hasStagedEntry }
  }

  var stagedChanges: [GitScopedChange] {
    changes.filter { $0.hasStagedEntry }
  }

  var unstagedChanges: [GitScopedChange] {
    changes.filter { $0.hasUnstagedEntry }
  }

  func canCommit(message: String) -> Bool {
    let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !trimmedMessage.isEmpty else {
      return false
    }

    guard hasStagedChangesInScope else {
      return false
    }

    return !hasStagedChangesOutsideScope
  }
}
