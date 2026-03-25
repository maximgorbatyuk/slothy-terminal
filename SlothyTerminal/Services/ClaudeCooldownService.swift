import Foundation

enum ClaudeCooldownDecision: Equatable {
  case allowed
  case blocked(remainingSeconds: Int)
}

final class ClaudeCooldownService {
  static let shared = ClaudeCooldownService()

  private let cooldownInterval: TimeInterval
  private var lastSubmissionDate: Date?

  init(cooldownInterval: TimeInterval = 180) {
    self.cooldownInterval = cooldownInterval
  }

  func attemptSubmission(at date: Date = Date()) -> ClaudeCooldownDecision {
    if let lastSubmissionDate {
      let elapsed = date.timeIntervalSince(lastSubmissionDate)

      if elapsed < cooldownInterval {
        let remainingSeconds = Int(ceil(cooldownInterval - elapsed))
        return .blocked(remainingSeconds: remainingSeconds)
      }
    }

    lastSubmissionDate = date
    return .allowed
  }

  func reset() {
    lastSubmissionDate = nil
  }

  static func formatRemaining(seconds: Int) -> String {
    if seconds < 60 {
      return "\(seconds)s"
    }

    let minutes = seconds / 60
    let remainingSeconds = seconds % 60
    return "\(minutes)m \(remainingSeconds)s"
  }
}
