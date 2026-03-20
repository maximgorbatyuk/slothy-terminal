import SwiftUI

/// Container view that displays the active tab's terminal or an empty state.
/// All terminal views are kept alive in a single ZStack to preserve PTY sessions
/// when switching tabs or toggling split mode. Split chrome is overlaid on top.
struct TerminalContainerView: View {
  @Environment(AppState.self) private var appState

  var body: some View {
    let isEmpty = appState.visibleTabs.isEmpty

    ZStack {
      // Always keep all tab surfaces alive to preserve PTY sessions
      // across workspace switches. The active layout (single or split)
      // controls visibility; tabs from inactive workspaces stay hidden.
      // When empty, force single layout to avoid rendering a stale split.
      if !isEmpty, let split = appState.activeSplitState {
        splitLayout(split)
      } else {
        singleLayout
      }

      if isEmpty {
        EmptyTerminalView()
          .allowsHitTesting(true)
      }
    }
  }

  // MARK: - Single Tab Layout

  /// Renders all tabs in a ZStack; only the active tab is visible.
  /// Tabs are never destroyed when switching — their PTY sessions stay alive.
  /// Hidden tabs get a zero frame so they don't participate in layout.
  private var singleLayout: some View {
    ZStack {
      ForEach(appState.tabs) { tab in
        let isVisible = tab.id == appState.activeTabID

        ActiveTerminalView(tab: tab, isActive: isVisible)
          .frame(
            maxWidth: isVisible ? .infinity : 0,
            maxHeight: isVisible ? .infinity : 0
          )
          .opacity(isVisible ? 1 : 0)
          .allowsHitTesting(isVisible)
      }
    }
  }

  // MARK: - Split Layout

  /// Renders all tabs in a single ZStack (preserving identity/lifetime),
  /// using GeometryReader to position the two split-visible tabs side by side.
  /// Non-split tabs are hidden but kept alive.
  private func splitLayout(_ split: WorkspaceSplitState) -> some View {
    GeometryReader { geo in
      let paneWidth = (geo.size.width - 1) / 2
      let paneHeight = geo.size.height

      ZStack(alignment: .topLeading) {
        // All tabs rendered — only split members visible.
        // Hidden tabs get zero frame to avoid layout participation.
        ForEach(appState.tabs) { tab in
          let isLeftPane = tab.id == split.leftTabID
          let isRightPane = tab.id == split.rightTabID
          let isVisibleInSplit = isLeftPane || isRightPane
          let isFocused = tab.id == appState.activeTabID

          ActiveTerminalView(
            tab: tab,
            isActive: isFocused,
            onPaneFocused: isVisibleInSplit ? {
              if !isFocused {
                appState.switchToTab(id: tab.id)
              }
            } : nil
          )
          .frame(
            width: isVisibleInSplit ? paneWidth : 0,
            height: isVisibleInSplit ? paneHeight : 0
          )
          .offset(x: isRightPane ? paneWidth + 1 : 0)
          .opacity(isVisibleInSplit ? 1 : 0)
          .allowsHitTesting(isVisibleInSplit)
        }

        // Vertical divider between panes.
        Rectangle()
          .fill(Color.primary.opacity(0.15))
          .frame(width: 1, height: paneHeight)
          .offset(x: paneWidth)
          .allowsHitTesting(false)

        // Thin accent top border on the focused pane.
        Rectangle()
          .fill(Color.accentColor)
          .frame(
            width: paneWidth,
            height: 2
          )
          .offset(x: appState.activeTabID == split.rightTabID ? paneWidth + 1 : 0)
          .allowsHitTesting(false)
      }
    }
  }
}

/// Displays the terminal or chat for an active tab.
struct ActiveTerminalView: View {
  let tab: Tab
  let isActive: Bool

  /// Called when the user interacts with this pane (click/mouse-down).
  /// Used by split view to update AppState focus.
  var onPaneFocused: (() -> Void)? = nil

  @State private var isReady: Bool = false
  @State private var agentUnavailableError: String?

  var body: some View {
    ZStack {
      appCardColor

      if tab.mode == .git {
        GitClientView(workingDirectory: tab.workingDirectory)
          .contentShape(Rectangle())
          .onTapGesture { onPaneFocused?() }
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
          shouldAutoRunCommand: tab.agentType?.supportsInitialPrompt ?? false,
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
          },
          onMouseDown: {
            onPaneFocused?()
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

      // Check if agent is available.
      if !tab.isAgentAvailable {
        agentUnavailableError = "The \(tab.agent?.displayName ?? "Agent") CLI was not found at: \(tab.command)"
        return
      }

      // Mark as ready to show terminal.
      isReady = true
      tab.handleTerminalLaunch(shouldAutoRunCommand: tab.agentType?.supportsInitialPrompt ?? false)
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
