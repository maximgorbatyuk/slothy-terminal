import Foundation

/// Assigns visual lanes to commits for graph rendering.
///
/// Uses a standard lane-tracking algorithm (similar to gitk/GitKraken):
/// each lane tracks the next expected commit hash, and lanes are created,
/// continued, or terminated as commits and their parents are processed.
enum GraphLaneCalculator {
  /// Assigns lane positions and visual state to each commit for graph rendering.
  /// - Parameter commits: Commits in topological order (children before parents).
  /// - Returns: Lane assignments with visual state for each row.
  static func assignLanes(_ commits: [GraphCommit]) -> [LaneAssignment] {
    guard !commits.isEmpty else {
      return []
    }

    var activeLanes: [String?] = []
    var colorMap: [String: Int] = [:]
    var nextColorIndex = 0
    var result: [LaneAssignment] = []

    for commit in commits {
      // Find or create lane for this commit.
      let laneIndex: Int
      if let existingIndex = activeLanes.firstIndex(of: commit.id) {
        laneIndex = existingIndex
      } else if let freeIndex = activeLanes.firstIndex(of: nil) {
        activeLanes[freeIndex] = commit.id
        laneIndex = freeIndex
      } else {
        activeLanes.append(commit.id)
        laneIndex = activeLanes.count - 1
      }

      // Assign color for this commit if not already assigned.
      if colorMap[commit.id] == nil {
        colorMap[commit.id] = nextColorIndex % 8
        nextColorIndex += 1
      }

      let commitColor = colorMap[commit.id]!

      // Build row state.
      var rowState: [LaneState] = Array(repeating: .empty, count: activeLanes.count)
      for i in 0..<activeLanes.count {
        if i == laneIndex {
          rowState[i] = .commitDot(color: commitColor)
        } else if let trackedHash = activeLanes[i] {
          let color = colorMap[trackedHash] ?? 0
          rowState[i] = .passThrough(color: color)
        }
      }

      // Handle parents.
      var mergeSourceLanes: [Int] = []

      if commit.parentHashes.isEmpty {
        // Root commit — lane ends. Remove from color map to bound memory.
        colorMap.removeValue(forKey: commit.id)
        activeLanes[laneIndex] = nil
      } else {
        // First parent: continue this lane.
        let firstParent = commit.parentHashes[0]
        activeLanes[laneIndex] = firstParent

        if colorMap[firstParent] == nil {
          colorMap[firstParent] = commitColor
        }

        // Additional parents: merge sources.
        for parentIndex in 1..<commit.parentHashes.count {
          let parentHash = commit.parentHashes[parentIndex]

          if let existingLane = activeLanes.firstIndex(of: parentHash) {
            // Parent already tracked in another lane.
            mergeSourceLanes.append(existingLane)
          } else if let freeLane = activeLanes.firstIndex(of: nil) {
            // Reuse a free slot.
            activeLanes[freeLane] = parentHash

            if colorMap[parentHash] == nil {
              colorMap[parentHash] = nextColorIndex % 8
              nextColorIndex += 1
            }

            mergeSourceLanes.append(freeLane)
          } else {
            // Append new lane.
            if colorMap[parentHash] == nil {
              colorMap[parentHash] = nextColorIndex % 8
              nextColorIndex += 1
            }

            activeLanes.append(parentHash)
            mergeSourceLanes.append(activeLanes.count - 1)
          }
        }
      }

      // Update merge source lanes in row state.
      for mergeLane in mergeSourceLanes {
        // Ensure rowState is large enough.
        while rowState.count <= mergeLane {
          rowState.append(.empty)
        }

        if case .empty = rowState[mergeLane] {
          let color = colorMap[activeLanes[mergeLane] ?? ""] ?? 0
          rowState[mergeLane] = .mergeIn(color: color)
        }
      }

      // Prune the commit hash from colorMap — it's no longer tracked in any lane.
      if !activeLanes.contains(commit.id) {
        colorMap.removeValue(forKey: commit.id)
      }

      // Compact trailing nil slots.
      let minSize = max(laneIndex + 1, (mergeSourceLanes.max() ?? 0) + 1)
      while activeLanes.count > minSize,
            activeLanes.last == nil
      {
        activeLanes.removeLast()
      }

      result.append(LaneAssignment(
        commit: commit,
        laneIndex: laneIndex,
        activeLanes: rowState,
        mergeSourceLanes: mergeSourceLanes
      ))
    }

    return result
  }
}
