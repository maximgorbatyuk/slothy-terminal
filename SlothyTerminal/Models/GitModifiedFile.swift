import SwiftUI

/// Status of a file in the git working tree.
enum GitFileStatus: String {
  case modified = "M"
  case added = "A"
  case deleted = "D"
  case renamed = "R"
  case copied = "C"
  case untracked = "?"
  case ignored = "!"

  /// Short badge text for display.
  var badge: String {
    switch self {
    case .modified:
      return "M"

    case .added:
      return "A"

    case .deleted:
      return "D"

    case .renamed:
      return "R"

    case .copied:
      return "C"

    case .untracked:
      return "U"

    case .ignored:
      return "!"
    }
  }

  /// Badge color for status indication.
  var color: Color {
    switch self {
    case .modified:
      return .orange

    case .added, .copied:
      return .green

    case .deleted:
      return .red

    case .renamed:
      return .blue

    case .untracked:
      return .secondary

    case .ignored:
      return .gray
    }
  }
}

/// A file reported by `git status --porcelain`.
struct GitModifiedFile: Identifiable {
  var id: String { path }

  /// Relative path from repository root.
  let path: String

  /// Filename (last path component).
  var filename: String {
    (path as NSString).lastPathComponent
  }

  /// Git status of this file.
  let status: GitFileStatus
}
