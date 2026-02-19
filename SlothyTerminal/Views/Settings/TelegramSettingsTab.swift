import SwiftUI

/// Settings tab for Telegram bot configuration.
struct TelegramSettingsTab: View {
  private var configManager = ConfigManager.shared

  @State private var connectionStatus: String?
  @State private var isCheckingConnection = false

  var body: some View {
    Form {
      Section("Bot Credentials") {
        SecureField(
          "Bot Token",
          text: Binding(
            get: { configManager.config.telegramBotToken ?? "" },
            set: { configManager.config.telegramBotToken = $0.isEmpty ? nil : $0 }
          ),
          prompt: Text("123456:ABC-DEF...")
        )
        .textFieldStyle(.roundedBorder)

        HStack {
          TextField(
            "Allowed User ID",
            value: Binding(
              get: { configManager.config.telegramAllowedUserID },
              set: { configManager.config.telegramAllowedUserID = $0 }
            ),
            format: .number,
            prompt: Text("Your Telegram user ID")
          )
          .textFieldStyle(.roundedBorder)

          Button(isCheckingConnection ? "Checking..." : "Test Connection") {
            Task {
              await checkConnection()
            }
          }
          .disabled(
            configManager.config.telegramBotToken == nil
            || configManager.config.telegramBotToken?.isEmpty == true
            || isCheckingConnection
          )
        }

        if let status = connectionStatus {
          Text(status)
            .font(.caption)
            .foregroundColor(status.hasPrefix("Connected") ? .green : .red)
        }

        Text("Get a token from @BotFather. Find your user ID via @userinfobot.")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Section("Execution") {
        Picker("Execution agent", selection: Bindable(configManager).config.telegramExecutionAgent) {
          Text("Claude").tag(AgentType.claude)
          Text("OpenCode").tag(AgentType.opencode)
        }
        .pickerStyle(.segmented)

        Text("Agent used to run prompts received from Telegram.")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Section("Behavior") {
        Toggle(
          "Auto-start when tab opens",
          isOn: Bindable(configManager).config.telegramAutoStartOnOpen
        )

        Picker("Default mode", selection: Bindable(configManager).config.telegramDefaultListenMode) {
          Text("Execute").tag(TelegramBotMode.execute)
          Text("Listen Only").tag(TelegramBotMode.passive)
        }
        .pickerStyle(.segmented)

        TextField(
          "Reply prefix (optional)",
          text: Binding(
            get: { configManager.config.telegramReplyPrefix ?? "" },
            set: { configManager.config.telegramReplyPrefix = $0.isEmpty ? nil : $0 }
          ),
          prompt: Text("e.g. [SlothyBot]")
        )
        .textFieldStyle(.roundedBorder)
      }

      Section("Open Directory") {
        TextField(
          "Root directory",
          text: Binding(
            get: { configManager.config.telegramRootDirectoryPath ?? "" },
            set: { configManager.config.telegramRootDirectoryPath = $0.isEmpty ? nil : $0 }
          ),
          prompt: Text("~/projects")
        )
        .textFieldStyle(.roundedBorder)

        TextField(
          "Default subfolder",
          text: Binding(
            get: { configManager.config.telegramPredefinedOpenSubpath ?? "" },
            set: { configManager.config.telegramPredefinedOpenSubpath = $0.isEmpty ? nil : $0 }
          ),
          prompt: Text("e.g. my-repo")
        )
        .textFieldStyle(.roundedBorder)

        Picker("Tab mode", selection: Bindable(configManager).config.telegramOpenDirectoryTabMode) {
          Text("Chat").tag(TabMode.chat)
          Text("Terminal").tag(TabMode.terminal)
        }
        .pickerStyle(.segmented)

        Picker("Agent", selection: Bindable(configManager).config.telegramOpenDirectoryAgent) {
          Text("Claude").tag(AgentType.claude)
          Text("OpenCode").tag(AgentType.opencode)
        }
        .pickerStyle(.segmented)

        Text("Configures the tab opened by the /open-directory command.")
          .font(.caption)
          .foregroundColor(.secondary)
      }
    }
    .formStyle(.grouped)
    .scrollContentBackground(.hidden)
    .padding()
    .background(appBackgroundColor)
  }

  private func checkConnection() async {
    guard let token = configManager.config.telegramBotToken,
          !token.isEmpty
    else {
      connectionStatus = "No token configured"
      return
    }

    isCheckingConnection = true
    connectionStatus = nil

    let client = TelegramBotAPIClient(token: token)
    do {
      let botInfo = try await client.getMe()
      let name = botInfo.username ?? botInfo.firstName
      connectionStatus = "Connected as @\(name)"
    } catch {
      connectionStatus = "Failed: \(error.localizedDescription)"
    }

    isCheckingConnection = false
  }
}
