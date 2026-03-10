import Foundation
import Testing

@testable import SlothyTerminalLib

@Suite("GraphLaneCalculator")
struct GraphLaneCalculatorTests {
  /// Helper to create a GraphCommit with minimal fields.
  private func commit(
    id: String,
    parents: [String] = [],
    subject: String = ""
  ) -> GraphCommit {
    GraphCommit(
      id: id,
      shortHash: String(id.prefix(7)),
      subject: subject.isEmpty ? "Commit \(id)" : subject,
      authorName: "Test",
      authorEmail: "test@example.com",
      authorDate: Date(),
      parentHashes: parents,
      decorations: []
    )
  }

  @Test("Linear history — all commits in lane 0")
  func linearHistory() {
    let commits = [
      commit(id: "A", parents: ["B"]),
      commit(id: "B", parents: ["C"]),
      commit(id: "C"),
    ]

    let assignments = GraphLaneCalculator.assignLanes(commits)

    #expect(assignments.count == 3)

    for assignment in assignments {
      #expect(assignment.laneIndex == 0)
      #expect(assignment.mergeSourceLanes.isEmpty)

      // Lane 0 should be a commitDot.
      guard let firstLane = assignment.activeLanes.first else {
        Issue.record("Expected at least one active lane")
        continue
      }

      if case .commitDot = firstLane {
        // Expected.
      } else {
        Issue.record("Lane 0 should be .commitDot, got \(firstLane)")
      }
    }
  }

  @Test("Single branch and merge — merge has merge source lanes")
  func singleBranchAndMerge() {
    // M merges B and D: M(parents: B,D), B(parent: A), D(parent: C), C(parent: A), A(root)
    let commits = [
      commit(id: "M", parents: ["B", "D"]),
      commit(id: "B", parents: ["A"]),
      commit(id: "D", parents: ["C"]),
      commit(id: "C", parents: ["A"]),
      commit(id: "A"),
    ]

    let assignments = GraphLaneCalculator.assignLanes(commits)

    #expect(assignments.count == 5)

    // M should have a merge source.
    let mergeAssignment = assignments[0]
    #expect(mergeAssignment.commit.id == "M")
    #expect(!mergeAssignment.mergeSourceLanes.isEmpty)

    // B and D should be in different lanes.
    let bLane = assignments[1].laneIndex
    let dLane = assignments[2].laneIndex
    #expect(bLane != dLane)
  }

  @Test("Root commit ends lane")
  func rootCommitEndsLane() {
    let commits = [commit(id: "ROOT")]

    let assignments = GraphLaneCalculator.assignLanes(commits)

    #expect(assignments.count == 1)
    #expect(assignments[0].laneIndex == 0)

    // The lane should have a commitDot.
    if case .commitDot = assignments[0].activeLanes[0] {
      // Expected.
    } else {
      Issue.record("Root commit lane should be .commitDot")
    }
  }

  @Test("Three-way merge — mergeSourceLanes has 2 entries")
  func threeWayMerge() {
    let commits = [
      commit(id: "M", parents: ["P1", "P2", "P3"]),
      commit(id: "P1"),
      commit(id: "P2"),
      commit(id: "P3"),
    ]

    let assignments = GraphLaneCalculator.assignLanes(commits)

    let mergeAssignment = assignments[0]
    #expect(mergeAssignment.commit.id == "M")
    #expect(mergeAssignment.mergeSourceLanes.count == 2)
  }

  @Test("Empty input returns empty")
  func emptyInput() {
    let assignments = GraphLaneCalculator.assignLanes([])
    #expect(assignments.isEmpty)
  }

  @Test("Lane compaction — nil slots are trimmed")
  func laneCompaction() {
    // Branch splits and merges back, then continues linearly.
    // M merges B and D, then continues to A.
    let commits = [
      commit(id: "M", parents: ["B", "D"]),
      commit(id: "B", parents: ["A"]),
      commit(id: "D", parents: ["A"]),
      commit(id: "A"),
    ]

    let assignments = GraphLaneCalculator.assignLanes(commits)

    // After D merges into A and both lanes resolve to A,
    // the final row (A) should not have excessive nil/empty lanes.
    let lastAssignment = assignments.last!
    let activeLaneCount = lastAssignment.activeLanes.filter { $0 != .empty }.count
    #expect(activeLaneCount <= 2)
  }
}
