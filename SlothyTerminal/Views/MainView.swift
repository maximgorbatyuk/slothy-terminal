import SwiftUI

/// The main application view containing the tab bar, terminal, and sidebar.
struct MainView: View {
  @Environment(AppState.self) private var appState
  private var configManager = ConfigManager.shared

  private var sidebarPosition: SidebarPosition {
    configManager.config.sidebarPosition
  }

  var body: some View {
    @Bindable var appState = appState

    VStack(spacing: 0) {
      TabBarView()
        .padding(.horizontal, 8)
        .padding(.top, 8)

      HStack(spacing: 0) {
        /// Sidebar on the left.
        if appState.isSidebarVisible && sidebarPosition == .left {
          SidebarView()
            .frame(width: appState.sidebarWidth)
            .padding(.vertical, 8)
            .padding(.leading, 8)

          Divider()
        }

        /// Terminal container takes remaining space.
        TerminalContainerView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .padding(8)

        /// Sidebar on the right.
        if appState.isSidebarVisible && sidebarPosition == .right {
          Divider()

          SidebarView()
            .frame(width: appState.sidebarWidth)
            .padding(.vertical, 8)
            .padding(.trailing, 8)
        }
      }

      /// Status bar at the bottom.
      StatusBarView()
    }
    .frame(minWidth: 800, minHeight: 600)
    .background(appBackgroundColor)
    .sheet(item: $appState.activeModal) { modal in
      ModalRouter(modal: modal)
    }
  }
}

/// Status bar at the bottom of the window.
struct StatusBarView: View {
  @Environment(AppState.self) private var appState

  /// Current git branch for the active tab's directory.
  @State private var gitBranch: String?

  /// App version from bundle.
  private var appVersion: String {
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
  }

  /// Build number from bundle.
  private var buildNumber: String {
    Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
  }

  /// Whether this is a development build.
  private var isDevelopment: Bool {
    BuildConfig.isDevelopment
  }

  /// The working directory of the active tab.
  private var activeDirectory: URL? {
    appState.activeTab?.workingDirectory
  }

  var body: some View {
    HStack(spacing: 8) {
      /// Git branch on the left.
      if let branch = gitBranch {
        HStack(spacing: 4) {
          Image(systemName: "arrow.triangle.branch")
            .font(.system(size: 9))
          Text(branch)
            .font(.system(size: 10))
        }
        .foregroundColor(.secondary)
      }

      Spacer()

      /// Version info on the right.
      HStack(spacing: 6) {
        Text("v\(appVersion)")
          .font(.system(size: 10))
          .foregroundColor(.secondary)

        if isDevelopment {
          Text("dev")
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(.orange)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Color.orange.opacity(0.2))
            .cornerRadius(3)
        }
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 4)
    .background(appCardColor)
    .task(id: activeDirectory) {
      updateGitBranch()
    }
  }

  /// Updates the git branch for the current directory.
  private func updateGitBranch() {
    guard let directory = activeDirectory else {
      gitBranch = nil
      return
    }

    gitBranch = GitService.shared.getCurrentBranch(in: directory)
  }
}

/// Routes to the appropriate modal view based on the modal type.
struct ModalRouter: View {
  let modal: ModalType
  @Environment(AppState.self) private var appState

  var body: some View {
    switch modal {
    case .newTab(let preselectedAgent):
      AgentSelectionView(preselectedAgent: preselectedAgent)

    case .folderSelector(let agent):
      FolderSelectorModal(agent: agent) { selectedDirectory, selectedPrompt in
        appState.createTab(agent: agent, directory: selectedDirectory, initialPrompt: selectedPrompt)
      }

    case .chatFolderSelector:
      FolderSelectorModal(agent: .claude) { selectedDirectory, selectedPrompt in
        appState.createChatTab(directory: selectedDirectory, initialPrompt: selectedPrompt?.promptText)
      }

    case .settings:
      Text("Settings")
        .frame(width: 500, height: 400)
    }
  }
}

/// View for selecting an AI agent when creating a new tab.
struct AgentSelectionView: View {
  let preselectedAgent: AgentType?
  @Environment(AppState.self) private var appState
  @Environment(\.dismiss) private var dismiss

  private let recentFoldersManager = RecentFoldersManager.shared
  private let configManager = ConfigManager.shared

  /// The currently selected directory.
  @State private var selectedDirectory: URL?

  /// The selected saved prompt ID.
  @State private var selectedPromptID: UUID?

  private var savedPrompts: [SavedPrompt] {
    configManager.config.savedPrompts
  }

  /// The directory that will be used for the new tab.
  private var currentDirectory: URL {
    selectedDirectory ?? recentFoldersManager.recentFolders.first ?? FileManager.default.homeDirectoryForCurrentUser
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

  var body: some View {
    VStack(spacing: 24) {
      Text("Open new tab")
        .font(.headline)

      /// Agent selection row.
      HStack(spacing: 16) {
        ForEach(AgentType.allCases) { agent in
          Button {
            createTab(agent: agent)
          } label: {
            VStack(spacing: 8) {
              Image(systemName: agent.iconName)
                .font(.largeTitle)
                .foregroundColor(agent.accentColor)
              Text(agent.rawValue)
                .font(.caption)
            }
            .frame(width: 100, height: 80)
            .background(appCardColor)
            .cornerRadius(8)
          }
          .buttonStyle(.plain)
        }
      }

      /// Directory selection row.
      VStack(alignment: .leading, spacing: 8) {
        Text("WORKING DIRECTORY")
          .font(.system(size: 10, weight: .semibold))
          .foregroundColor(.secondary)

        HStack(spacing: 12) {
          /// Current directory display.
          HStack(spacing: 8) {
            Image(systemName: "folder.fill")
              .font(.system(size: 14))
              .foregroundColor(.secondary)

            Text(displayPath)
              .font(.system(size: 12))
              .foregroundColor(.primary)
              .lineLimit(1)
              .truncationMode(.middle)
          }
          .frame(maxWidth: .infinity, alignment: .leading)

          /// Change directory button.
          Button {
            openFolderPicker()
          } label: {
            Text("Change...")
              .font(.system(size: 12))
          }
          .buttonStyle(.bordered)
        }
        .padding(12)
        .background(appCardColor)
        .cornerRadius(8)
      }

      if !savedPrompts.isEmpty {
        PromptPicker(selectedPromptID: $selectedPromptID, savedPrompts: savedPrompts)
      }

      Button("Cancel") {
        dismiss()
      }
      .keyboardShortcut(.escape)
    }
    .padding(32)
    .frame(width: 400)
    .background(appBackgroundColor)
  }

  /// Creates a tab with the selected agent and directory.
  private func createTab(agent: AgentType) {
    recentFoldersManager.addRecentFolder(currentDirectory)
    let prompt = agent.supportsInitialPrompt
      ? savedPrompts.find(by: selectedPromptID)
      : nil
    appState.createTab(agent: agent, directory: currentDirectory, initialPrompt: prompt)
    dismiss()
  }

  /// Opens the system folder picker.
  private func openFolderPicker() {
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
        selectedDirectory = url
      }
    }
  }
}

#Preview {
  MainView()
    .environment(AppState())
}
