import SwiftUI

/// Start/Stop controls for the Telegram bot.
struct TelegramControlsBar: View {
  let runtime: TelegramBotRuntime

  var body: some View {
    HStack(spacing: 8) {
      if runtime.mode == .stopped {
        Button {
          runtime.start()
        } label: {
          Label("Start", systemImage: "play.fill")
        }
        .buttonStyle(.borderedProminent)
        .tint(.green)
      } else {
        Button {
          runtime.stop()
        } label: {
          Label("Stop", systemImage: "stop.fill")
        }
        .buttonStyle(.bordered)
        .tint(.red)
      }

      Spacer()
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
  }
}
