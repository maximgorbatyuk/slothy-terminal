import SwiftUI

/// Settings tab for configuring usage stats.
struct UsageSettingsTab: View {
  private var configManager = ConfigManager.shared
  private var usageService = UsageService.shared

  @State private var showClearConfirmation = false
  @State private var showImportSheet = false
  @State private var importSessionKey = ""
  @State private var importProvider: UsageProvider = .claude

  var body: some View {
    Form {
      Section("Usage Statistics") {
        Toggle("Enable usage stats", isOn: Binding(
          get: { configManager.config.usagePreferences.isEnabled },
          set: { newValue in
            configManager.config.usagePreferences.isEnabled = newValue

            if newValue {
              usageService.startIfEnabled()
            } else {
              usageService.stopAll()
            }
          }
        ))

        Text(
          "When enabled, SlothyTerminal fetches usage data directly from provider APIs. "
          + "Stats appear in the status bar."
        )
        .font(.system(size: 11))
        .foregroundColor(.secondary)
      }

      if configManager.config.usagePreferences.isEnabled {
        Section("Auth Sources") {
          authSourcesView()
        }

        Section("Experimental Sources") {
          Toggle("Enable experimental/private sources", isOn: Binding(
            get: { configManager.config.usagePreferences.enableExperimentalSources },
            set: { newValue in
              configManager.config.usagePreferences.enableExperimentalSources = newValue
              usageService.startIfEnabled()
            }
          ))

          Text(
            "Experimental sources use undocumented or private provider endpoints. "
            + "They may break without warning and require explicit opt-in."
          )
          .font(.system(size: 11))
          .foregroundColor(.secondary)

          if configManager.config.usagePreferences.enableExperimentalSources {
            Button("Import Browser Session...") {
              showImportSheet = true
            }
          }
        }

        Section("Refresh") {
          Picker("Auto-refresh interval", selection: Binding(
            get: { configManager.config.usagePreferences.refreshIntervalSeconds },
            set: { newValue in
              configManager.config.usagePreferences.refreshIntervalSeconds = newValue
              usageService.startIfEnabled()
            }
          )) {
            Text("1 minute").tag(60)
            Text("5 minutes").tag(300)
            Text("15 minutes").tag(900)
            Text("30 minutes").tag(1800)
            Text("Manual only").tag(0)
          }
          .pickerStyle(.menu)
        }

        Section("Data") {
          Button("Clear All Cached Data") {
            showClearConfirmation = true
          }

          Button("Remove Imported Auth Material") {
            UsageKeychainStore.deleteAll()
            usageService.clearAll()
          }
          .foregroundColor(.red)
        }
      }
    }
    .formStyle(.grouped)
    .alert("Clear Usage Data", isPresented: $showClearConfirmation) {
      Button("Cancel", role: .cancel) {}

      Button("Clear", role: .destructive) {
        usageService.clearAll()
      }
    } message: {
      Text(
        "This will clear all cached usage data and imported auth material. "
        + "You can re-enable and re-import later."
      )
    }
    .sheet(isPresented: $showImportSheet, onDismiss: {
      importSessionKey = ""
    }) {
      importSessionSheet()
    }
  }

  @ViewBuilder
  private func authSourcesView() -> some View {
    ForEach(UsageProvider.allCases, id: \.self) { provider in
      if let source = usageService.authSource(for: provider) {
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text(provider.displayName)
              .font(.system(size: 12, weight: .medium))

            Text(source.label)
              .font(.system(size: 11))
              .foregroundColor(.secondary)

            if let detail = source.detail {
              Text(detail)
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.7))
            }
          }

          Spacer()

          if source.isExperimental {
            Text("Experimental")
              .font(.system(size: 9, weight: .medium))
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .background(Color.orange.opacity(0.2))
              .foregroundColor(.orange)
              .cornerRadius(4)
          } else {
            Image(systemName: "checkmark.circle.fill")
              .foregroundColor(.green)
              .font(.system(size: 14))
          }
        }
      } else {
        HStack {
          Text(provider.displayName)
            .font(.system(size: 12, weight: .medium))

          Spacer()

          Text("No source")
            .font(.system(size: 11))
            .foregroundColor(.secondary)
        }
      }
    }
  }

  @ViewBuilder
  private func importSessionSheet() -> some View {
    VStack(spacing: 16) {
      Text("Import Browser Session")
        .font(.headline)

      Text(
        "Paste a session key from your browser. "
        + "It will be stored securely in Keychain."
      )
      .font(.system(size: 12))
      .foregroundColor(.secondary)
      .multilineTextAlignment(.center)

      Picker("Provider", selection: $importProvider) {
        ForEach(UsageProvider.allCases, id: \.self) { provider in
          Text(provider.displayName).tag(provider)
        }
      }
      .pickerStyle(.segmented)

      SecureField("Session key", text: $importSessionKey)
        .textFieldStyle(.roundedBorder)

      HStack {
        Button("Cancel") {
          showImportSheet = false
          importSessionKey = ""
        }

        Spacer()

        Button("Import") {
          let trimmed = importSessionKey
            .trimmingCharacters(in: .whitespacesAndNewlines)

          // Reject empty or values with control characters (header injection).
          guard !trimmed.isEmpty,
                !trimmed.contains(where: { $0.isNewline || $0 == "\r" })
          else {
            return
          }

          UsageKeychainStore.saveString(
            trimmed,
            provider: importProvider,
            sourceKind: .browser
          )

          importSessionKey = ""
          showImportSheet = false
          usageService.startIfEnabled()
        }
        .buttonStyle(.borderedProminent)
      }
    }
    .padding(24)
    .frame(width: 400)
  }
}
