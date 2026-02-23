import AppKit
import SwiftUI

/// The startup page for creating new sessions.
/// Replaces the old `AgentSelectionView` with a unified flow:
/// folder selector, launch type picker, prompt picker, and Start button.
struct StartupPageView: View {
  @Environment(AppState.self) private var appState
  @Environment(\.dismiss) private var dismiss

  private let recentFoldersManager = RecentFoldersManager.shared
  private let configManager = ConfigManager.shared
  private let externalAppManager = ExternalAppManager.shared

  @State private var selectedDirectory: URL?
  @State private var selectedLaunchType: LaunchType
  @State private var selectedPromptID: UUID?
  @State private var showFolderSelector = false
  @State private var nativeAuthStatus: [ProviderID: Bool] = [:]

  init() {
    let config = ConfigManager.shared.config
    _selectedLaunchType = State(initialValue: config.lastUsedLaunchType ?? .claudeChat)
  }

  private var savedPrompts: [SavedPrompt] {
    configManager.config.savedPrompts
  }

  /// The directory that will be used for the new session.
  private var currentDirectory: URL {
    selectedDirectory
      ?? appState.globalWorkingDirectory
      ?? recentFoldersManager.recentFolders.first
      ?? FileManager.default.homeDirectoryForCurrentUser
  }

  /// Display path with ~ for home directory.
  private var displayPath: String {
    let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
    let fullPath = currentDirectory.path

    if fullPath.hasPrefix(homeDir) {
      return "~" + fullPath.dropFirst(homeDir.count)
    }

    return fullPath
  }

  /// Whether the selected launch type is currently available.
  private var isLaunchTypeAvailable: Bool {
    launchTypeAvailability(selectedLaunchType)
  }

  /// Whether the Start button should be enabled.
  private var canStart: Bool {
    guard isLaunchTypeAvailable else {
      return false
    }

    guard selectedLaunchType.requiresPredefinedPrompt else {
      return true
    }

    return selectedPrompt?.promptText
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .isEmpty == false
  }

  private var selectedPrompt: SavedPrompt? {
    savedPrompts.find(by: selectedPromptID)
  }

