import AppKit
import SwiftUI

/// Shared presentation modes for the start-session flow.
enum StartSessionPresentation {
  case modal
  case embedded
}

/// Reusable session launcher content used in both the modal and empty state.
struct StartSessionContentView: View {
  @Environment(AppState.self) private var appState

  let presentation: StartSessionPresentation
  let onStart: () -> Void

  private let recentFoldersManager = RecentFoldersManager.shared
  private let configManager = ConfigManager.shared

  @State private var selectedDirectory: URL?
  @State private var selectedLaunchType: LaunchType
  @State private var selectedPromptID: UUID?
  @State private var showFolderSelector = false

  /// OpenCode-specific startup options.
  @State private var openCodeMode: ChatMode
  @State private var openCodeModel: ChatModelSelection?
  @State private var openCodeModelOptions: [ChatModelSelection] = []
  @State private var isModelPickerPresented = false

  init(
    presentation: StartSessionPresentation,
    onStart: @escaping () -> Void = {}
  ) {
    self.presentation = presentation
    self.onStart = onStart

    let config = ConfigManager.shared.config
    _selectedLaunchType = State(initialValue: config.lastUsedLaunchType ?? .claudeChat)
    _openCodeMode = State(initialValue: config.lastUsedOpenCodeMode ?? .build)
    _openCodeModel = State(initialValue: config.lastUsedOpenCodeModel)
  }

  private var savedPrompts: [SavedPrompt] {
    configManager.config.savedPrompts
  }

