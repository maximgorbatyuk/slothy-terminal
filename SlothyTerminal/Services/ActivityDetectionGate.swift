import Foundation

/// Prevents render-driven activity checks from being endlessly rescheduled.
@MainActor
final class ActivityDetectionGate {
  private var latestRenderVersion: UInt64 = 0
  private var scheduledRenderVersion: UInt64?
  private var inFlightRenderVersion: UInt64?
  private var lastCompletedRenderVersion: UInt64 = 0

  func noteRender() -> Bool {
    latestRenderVersion &+= 1
    let version = latestRenderVersion

    if inFlightRenderVersion == nil,
       scheduledRenderVersion == nil
    {
      scheduledRenderVersion = version
      return true
    }

    if scheduledRenderVersion != nil {
      scheduledRenderVersion = version
    }

    return false
  }

  func beginScheduledCheck() -> UInt64? {
    guard inFlightRenderVersion == nil,
          let scheduledRenderVersion
    else {
      return nil
    }

    self.scheduledRenderVersion = nil
    inFlightRenderVersion = scheduledRenderVersion
    return scheduledRenderVersion
  }

  func completeScheduledCheck(for version: UInt64) -> Bool {
    guard inFlightRenderVersion == version else {
      return false
    }

    inFlightRenderVersion = nil
    lastCompletedRenderVersion = max(lastCompletedRenderVersion, version)

    guard latestRenderVersion > lastCompletedRenderVersion,
          scheduledRenderVersion == nil
    else {
      return false
    }

    scheduledRenderVersion = latestRenderVersion
    return true
  }

  func shouldAcceptResult(for version: UInt64) -> Bool {
    inFlightRenderVersion == version
  }

  func cancelAll() {
    scheduledRenderVersion = nil
    inFlightRenderVersion = nil
    lastCompletedRenderVersion = latestRenderVersion
  }
}