  var body: some View {
    VStack(spacing: 0) {
      header

      Divider()

      ScrollView {
        VStack(spacing: 0) {
          folderSelectorCard
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

          Divider()

          launchTypePicker
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

          Divider()

          promptSection
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 16)
        }
      }

      Divider()

      startButton
        .padding(20)
    }
    .frame(width: 440)
    .fixedSize(horizontal: false, vertical: true)
    .background(appBackgroundColor)
    .task {
      async let anthropicAuth = AgentRuntimeFactory.hasAuth(for: .anthropic)
      async let openAIAuth = AgentRuntimeFactory.hasAuth(for: .openAI)
      nativeAuthStatus[.anthropic] = await anthropicAuth
      nativeAuthStatus[.openAI] = await openAIAuth
    }
    .sheet(isPresented: $showFolderSelector) {
      FolderSelectorSheet(
        currentDirectory: currentDirectory,
        onSelect: { url in
          selectedDirectory = url
          appState.globalWorkingDirectory = url
          recentFoldersManager.addRecentFolder(url)
        }
      )
    }
  }

  // MARK: - Header

  private var header: some View {
    HStack {
      Text("Start New Session")
        .font(.headline)

      Spacer()

      Button {
        dismiss()
      } label: {
        Image(systemName: "xmark.circle.fill")
          .font(.system(size: 20))
          .foregroundColor(.secondary)
      }
      .buttonStyle(.plain)
      .keyboardShortcut(.escape)
    }
    .padding(20)
  }

  // MARK: - Folder Selector Card

  private var folderSelectorCard: some View {
    Button {
      showFolderSelector = true
    } label: {
      HStack(spacing: 12) {
        Image(systemName: "folder.fill")
          .font(.system(size: 24))
          .foregroundColor(.accentColor)

        VStack(alignment: .leading, spacing: 4) {
          Text(currentDirectory.lastPathComponent)
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.primary)

          Text(displayPath)
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
        }

        Spacer()

        Text("Change...")
          .font(.system(size: 12))
          .foregroundColor(.secondary)
      }
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(appCardColor)
      .cornerRadius(10)
      .overlay(
        RoundedRectangle(cornerRadius: 10)
          .strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 1)
      )
    }
    .buttonStyle(.plain)
  }

  // MARK: - Launch Type Picker

  private var launchTypePicker: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("LAUNCH TYPE")
        .font(.system(size: 10, weight: .semibold))
        .foregroundColor(.secondary)

      Menu {
        ForEach(LaunchType.allCases) { launchType in
          let available = launchTypeAvailability(launchType)

          Button {
            selectedLaunchType = launchType
            configManager.config.lastUsedLaunchType = launchType
          } label: {
            HStack {
              Label(launchType.displayName, systemImage: launchType.iconName)

              if !available {
                Text(unavailabilityHint(for: launchType))
              }
            }
          }
          .disabled(!available)
        }
      } label: {
        HStack(spacing: 8) {
          Image(systemName: selectedLaunchType.iconName)
            .font(.system(size: 14))
            .foregroundColor(launchTypeAccentColor(selectedLaunchType))
            .frame(width: 20)

          VStack(alignment: .leading, spacing: 2) {
            Text(selectedLaunchType.displayName)
              .font(.system(size: 12, weight: .medium))
              .foregroundColor(.primary)

            Text(selectedLaunchType.subtitle)
              .font(.system(size: 11))
              .foregroundColor(.secondary)
              .lineLimit(1)
          }

          Spacer()

          if !isLaunchTypeAvailable {
            Text(unavailabilityHint(for: selectedLaunchType))
              .font(.system(size: 10))
              .foregroundColor(.orange)
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .background(Color.orange.opacity(0.1))
              .cornerRadius(4)
          }

          Image(systemName: "chevron.up.chevron.down")
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(appCardColor)
        .cornerRadius(8)
      }
      .menuStyle(.borderlessButton)
      .fixedSize(horizontal: false, vertical: true)
    }
  }

  // MARK: - Prompt Section

  private var promptSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      if selectedLaunchType.requiresPrompt {
        if !savedPrompts.isEmpty {
          PromptPicker(selectedPromptID: $selectedPromptID, savedPrompts: savedPrompts)
        } else {
          disabledPromptHint(text: "No saved prompts. Create prompts in Settings.")
        }
      } else {
        disabledPromptHint(text: "Telegram Bot does not use predefined prompts")
      }
    }
  }

  private func disabledPromptHint(text: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("PROMPT")
        .font(.system(size: 10, weight: .semibold))
        .foregroundColor(.secondary)

      HStack(spacing: 8) {
        Text(text)
          .font(.system(size: 12))
          .foregroundColor(.secondary)

        Spacer()
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(appCardColor.opacity(0.5))
      .cornerRadius(8)
    }
  }

  // MARK: - Start Button

  private var startButton: some View {
    Button {
      handleStart()
    } label: {
      Text("Start")
        .font(.system(size: 14, weight: .semibold))
        .frame(maxWidth: .infinity)
    }
    .buttonStyle(.borderedProminent)
    .controlSize(.large)
    .disabled(!canStart)
  }

  // MARK: - Actions

  private func handleStart() {
    let directory = currentDirectory
    recentFoldersManager.addRecentFolder(directory)
    appState.globalWorkingDirectory = directory
    configManager.config.lastUsedLaunchType = selectedLaunchType

    let prompt = selectedPrompt

    switch selectedLaunchType {
    case .terminal:
      appState.createTab(agent: .terminal, directory: directory, initialPrompt: prompt)

    case .claudeChat:
      appState.createChatTab(agent: .claude, directory: directory, initialPrompt: prompt?.promptText)

    case .opencodeChat:
      appState.createChatTab(agent: .opencode, directory: directory, initialPrompt: prompt?.promptText)

    case .claudeNative:
      appState.createChatTab(
        agent: .nativeAgent,
        directory: directory,
        initialPrompt: prompt?.promptText,
        nativeProviderID: .anthropic
      )

    case .codexNative:
      appState.createChatTab(
        agent: .nativeAgent,
        directory: directory,
        initialPrompt: prompt?.promptText,
        nativeProviderID: .openAI
      )

    case .claudeDesktop:
      guard let prompt,
            !prompt.promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else {
        return
      }

      launchDesktopApp(
        bundleID: "com.anthropic.claudefordesktop",
        directory: directory,
        promptText: prompt.promptText
      )

    case .codexDesktop:
      guard let prompt,
            !prompt.promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else {
        return
      }

      launchDesktopApp(
        bundleID: "com.openai.codex",
        directory: directory,
        promptText: prompt.promptText
      )

    case .telegramBot:
      appState.createTelegramBotTab(directory: directory)
    }

    dismiss()
  }

  private func launchDesktopApp(
    bundleID: String,
    directory: URL,
    promptText: String
  ) {
    guard let app = externalAppManager.knownApps.first(where: { $0.id == bundleID }) else {
      return
    }

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(promptText, forType: .string)

    externalAppManager.openDirectory(directory, in: app)
  }

  // MARK: - Availability

  private func launchTypeAvailability(_ launchType: LaunchType) -> Bool {
    switch launchType {
    case .terminal:
      return true

    case .claudeChat:
      return AgentFactory.createAgent(for: .claude).isAvailable()

    case .opencodeChat:
      return AgentFactory.createAgent(for: .opencode).isAvailable()

    case .claudeNative:
      return nativeAuthStatus[.anthropic] ?? false

    case .codexNative:
      return nativeAuthStatus[.openAI] ?? false

    case .claudeDesktop:
      return externalAppManager.knownApps
        .first(where: { $0.id == "com.anthropic.claudefordesktop" })?.isInstalled ?? false

    case .codexDesktop:
      return externalAppManager.knownApps
        .first(where: { $0.id == "com.openai.codex" })?.isInstalled ?? false

    case .telegramBot:
      let config = configManager.config
      return config.telegramBotToken != nil && config.telegramAllowedUserID != nil
    }
  }

  private func unavailabilityHint(for launchType: LaunchType) -> String {
    switch launchType {
    case .terminal:
      return ""

    case .claudeChat, .opencodeChat:
      return "CLI not found"

    case .claudeNative, .codexNative:
      return "No API key or OAuth"

    case .claudeDesktop, .codexDesktop:
      return "Not installed"

    case .telegramBot:
      return "Not configured"
    }
  }

  private func launchTypeAccentColor(_ launchType: LaunchType) -> Color {
    switch launchType {
    case .terminal:
      return .secondary

    case .claudeChat, .claudeDesktop:
      return Color(red: 0.85, green: 0.47, blue: 0.34)

    case .claudeNative:
      return Color(red: 0.85, green: 0.47, blue: 0.34)

    case .codexNative:
      return .purple

    case .opencodeChat:
      return Color(red: 0.29, green: 0.78, blue: 0.49)

    case .codexDesktop:
      return .purple

    case .telegramBot:
      return Color(red: 0.33, green: 0.67, blue: 0.91)
    }
  }
}

