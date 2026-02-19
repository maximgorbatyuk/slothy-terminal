import SwiftUI

/// Displays the bot's activity counters.
struct TelegramCountersBar: View {
  let stats: TelegramBotStats

  var body: some View {
    HStack(spacing: 16) {
      CounterPill(label: "Rx", value: stats.received, color: .blue)
      CounterPill(label: "Ig", value: stats.ignored, color: .secondary)
      CounterPill(label: "Ex", value: stats.executed, color: .green)
      CounterPill(label: "Fail", value: stats.failed, color: .red)

      Spacer()
    }
  }
}

/// A single counter display.
private struct CounterPill: View {
  let label: String
  let value: Int
  let color: Color

  var body: some View {
    HStack(spacing: 4) {
      Text(label)
        .font(.system(size: 10, weight: .medium))
        .foregroundColor(.secondary)

      Text("\(value)")
        .font(.system(size: 11, weight: .semibold, design: .monospaced))
        .foregroundColor(color)
    }
  }
}
