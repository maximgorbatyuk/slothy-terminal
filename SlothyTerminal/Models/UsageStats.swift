import Foundation

/// Tracks usage statistics for an AI agent session.
@Observable
class UsageStats {
  var tokensIn: Int = 0
  var tokensOut: Int = 0
  var messageCount: Int = 0
  var startTime: Date = Date()
  var estimatedCost: Double?

  var totalTokens: Int {
    tokensIn + tokensOut
  }

  var duration: TimeInterval {
    Date().timeIntervalSince(startTime)
  }

  var formattedDuration: String {
    let totalSeconds = Int(duration)
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60

    if hours > 0 {
      return String(format: "%dh %02dm", hours, minutes)
    } else {
      return String(format: "%dm %02ds", minutes, seconds)
    }
  }

  func reset() {
    tokensIn = 0
    tokensOut = 0
    messageCount = 0
    startTime = Date()
    estimatedCost = nil
  }
}
