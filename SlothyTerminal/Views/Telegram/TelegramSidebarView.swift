import SwiftUI

/// Sidebar panel for the Telegram bot — vertical layout optimized for narrow widths.
struct TelegramSidebarView: View {
  @Environment(AppState.self) private var appState
  private var configManager = ConfigManager.shared

  var body: some View {
    VStack(spacing: 0) {
      if let runtime = appState.telegramRuntime {
        TelegramStatusBar(runtime: runtime)
        Divider()
        TelegramControlsBar(runtime: runtime)
        Divider()
        TelegramCountersBar(stats: runtime.stats)
          .padding(.horizontal, 12)
          .padding(.vertical, 6)
        Divider()
        TelegramMessageTimeline(messages: runtime.messages)
          .frame(maxHeight: .infinity)
        Divider()
        TelegramActivityLog(events: runtime.events)
          .frame(minHeight: 120, maxHeight: 200)
      } else {
        telegramSetupView
      }
    }
    .background(appBackgroundColor)
  }

  private var telegramSetupView: some View {
    VStack(spacing: 16) {
      Spacer()

      Image(systemName: "paperplane")
        .font(.system(size: 36))
        .foregroundColor(.secondary)

      let config = configManager.config

      if config.telegramBotToken == nil || config.telegramAllowedUserID == nil {
        Text("Telegram Bot not configured")
          .font(.headline)

        Text("Set your bot token and user ID in Settings → Telegram.")
          .font(.system(size: 12))
          .foregroundColor(.secondary)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 16)

        SettingsLink {
          Text("Open Settings")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .simultaneousGesture(TapGesture().onEnded {
          appState.pendingSettingsSection = .telegram
        })
      } else {
        Text("Telegram Bot ready")
          .font(.headline)

        Text("Select a working directory to start the bot.")
          .font(.system(size: 12))
          .foregroundColor(.secondary)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 16)

        Button("Start Bot") {
          startBotWithBestDirectory()
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        // TODO: Re-enable after the Telegram bot start approach is clarified.
        .disabled(true)
      }

      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func startBotWithBestDirectory() {
    let config = configManager.config

    if let path = config.telegramRootDirectoryPath {
      appState.startTelegramBot(
        directory: URL(fileURLWithPath: path),
        startImmediately: true
      )
    } else if let dir = appState.globalWorkingDirectory ?? appState.activeTab?.workingDirectory {
      appState.startTelegramBot(directory: dir, startImmediately: true)
    } else {
      appState.startTelegramBot(
        directory: FileManager.default.homeDirectoryForCurrentUser,
        startImmediately: true
      )
    }
  }
}
