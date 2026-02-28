import SwiftUI

/// Main container view for the Telegram bot tab.
struct TelegramBotView: View {
  let runtime: TelegramBotRuntime

  var body: some View {
    VStack(spacing: 0) {
      TelegramStatusBar(runtime: runtime)

      Divider()

      TelegramControlsBar(runtime: runtime)

      Divider()

      TelegramCountersBar(stats: runtime.stats)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)

      Divider()

      HSplitView {
        TelegramMessageTimeline(messages: runtime.messages)
          .frame(minWidth: 300)

        TelegramActivityLog(events: runtime.events)
          .frame(minWidth: 200)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .background(appBackgroundColor)
  }
}