// MARK: - Folder Selector Sheet

/// A sheet for selecting a working directory from recent folders or the system browser.
private struct FolderSelectorSheet: View {
  let currentDirectory: URL
  let onSelect: (URL) -> Void

  @Environment(\.dismiss) private var dismiss
  private let recentFoldersManager = RecentFoldersManager.shared

  var body: some View {
    VStack(spacing: 0) {
      /// Header.
      HStack {
        Text("Select Working Directory")
          .font(.headline)

        Spacer()

        Button {
          dismiss()
        } label: {
          Image(systemName: "xmark.circle.fill")
            .font(.system(size: 20))
            .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
      }
      .padding(20)

      Divider()

      /// Recent folders.
      if !recentFoldersManager.recentFolders.isEmpty {
        VStack(alignment: .leading, spacing: 12) {
          Text("RECENT FOLDERS")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.secondary)

          VStack(spacing: 4) {
            ForEach(recentFoldersManager.recentFolders.prefix(8), id: \.path) { folder in
              RecentFolderButton(
                folder: folder,
                accentColor: .accentColor,
                onSelect: {
                  onSelect(folder)
                  dismiss()
                },
                onRemove: {
                  recentFoldersManager.removeRecentFolder(folder)
                }
              )
            }
          }
        }
        .padding(20)

        Divider()
      }

      /// Browse button.
      VStack(spacing: 16) {
        if recentFoldersManager.recentFolders.isEmpty {
          VStack(spacing: 12) {
            Image(systemName: "folder.badge.plus")
              .font(.system(size: 40))
              .foregroundColor(.secondary)

            Text("No recent folders")
              .font(.subheadline)
              .foregroundColor(.secondary)
          }
          .padding(.vertical, 20)
        }

        Button {
          openSystemFolderPicker()
        } label: {
          HStack {
            Image(systemName: "folder")
            Text("Browse...")
          }
          .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
      }
      .padding(20)

      Divider()

      /// Footer.
      HStack {
        Button("Cancel") {
          dismiss()
        }
        .keyboardShortcut(.escape)

        Spacer()
      }
      .padding(16)
    }
    .frame(width: 400)
    .fixedSize(horizontal: false, vertical: true)
    .background(appBackgroundColor)
  }

  private func openSystemFolderPicker() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true
    panel.message = "Select a working directory"
    panel.prompt = "Select"
    panel.directoryURL = currentDirectory

    panel.begin { response in
      if response == .OK, let url = panel.url {
        onSelect(url)
        dismiss()
      }
    }
  }
}

#Preview {
  StartupPageView()
    .environment(AppState())
}
