import Foundation

/// Sub-tabs within the Git client tab.
enum GitTab: String, CaseIterable, Identifiable {
  case overview
  case revisionGraph
  case commit
  /// Placeholder tabs for upcoming features.
  case comingSoon1
  case comingSoon2

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .overview:
      return "Overview"

    case .revisionGraph:
      return "Revision Graph"

    case .commit:
      return "Make Commit"

    case .comingSoon1, .comingSoon2:
      return "Coming Soon"
    }
  }

  /// Whether this tab has real content implemented.
  var isStub: Bool {
    switch self {
    case .overview, .revisionGraph:
      return false

    case .commit, .comingSoon1, .comingSoon2:
      return true
    }
  }

  /// SF Symbol icon for the tab.
  var iconName: String {
    switch self {
    case .overview:
      return "chart.bar.xaxis"

    case .revisionGraph:
      return "point.3.connected.trianglepath.dotted"

    case .commit:
      return "square.and.pencil"

    case .comingSoon1, .comingSoon2:
      return "sparkles"
    }
  }
}
