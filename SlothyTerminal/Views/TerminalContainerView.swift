import SwiftUI

/// Container view that displays the active tab's terminal or an empty state.
/// All terminal views are kept alive to preserve sessions when switching tabs.
struct TerminalContainerView: View {
  @Environment(AppState.self) private var appState

  var body: some View {
    ZStack {
      if appState.tabs.isEmpty {
        EmptyTerminalView()
      } else {
        /// Render all terminal views but only show the active one.
        /// This keeps sessions alive when switching between tabs.
        ForEach(appState.tabs) { tab in
          ActiveTerminalView(tab: tab)
            .opacity(tab.id == appState.activeTabID ? 1 : 0)
            .allowsHitTesting(tab.id == appState.activeTabID)
        }
      }
    }
  }
}

/// Displays the terminal for an active tab.
struct ActiveTerminalView: View {
  let tab: Tab
  @State private var isReady: Bool = false
  @State private var agentUnavailableError: String?

  var body: some View {
    ZStack {
      Color(.textBackgroundColor)

      if let error = agentUnavailableError {
        AgentUnavailableView(agentName: tab.agent.displayName, error: error)
      } else if isReady {
        StandaloneTerminalView(
          workingDirectory: tab.workingDirectory,
          command: tab.command,
          arguments: tab.arguments,
          onOutput: { output in
            tab.processOutput(output)
          },
          shouldAutoRunCommand: tab.agentType.showsUsageStats
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

      /// Mark as ready to show terminal.
      isReady = true

      /// Start the session timer.
      tab.usageStats.startSession()
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
    VStack(spacing: 32) {
      VStack(spacing: 8) {
        Image(systemName: "terminal.fill")
          .font(.system(size: 48))
          .foregroundColor(.secondary)

        Text("SlothyTerminal")
          .font(.title)
          .fontWeight(.semibold)

        Text("Choose a tab type to get started")
          .font(.subheadline)
          .foregroundColor(.secondary)
      }

      VStack(spacing: 12) {
        ForEach(AgentType.allCases) { agentType in
          TabTypeButton(agentType: agentType) {
            appState.showFolderSelector(for: agentType)
          }
        }
      }
      .frame(maxWidth: 320)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.windowBackgroundColor))
  }
}

/// Button for creating a new tab with a specific type.
struct TabTypeButton: View {
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
      HStack(spacing: 12) {
        Image(systemName: agentType.iconName)
          .font(.system(size: 20))
          .foregroundColor(agentType.accentColor)
          .frame(width: 32)

        VStack(alignment: .leading, spacing: 2) {
          Text("New \(agentType.rawValue) Tab")
            .font(.system(size: 14, weight: .medium))

          Text(agentType.description)
            .font(.system(size: 11))
            .foregroundColor(.secondary)
        }

        Spacer()

        if !isAvailable && agentType != .terminal {
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
      .background(Color(.controlBackgroundColor))
      .cornerRadius(8)
    }
    .buttonStyle(.plain)
    .opacity(isAvailable ? 1.0 : 0.7)
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
