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
  @State private var agentUnavailableError: String?

  var body: some View {
    ZStack {
      Color(.textBackgroundColor)

      if let error = agentUnavailableError {
        AgentUnavailableView(agentName: tab.agent.displayName, error: error)
      } else if ptyController != nil {
        StandaloneTerminalView(
          workingDirectory: tab.workingDirectory,
          command: tab.command,
          arguments: tab.arguments
        )
      } else {
        ProgressView("Starting \(tab.agent.displayName)...")
      }
    }
    .task {
      /// Check if agent is available.
      if !tab.isAgentAvailable {
        agentUnavailableError = "The \(tab.agent.displayName) CLI was not found at: \(tab.command)"
        return
      }

      /// Initialize PTY controller when view appears.
      let controller = PTYController()
      ptyController = controller
      tab.ptyController = controller
    }
  }
}

/// View shown when an agent is not installed.
struct AgentUnavailableView: View {
  let agentName: String
  let error: String

  var body: some View {
    VStack(spacing: 16) {
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.system(size: 48))
        .foregroundColor(.orange)

      Text("\(agentName) Not Found")
        .font(.title2)
        .fontWeight(.semibold)

      Text(error)
        .font(.system(size: 12))
        .foregroundColor(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 32)

      VStack(alignment: .leading, spacing: 8) {
        Text("To install \(agentName):")
          .font(.system(size: 12, weight: .medium))

        Text(installationInstructions)
          .font(.system(size: 11, design: .monospaced))
          .padding(12)
          .background(Color(.textBackgroundColor))
          .cornerRadius(6)
      }
      .padding(.top, 8)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.windowBackgroundColor))
  }

  private var installationInstructions: String {
    switch agentName {
    case "Claude":
      return """
        # Install via npm
        npm install -g @anthropic-ai/claude-cli

        # Or set custom path
        export CLAUDE_PATH=/path/to/claude
        """
    case "GLM":
      return """
        # Install GLM CLI
        pip install chatglm-cli

        # Or set custom path
        export GLM_PATH=/path/to/glm
        """
    default:
      return "Please install the \(agentName) CLI."
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
          AgentButton(agentType: agent) {
            appState.showFolderSelector(for: agent)
          }
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.windowBackgroundColor))
  }
}

/// Button for creating a new tab with a specific agent.
struct AgentButton: View {
  let agentType: AgentType
  let action: () -> Void

  private var agent: AIAgent {
    AgentFactory.createAgent(for: agentType)
  }

  private var isAvailable: Bool {
    agent.isAvailable()
  }

  var body: some View {
    Button(action: action) {
      HStack(spacing: 8) {
        Image(systemName: agent.iconName)
        Text("New \(agent.displayName) Tab")
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 8)
    }
    .buttonStyle(.borderedProminent)
    .tint(agent.accentColor)
    .opacity(isAvailable ? 1.0 : 0.6)
    .help(isAvailable ? "Create a new \(agent.displayName) tab" : "\(agent.displayName) CLI not found")
  }
}

#Preview("Empty State") {
  EmptyTerminalView()
    .environment(AppState())
}

#Preview("Agent Unavailable") {
  AgentUnavailableView(
    agentName: "Claude",
    error: "The Claude CLI was not found at: /usr/local/bin/claude"
  )
}
