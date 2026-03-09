import Foundation

/// Prevents render-driven activity checks from being endlessly rescheduled.
@MainActor
final class ActivityDetectionGate {
  private var isScheduled = false

  func beginSchedule() -> Bool {
    guard !isScheduled else {
      return false
    }

    isScheduled = true
    return true
  }

  func finishSchedule() {
    isScheduled = false
  }

  func cancelSchedule() {
    isScheduled = false
  }
}
