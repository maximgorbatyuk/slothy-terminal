import Foundation

/// Per-author commit statistics.
struct AuthorStats: Identifiable {
  var id: String { "\(name)|\(email)" }
  let name: String
  let email: String
  let commitCount: Int
}

/// A single day's commit count.
struct DailyActivity: Identifiable {
  var id: Date { date }
  let date: Date
  let commitCount: Int
}

/// High-level repository summary.
struct RepositorySummary {
  let totalCommits: Int
  let totalAuthors: Int
  let firstCommitDate: Date?
  let currentBranch: String?
}

/// A single commit with parent relationships and decorations.
struct GraphCommit: Identifiable {
  let id: String
  let shortHash: String
  let subject: String
  let authorName: String
  let authorEmail: String
  let authorDate: Date
  let parentHashes: [String]
  let decorations: [String]
}

/// State of a single lane at a given row.
enum LaneState: Equatable {
  case empty
  case passThrough(color: Int)
  case commitDot(color: Int)
  case mergeIn(color: Int)
}

/// Lane assignment for rendering a single row in the graph.
struct LaneAssignment: Identifiable {
  var id: String { commit.id }
  let commit: GraphCommit
  let laneIndex: Int
  let activeLanes: [LaneState]
  let mergeSourceLanes: [Int]
}
