import Foundation

/// Represents a 50/50 side-by-side split of two tabs within a workspace.
/// Both tab IDs must belong to the same workspace.
struct WorkspaceSplitState: Equatable, Codable {
  /// Tab shown in the left pane.
  var leftTabID: UUID

  /// Tab shown in the right pane.
  var rightTabID: UUID

  /// Returns true if the given tab ID is part of this split.
  func contains(_ tabID: UUID) -> Bool {
    tabID == leftTabID || tabID == rightTabID
  }

  /// Returns the other tab ID in the split, or nil if the given ID is not a member.
  func otherTab(than tabID: UUID) -> UUID? {
    if tabID == leftTabID {
      return rightTabID
    }

    if tabID == rightTabID {
      return leftTabID
    }

    return nil
  }

  /// Replaces the focused tab with a new tab ID. Returns the updated state,
  /// or nil if `focusedTabID` is not a member of this split.
  func replacing(_ focusedTabID: UUID, with newTabID: UUID) -> WorkspaceSplitState? {
    guard newTabID != leftTabID, newTabID != rightTabID else {
      return nil
    }

    if focusedTabID == leftTabID {
      return WorkspaceSplitState(leftTabID: newTabID, rightTabID: rightTabID)
    }

    if focusedTabID == rightTabID {
      return WorkspaceSplitState(leftTabID: leftTabID, rightTabID: newTabID)
    }

    return nil
  }

  /// Returns the remaining tab ID after removing the given tab,
  /// or nil if the given ID is not a member.
  func remaining(after removedTabID: UUID) -> UUID? {
    otherTab(than: removedTabID)
  }

  /// Both tab IDs as a set for quick membership checks.
  var tabIDs: Set<UUID> {
    [leftTabID, rightTabID]
  }
}
