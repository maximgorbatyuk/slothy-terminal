import SwiftUI

/// The main application view containing the tab bar, terminal, and sidebar.
struct MainView: View {
  @Environment(AppState.self) private var appState

  var body: some View {
    @Bindable var appState = appState

    VStack(spacing: 0) {
      TabBarView()

      HStack(spacing: 0) {
        /// Terminal container takes remaining space.
        TerminalContainerView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)

        /// Sidebar on the right.
        if appState.isSidebarVisible {
          Divider()

          SidebarView()
            .frame(width: appState.sidebarWidth)
        }
      }
    }
    .frame(minWidth: 800, minHeight: 600)
    .background(Color(.windowBackgroundColor))
    .sheet(item: $appState.activeModal) { modal in
      ModalRouter(modal: modal)
    }
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
      FolderSelectorView(agent: agent)

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

  var body: some View {
    VStack(spacing: 20) {
      Text("Select Agent")
        .font(.headline)

      HStack(spacing: 16) {
        ForEach(AgentType.allCases) { agent in
          Button {
            appState.dismissModal()
            appState.showFolderSelector(for: agent)
          } label: {
            VStack(spacing: 8) {
              Image(systemName: agent.iconName)
                .font(.largeTitle)
              Text(agent.rawValue)
                .font(.caption)
            }
            .frame(width: 100, height: 80)
            .background(agent.accentColor.opacity(0.2))
            .cornerRadius(8)
          }
          .buttonStyle(.plain)
        }
      }

      Button("Cancel") {
        dismiss()
      }
      .keyboardShortcut(.escape)
    }
    .padding(24)
    .frame(width: 300)
  }
}

/// Placeholder for folder selector - will be implemented in Phase 4.
struct FolderSelectorView: View {
  let agent: AgentType
  @Environment(AppState.self) private var appState
  @Environment(\.dismiss) private var dismiss
  @State private var selectedDirectory: URL = FileManager.default.homeDirectoryForCurrentUser

  var body: some View {
    VStack(spacing: 16) {
      Text("Select Working Directory")
        .font(.headline)

      Text("Current: \(selectedDirectory.path)")
        .font(.caption)
        .foregroundColor(.secondary)

      HStack {
        Button("Browse...") {
          let panel = NSOpenPanel()
          panel.canChooseFiles = false
          panel.canChooseDirectories = true
          panel.allowsMultipleSelection = false

          if panel.runModal() == .OK,
             let url = panel.url
          {
            selectedDirectory = url
          }
        }
      }

      HStack {
        Button("Cancel") {
          dismiss()
        }
        .keyboardShortcut(.escape)

        Spacer()

        Button("Select") {
          appState.createTab(agent: agent, directory: selectedDirectory)
          dismiss()
        }
        .keyboardShortcut(.return)
        .buttonStyle(.borderedProminent)
      }
    }
    .padding(24)
    .frame(width: 400)
  }
}

#Preview {
  MainView()
    .environment(AppState())
}
