import SwiftUI

/// Settings tab for the native agent system.
///
/// Provides:
/// - Master toggle for native agent mode
/// - Per-provider API key entry with connection status
/// - Default provider and model selection
struct NativeAgentSettingsTab: View {
  private var configManager = ConfigManager.shared

  /// Ephemeral API key fields — stored to Keychain on commit, not in AppConfig.
  @State private var anthropicKey = ""
  @State private var openAIKey = ""
  @State private var zaiKey = ""

  /// Auth status per provider.
  @State private var anthropicStatus: AuthStatus = .disconnected
  @State private var openAIStatus: AuthStatus = .disconnected
  @State private var zaiStatus: AuthStatus = .disconnected

  @State private var isLoading = false

  private let tokenStore: TokenStore = KeychainTokenStore()

  var body: some View {
    Form {
      Section("Native Agent") {
        Toggle(
          "Enable native agent mode",
          isOn: Bindable(configManager).config.nativeAgentEnabled
        )

        Text(
          "When enabled, chat mode communicates directly with LLM provider APIs "
          + "instead of using CLI subprocesses. Requires an API key for the selected provider."
        )
        .font(.caption)
        .foregroundColor(.secondary)
      }

      Section("Provider Credentials") {
        ProviderAuthRow(
          providerName: "Anthropic (Claude)",
          providerIcon: "brain.head.profile",
          apiKeyBinding: $anthropicKey,
          authStatus: anthropicStatus
        )

        Divider()

        ProviderAuthRow(
          providerName: "OpenAI (Codex)",
          providerIcon: "cpu",
          apiKeyBinding: $openAIKey,
          authStatus: openAIStatus
        )

        Divider()

        ProviderAuthRow(
          providerName: "Z.AI (GLM)",
          providerIcon: "globe.asia.australia",
          apiKeyBinding: $zaiKey,
          authStatus: zaiStatus
        )

        HStack {
          Spacer()

          Button(isLoading ? "Saving..." : "Save Credentials") {
            Task {
              await saveCredentials()
            }
          }
          .disabled(isLoading)
        }
        .padding(.top, 4)

        Text("API keys are stored securely in the macOS Keychain.")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Section("Defaults") {
        Picker(
          "Default Provider",
          selection: Binding(
            get: { configManager.config.nativeDefaultProvider ?? "anthropic" },
            set: { configManager.config.nativeDefaultProvider = $0 }
          )
        ) {
          Text("Anthropic").tag("anthropic")
          Text("OpenAI").tag("openai")
          Text("Z.AI").tag("zai")
        }

        TextField(
          "Default Model",
          text: Binding(
            get: { configManager.config.nativeDefaultModel ?? "" },
            set: { configManager.config.nativeDefaultModel = $0.isEmpty ? nil : $0 }
          ),
          prompt: Text("e.g. claude-sonnet-4-6")
        )
        .textFieldStyle(.roundedBorder)

        Text("Provider and model used when starting a new native chat session.")
          .font(.caption)
          .foregroundColor(.secondary)
      }
    }
    .formStyle(.grouped)
    .scrollContentBackground(.hidden)
    .padding()
    .background(appBackgroundColor)
    .task {
      await loadCredentials()
    }
  }

  // MARK: - Credential Management

  private func loadCredentials() async {
    anthropicStatus = await statusFor(.anthropic)
    openAIStatus = await statusFor(.openAI)
    zaiStatus = await statusFor(.zai)

    /// Pre-fill key fields with masked indicator if credentials exist.
    if case .connected = anthropicStatus {
      anthropicKey = ""
    }
    if case .connected = openAIStatus {
      openAIKey = ""
    }
    if case .connected = zaiStatus {
      zaiKey = ""
    }
  }

  private func saveCredentials() async {
    isLoading = true
    defer { isLoading = false }

    await saveKeyIfNeeded(anthropicKey, provider: .anthropic)
    await saveKeyIfNeeded(openAIKey, provider: .openAI)
    await saveKeyIfNeeded(zaiKey, provider: .zai)

    /// Refresh statuses.
    anthropicStatus = await statusFor(.anthropic)
    openAIStatus = await statusFor(.openAI)
    zaiStatus = await statusFor(.zai)
  }

  private func saveKeyIfNeeded(_ key: String, provider: ProviderID) async {
    let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !trimmed.isEmpty else {
      return
    }

    do {
      try await tokenStore.save(provider: provider, auth: .apiKey(trimmed))
    } catch {
      /// Status will be refreshed after save completes.
    }
  }

  private func statusFor(_ provider: ProviderID) async -> AuthStatus {
    do {
      if let auth = try await tokenStore.load(provider: provider) {
        switch auth {
        case .apiKey:
          return .connected

        case .oauth(let token):
          if token.expiresAt > Date() {
            return .connected
          }
          return .error("Token expired")
        }
      }
      return .disconnected
    } catch {
      return .error(error.localizedDescription)
    }
  }
}