  /// The directory that will be used for the new session.
  private var currentDirectory: URL {
    selectedDirectory
      ?? appState.preferredNewSessionDirectory
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

  private var embeddedWidth: CGFloat {
    640
  }

  private var horizontalPadding: CGFloat {
    switch presentation {
    case .modal:
      return 20

    case .embedded:
      return 24
    }
  }

  private var sectionSpacing: CGFloat {
    switch presentation {
    case .modal:
      return 0

    case .embedded:
      return 16
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      if presentation == .embedded {
        embeddedHeader
          .padding(.horizontal, horizontalPadding)
          .padding(.top, 28)
          .padding(.bottom, 20)
      }

      ScrollView {
        VStack(spacing: sectionSpacing) {
          folderSelectorCard
            .padding(.horizontal, horizontalPadding)
            .padding(.top, presentation == .modal ? 20 : 0)
            .padding(.bottom, presentation == .modal ? 16 : 0)

          sectionDivider

          launchTypePicker
            .padding(.horizontal, horizontalPadding)
            .padding(.top, presentation == .modal ? 16 : 0)
            .padding(.bottom, presentation == .modal ? 12 : 0)

          sectionDivider

          if selectedLaunchType == .opencode {
            openCodeOptionsSection
              .padding(.horizontal, horizontalPadding)
              .padding(.top, presentation == .modal ? 16 : 0)
              .padding(.bottom, presentation == .modal ? 12 : 0)

            sectionDivider
          }

          if selectedLaunchType.requiresPrompt {
            promptSection
              .padding(.horizontal, horizontalPadding)
              .padding(.top, presentation == .modal ? 16 : 0)
              .padding(.bottom, presentation == .modal ? 16 : 0)
          }
        }
        .frame(maxWidth: embeddedWidth)
        .frame(maxWidth: .infinity)
      }

      sectionDivider

      startButton
        .frame(maxWidth: embeddedWidth)
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, 20)
    }
    .background(containerBackground)
    .clipShape(RoundedRectangle(cornerRadius: presentation == .embedded ? 18 : 0))
    .overlay {
      if presentation == .embedded {
        RoundedRectangle(cornerRadius: 18)
          .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
      }
    }
    .frame(maxWidth: presentation == .embedded ? 760 : .infinity)
    .task(id: selectedLaunchType) {
      guard selectedLaunchType == .opencode else {
        return
      }

      let models = await Task.detached {
        OpenCodeCLIService.loadModels()
      }.value

      openCodeModelOptions = models
    }
    .onChange(of: openCodeMode) { _, newValue in
      configManager.config.lastUsedOpenCodeMode = newValue
    }
    .onChange(of: openCodeModel) { _, newValue in
      configManager.config.lastUsedOpenCodeModel = newValue
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

  private var embeddedHeader: some View {
    VStack(spacing: 10) {
      Image(systemName: "play.square.stack.fill")
        .font(.system(size: 36))
        .foregroundColor(.accentColor)

      Text("Start Session")
        .font(.title2)
        .fontWeight(.semibold)

      Text("Choose a folder, pick how you want to work, and launch your first session.")
        .font(.subheadline)
        .foregroundColor(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 420)
    }
    .frame(maxWidth: .infinity)
  }

  @ViewBuilder
  private var sectionDivider: some View {
    switch presentation {
    case .modal:
      Divider()

    case .embedded:
      EmptyView()
    }
  }

  private var containerBackground: some View {
    Group {
      switch presentation {
      case .modal:
        appBackgroundColor

      case .embedded:
        appCardColor
      }
    }
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
      .background(appBackgroundColor)
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
    VStack(alignment: .leading, spacing: 12) {
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
            HStack(spacing: 10) {
              Image(systemName: launchType.iconName)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 18)

              VStack(alignment: .leading, spacing: 2) {
                Text(launchType.displayName)
                  .font(.system(size: 12, weight: .semibold))

                Text(launchType.subtitle)
                  .font(.system(size: 10))
                  .foregroundColor(.secondary)
                  .lineLimit(1)
              }

              if !available {
                Text(unavailabilityHint(for: launchType))
                  .font(.system(size: 10, weight: .medium))
                  .foregroundColor(.orange)
              }
            }
          }
          .disabled(!available)
        }
      } label: {
        VStack(alignment: .leading, spacing: 10) {
          HStack(alignment: .top, spacing: 10) {
            Image(systemName: selectedLaunchType.iconName)
              .font(.system(size: 20, weight: .semibold))
              .foregroundColor(launchTypeAccentColor(selectedLaunchType))
              .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 3) {
              Text(selectedLaunchType.displayName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)

              Text(selectedLaunchType.subtitle)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.up.chevron.down")
              .font(.system(size: 10, weight: .semibold))
              .foregroundColor(.secondary)
          }

          if !isLaunchTypeAvailable {
            HStack(spacing: 4) {
              Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundColor(.orange)

              Text(unavailabilityHint(for: selectedLaunchType))
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.orange)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(6)
          }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .background(appBackgroundColor)
        .overlay(
          RoundedRectangle(cornerRadius: 10)
            .stroke(launchTypeAccentColor(selectedLaunchType).opacity(0.35), lineWidth: 1)
        )
        .cornerRadius(10)
      }
      .menuStyle(.borderlessButton)
      .fixedSize(horizontal: false, vertical: true)
    }
  }

  // MARK: - OpenCode Options

  private var openCodeOptionsSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("OPENCODE OPTIONS")
        .font(.system(size: 10, weight: .semibold))
        .foregroundColor(.secondary)

      HStack(spacing: 8) {
        Text("Mode")
          .font(.system(size: 12))
          .foregroundColor(.secondary)

        Picker("", selection: $openCodeMode) {
          ForEach(ChatMode.allCases, id: \.self) { mode in
            Text(mode.displayName).tag(mode)
          }
        }
        .pickerStyle(.segmented)
        .frame(width: 160)

        Spacer()
      }

      HStack(spacing: 8) {
        Text("Model")
          .font(.system(size: 12))
          .foregroundColor(.secondary)

        if openCodeModelOptions.isEmpty {
          Text("Loading models...")
            .font(.system(size: 12))
            .foregroundColor(.secondary.opacity(0.6))
        } else {
          Button {
            isModelPickerPresented.toggle()
          } label: {
            HStack(spacing: 4) {
              Text(openCodeModel?.displayName ?? "Default")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)

              Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(appBackgroundColor)
            .cornerRadius(6)
          }
          .buttonStyle(.plain)
          .fixedSize()
          .popover(isPresented: $isModelPickerPresented) {
            ModelPicker(
              models: openCodeModelOptions,
              selectedModel: $openCodeModel,
              isPresented: $isModelPickerPresented
            )
          }
        }

        Spacer()
      }
    }
  }

  // MARK: - Prompt Section

  private var promptSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      if !savedPrompts.isEmpty {
        PromptPicker(selectedPromptID: $selectedPromptID, savedPrompts: savedPrompts)
      } else {
        disabledPromptHint(text: "No saved prompts. Create prompts in Settings.")
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
      .background(appBackgroundColor.opacity(0.5))
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
    .keyboardShortcut(.defaultAction)
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

    case .claude:
      appState.createTab(agent: .claude, directory: directory, initialPrompt: prompt)

    case .opencode:
      var args: [String] = []

      if let model = openCodeModel {
        args += ["--model", model.cliModelString]
      }

      if openCodeMode == .plan {
        args += ["--agent", "plan"]
      }

      if let promptText = prompt?.promptText.trimmingCharacters(in: .whitespacesAndNewlines),
         !promptText.isEmpty
      {
        args += ["--prompt", promptText]
      }

      configManager.config.lastUsedOpenCodeMode = openCodeMode
      configManager.config.lastUsedOpenCodeModel = openCodeModel

      if args.isEmpty {
        appState.createTab(agent: .opencode, directory: directory, initialPrompt: prompt)
      } else {
        appState.createTab(
          agent: .opencode,
          directory: directory,
          initialPrompt: prompt,
          launchArgumentsOverride: args
        )
      }

    case .claudeChat:
      appState.createChatTab(agent: .claude, directory: directory, initialPrompt: prompt?.promptText)

    case .opencodeChat:
      appState.createChatTab(agent: .opencode, directory: directory, initialPrompt: prompt?.promptText)

    case .gitClient:
      appState.createGitTab(directory: directory)
    }

    onStart()
  }

  // MARK: - Availability

  private func launchTypeAvailability(_ launchType: LaunchType) -> Bool {
    switch launchType {
    case .terminal, .gitClient:
      return true

    case .claude, .claudeChat:
      return AgentFactory.createAgent(for: .claude).isAvailable()

    case .opencode, .opencodeChat:
      return AgentFactory.createAgent(for: .opencode).isAvailable()
    }
  }

  private func unavailabilityHint(for launchType: LaunchType) -> String {
    switch launchType {
    case .terminal, .gitClient:
      return ""

    case .claude, .opencode, .claudeChat, .opencodeChat:
      return "CLI not found"
    }
  }

  private func launchTypeAccentColor(_ launchType: LaunchType) -> Color {
    switch launchType {
    case .terminal:
      return .secondary

    case .claude, .claudeChat:
      return Color(red: 0.85, green: 0.47, blue: 0.34)

    case .opencode, .opencodeChat:
      return Color(red: 0.29, green: 0.78, blue: 0.49)

    case .gitClient:
      return Color(red: 0.95, green: 0.55, blue: 0.15)
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

#Preview("Embedded") {
  StartSessionContentView(presentation: .embedded)
    .padding(24)
    .frame(width: 860, height: 720)
    .background(appBackgroundColor)
    .environment(AppState())
}
