import SwiftUI

/// Container view that displays the active tab's terminal or an empty state.
/// All terminal views are kept alive to preserve sessions when switching tabs.
struct TerminalContainerView: View {
  @Environment(AppState.self) private var appState

  var body: some View {
    ZStack {
      if appState.visibleTabs.isEmpty {
        EmptyTerminalView()
      }

      /// Render all terminal views but only show the active one.
      /// This keeps sessions alive when switching between tabs and workspaces.
      ForEach(appState.tabs) { tab in
        ActiveTerminalView(tab: tab, isActive: tab.id == appState.activeTabID)
          .opacity(tab.id == appState.activeTabID ? 1 : 0)
          .allowsHitTesting(tab.id == appState.activeTabID)
      }
    }
  }
}

/// Displays the terminal or chat for an active tab.
struct ActiveTerminalView: View {
  let tab: Tab
  let isActive: Bool
  @State private var isReady: Bool = false
  @State private var agentUnavailableError: String?

  var body: some View {
    ZStack {
      appCardColor

      if tab.mode == .git {
        GitClientView(workingDirectory: tab.workingDirectory)
      } else if tab.mode == .chat, let chatState = tab.chatState {
        ChatView(chatState: chatState)
      } else if let error = agentUnavailableError {
        AgentUnavailableView(agentName: tab.agent?.displayName ?? "Unknown", error: error)
          .environment(\.colorScheme, .dark)
      } else if isReady {
        StandaloneTerminalView(
          workingDirectory: tab.workingDirectory,
          command: tab.command,
          arguments: tab.arguments,
          environment: tab.environment,
          tabId: tab.id,
          shouldAutoRunCommand: tab.agentType?.showsUsageStats ?? false,
          isActive: isActive,
          onDirectoryChanged: { newDirectory in
            tab.workingDirectory = newDirectory
          },
          onCommandEntered: {
            tab.handleTerminalCommandEntered()
          },
          onCommandSubmitted: { rawCommandLine in
            tab.updateLastSubmittedCommandLabel(from: rawCommandLine)
          },
          onCommandFinished: {
            tab.markTerminalIdle()
          },
          onClosed: {
            tab.markTerminalIdle()
          },
          onTerminalActivity: {
            tab.recordTerminalActivity()
          },
          onBackgroundActivity: {
            tab.markBackgroundActivity()
          }
        )
        .environment(\.colorScheme, .dark)
      } else {
        ProgressView("Starting \(tab.agent?.displayName ?? "session")...")
          .environment(\.colorScheme, .dark)
      }
    }
    .task {
      // Git mode renders its own content; no PTY or chat setup needed.
      if tab.mode == .git {
        return
      }

      // Chat mode doesn't need PTY availability checks.
      if tab.mode == .chat {
        tab.usageStats.startSession()
        return
      }

      // Check if agent is available.
      if !tab.isAgentAvailable {
        agentUnavailableError = "The \(tab.agent?.displayName ?? "Agent") CLI was not found at: \(tab.command)"
        return
      }

      // Mark as ready to show terminal.
      isReady = true
      tab.handleTerminalLaunch(shouldAutoRunCommand: tab.agentType?.showsUsageStats ?? false)

      // Start the session timer.
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
          .background(appCardColor)
          .cornerRadius(6)
      }
      .padding(.top, 8)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(appBackgroundColor)
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
  var body: some View {
    VStack {
      StartSessionContentView(presentation: .embedded)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(.horizontal, 32)
    .padding(.vertical, 28)
    .background(appBackgroundColor)
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
