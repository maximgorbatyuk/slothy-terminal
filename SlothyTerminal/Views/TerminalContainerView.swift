import SwiftUI

/// Container view that displays the active tab's terminal or an empty state.
struct TerminalContainerView: View {
  @Environment(AppState.self) private var appState

  var body: some View {
    Group {
      if let activeTab = appState.activeTab {
        ActiveTerminalView(tab: activeTab)
      } else {
        EmptyTerminalView()
      }
    }
  }
}

/// Displays the terminal for an active tab.
struct ActiveTerminalView: View {
  let tab: Tab
  @State private var ptyController: PTYController?

  var body: some View {
    ZStack {
      Color(.textBackgroundColor)

      if ptyController != nil {
        StandaloneTerminalView(
          workingDirectory: tab.workingDirectory,
          command: tab.agentType.command,
          arguments: []
        )
      } else {
        ProgressView("Starting terminal...")
      }
    }
    .task {
      /// Initialize PTY controller when view appears.
      let controller = PTYController()
      ptyController = controller
      tab.ptyController = controller
    }
  }
}

/// Empty state shown when no tabs are open.
struct EmptyTerminalView: View {
  @Environment(AppState.self) private var appState

  var body: some View {
    VStack(spacing: 24) {
      Image(systemName: "terminal")
        .font(.system(size: 64))
        .foregroundColor(.secondary)

      Text("No Terminal Open")
        .font(.title2)
        .foregroundColor(.secondary)

      Text("Create a new tab to get started")
        .font(.subheadline)
        .foregroundColor(.secondary)

      HStack(spacing: 16) {
        ForEach(AgentType.allCases) { agent in
          Button {
            appState.showFolderSelector(for: agent)
          } label: {
            HStack(spacing: 8) {
              Image(systemName: agent.iconName)
              Text("New \(agent.rawValue) Tab")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
          }
          .buttonStyle(.borderedProminent)
          .tint(agent.accentColor)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.windowBackgroundColor))
  }
}

#Preview("Empty State") {
  EmptyTerminalView()
    .environment(AppState())
}
