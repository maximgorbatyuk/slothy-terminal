import Foundation

/// Tracks usage statistics for an AI agent session.
@Observable
class UsageStats {
  var tokensIn: Int = 0
  var tokensOut: Int = 0
  var messageCount: Int = 0
  var startTime: Date = Date()
  var estimatedCost: Double?
  var contextWindowLimit: Int = 200_000

  /// Total tokens used (input + output).
  var totalTokens: Int {
    tokensIn + tokensOut
  }

  /// Duration since session started.
  var duration: TimeInterval {
    Date().timeIntervalSince(startTime)
  }

  /// Formatted duration string.
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

  /// Formatted input tokens with thousands separator.
  var formattedTokensIn: String {
    formatNumber(tokensIn)
  }

  /// Formatted output tokens with thousands separator.
  var formattedTokensOut: String {
    formatNumber(tokensOut)
  }

  /// Formatted total tokens with thousands separator.
  var formattedTotalTokens: String {
    formatNumber(totalTokens)
  }

  /// Formatted estimated cost.
  var formattedCost: String? {
    guard let cost = estimatedCost else {
      return nil
    }

    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = "USD"
    formatter.minimumFractionDigits = 4
    formatter.maximumFractionDigits = 4
    return formatter.string(from: NSNumber(value: cost))
  }

  /// Context window usage percentage.
  var contextWindowPercentage: Double {
    guard contextWindowLimit > 0 else {
      return 0
    }

    return Double(totalTokens) / Double(contextWindowLimit)
  }

  /// Formatted context window percentage.
  var formattedContextPercentage: String {
    String(format: "%.1f%%", contextWindowPercentage * 100)
  }

  /// Applies an update from parsed terminal output.
  /// - Parameter update: The parsed usage update.
  /// - Parameter incrementMessages: If true, adds to message count instead of replacing.
  func applyUpdate(_ update: UsageUpdate, incrementMessages: Bool = false) {
    if let tokensIn = update.tokensIn {
      self.tokensIn = tokensIn
    }

    if let tokensOut = update.tokensOut {
      self.tokensOut = tokensOut
    }

    if let cost = update.cost {
      self.estimatedCost = cost
    }

    if let messageCount = update.messageCount {
      if incrementMessages {
        self.messageCount += messageCount
      } else {
        self.messageCount = messageCount
      }
    }

    if let limit = update.contextWindowLimit {
      self.contextWindowLimit = limit
    }
  }

  /// Increments the message count.
  func incrementMessageCount() {
    messageCount += 1
  }

  /// Resets all statistics.
  func reset() {
    tokensIn = 0
    tokensOut = 0
    messageCount = 0
    startTime = Date()
    estimatedCost = nil
    contextWindowLimit = 200_000
  }

  /// Starts a new session by setting the start time to now.
  func startSession() {
    startTime = Date()
  }

  /// Formats a number with thousands separator.
  private func formatNumber(_ value: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.groupingSeparator = ","
    return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
  }
}
