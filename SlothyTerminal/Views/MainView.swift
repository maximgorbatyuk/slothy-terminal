import AppKit
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
          SidebarContainerView()
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

          SidebarContainerView()
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
    .onAppear {
      updateWindowTitle()
    }
    .onChange(of: appState.activeTabID) {
      updateWindowTitle()
    }
    .onChange(of: appState.tabs.count) {
      updateWindowTitle()
    }
  }

  /// Window title pattern: `📁 <directory> | Slothy Terminal`.
  private func updateWindowTitle() {
    let title = windowTitleText

    if let window = NSApplication.shared.mainWindow ?? NSApplication.shared.windows.first {
      window.title = title
      window.titleVisibility = .visible
    }
  }

  private var windowTitleText: String {
    if let activeTab = appState.activeTab {
      let directory = activeTab.workingDirectory.lastPathComponent
      return "📁 \(directory) | Slothy Terminal"
    }

    return "Slothy Terminal"
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

    case .chatFolderSelector(let agent):
      FolderSelectorModal(agent: agent) { selectedDirectory, selectedPrompt in
        appState.createChatTab(agent: agent, directory: selectedDirectory, initialPrompt: selectedPrompt?.promptText)
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
    VStack(spacing: 0) {
      /// Header.
      HStack {
        Text("Open new tab")
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

      Divider()

      /// Directory selection.
      VStack(alignment: .leading, spacing: 8) {
        Text("WORKING DIRECTORY")
          .font(.system(size: 10, weight: .semibold))
          .foregroundColor(.secondary)

        HStack(spacing: 12) {
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
      .padding(.horizontal, 20)
      .padding(.top, 16)
      .padding(.bottom, 12)

      if !savedPrompts.isEmpty {
        PromptPicker(selectedPromptID: $selectedPromptID, savedPrompts: savedPrompts)
          .padding(.horizontal, 20)
          .padding(.bottom, 12)
      }

      Divider()

      /// Tab type list.
      VStack(spacing: 8) {
        /// Chat mode buttons for agents that support it.
        ForEach(AgentType.allCases.filter(\.supportsChatMode)) { agent in
          TabTypeButton(chatAgent: agent) {
            createChatTab(agent: agent)
          }
        }

        /// TUI/terminal mode buttons.
        ForEach(AgentType.allCases) { agent in
          TabTypeButton(agentType: agent) {
            createTab(agent: agent)
          }
        }
      }
      .padding(20)
    }
    .frame(width: 400)
    .background(appBackgroundColor)
  }

  /// Creates a chat tab with the selected directory and agent.
  private func createChatTab(agent: AgentType = .claude) {
    recentFoldersManager.addRecentFolder(currentDirectory)
    let prompt = savedPrompts.find(by: selectedPromptID)
    appState.createChatTab(agent: agent, directory: currentDirectory, initialPrompt: prompt?.promptText)
    dismiss()
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
      Task { @MainActor in
        if response == .OK, let url = panel.url {
          selectedDirectory = url
        }
      }
    }
  }
}

/// Button row for creating a new tab of a given type.
struct TabTypeButton: View {
  let icon: String
  let title: String
  let subtitle: String
  let accentColor: Color
  let showBadge: Bool
  let checkAvailability: () -> Bool
  let action: () -> Void

  @State private var isAvailable = true

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Image(systemName: icon)
          .font(.system(size: 20))
          .foregroundColor(accentColor)
          .frame(width: 32)

        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(.system(size: 14, weight: .medium))

          Text(subtitle)
            .font(.system(size: 11))
            .foregroundColor(.secondary)
        }

        Spacer()

        if showBadge && !isAvailable {
          Text("Not installed")
            .font(.system(size: 10))
            .foregroundColor(.orange)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(4)
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(appCardColor)
      .cornerRadius(8)
    }
    .buttonStyle(.plain)
    .disabled(!isAvailable)
    .opacity(isAvailable ? 1.0 : 0.7)
    .onAppear {
      isAvailable = checkAvailability()
    }
  }

  /// Creates a button for an agent-based tab.
  init(agentType: AgentType, action: @escaping () -> Void) {
    self.icon = agentType.iconName
    self.title = "New \(agentType.rawValue) Tab"
    self.subtitle = agentType.description
    self.accentColor = agentType.accentColor
    self.showBadge = agentType != .terminal
    self.checkAvailability = { AgentFactory.createAgent(for: agentType).isAvailable() }
    self.action = action
  }

  /// Creates a button for a chat tab with the specified agent.
  init(chatAgent agent: AgentType, action: @escaping () -> Void) {
    self.icon = "bubble.left.and.bubble.right"
    self.title = "New \(agent.rawValue) Chat"
    self.subtitle = "Chat interface for \(agent.rawValue)"
    self.accentColor = agent.accentColor
    self.showBadge = true
    self.checkAvailability = { AgentFactory.createAgent(for: agent).isAvailable() }
    self.action = action
  }
}

#Preview {
  MainView()
    .environment(AppState())
}
