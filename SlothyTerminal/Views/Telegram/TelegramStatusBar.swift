import SwiftUI

/// Displays the current bot state, status, user ID, and agent.
struct TelegramStatusBar: View {
  let runtime: TelegramBotRuntime

  private var configManager: ConfigManager

  init(runtime: TelegramBotRuntime) {
    self.runtime = runtime
    self.configManager = ConfigManager.shared
  }

  var body: some View {
    HStack(spacing: 12) {
      /// Runtime state badge.
      HStack(spacing: 4) {
        Circle()
          .fill(stateColor)
          .frame(width: 8, height: 8)

        Text(stateText)
          .font(.system(size: 11, weight: .medium))
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(stateColor.opacity(0.15))
      .cornerRadius(4)

      /// Status text.
      Text(statusText)
        .font(.system(size: 11))
        .foregroundColor(.secondary)

      Spacer()

      /// User ID.
      if let userId = configManager.config.telegramAllowedUserID {
        HStack(spacing: 4) {
          Image(systemName: "person.fill")
            .font(.system(size: 9))
          Text("\(userId)")
            .font(.system(size: 10, design: .monospaced))
        }
        .foregroundColor(.secondary)
      }

      /// Execution agent.
      HStack(spacing: 4) {
        Image(systemName: "cpu")
          .font(.system(size: 9))
        Text(configManager.config.telegramExecutionAgent.rawValue)
          .font(.system(size: 10))
      }
      .foregroundColor(.secondary)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(appCardColor)
  }

  private var stateColor: Color {
    runtime.mode == .stopped ? .secondary : .green
  }

  private var stateText: String {
    runtime.mode == .stopped ? "Stopped" : "Execute"
  }

  private var statusText: String {
    switch runtime.status {
    case .idle:
      return "Idle"

    case .running:
      return "Polling..."

    case .error(let message):
      return message
    }
  }
}
