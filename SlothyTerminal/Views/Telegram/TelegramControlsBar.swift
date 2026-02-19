import SwiftUI

/// Start/Stop/Mode toggle controls for the Telegram bot.
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

      Divider()
        .frame(height: 20)

      /// Mode toggle buttons.
      Button {
        runtime.switchMode(.execute)
      } label: {
        Text("Execute")
          .font(.system(size: 11))
      }
      .buttonStyle(.bordered)
      .tint(runtime.mode == .execute ? .green : nil)
      .disabled(runtime.mode == .stopped)

      Button {
        runtime.switchMode(.passive)
      } label: {
        Text("Listen but not execute commands")
          .font(.system(size: 11))
      }
      .buttonStyle(.bordered)
      .tint(runtime.mode == .passive ? .orange : nil)
      .disabled(runtime.mode == .stopped)

      Spacer()
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
  }
}
