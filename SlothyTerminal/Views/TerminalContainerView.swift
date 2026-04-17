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
  private enum ClaudeCooldownOverlay {
    static let dismissDelayNanoseconds: UInt64 = 2_500_000_000
  }

  /// Tunables for the agent auto-launch flow.
  ///
  /// We host agents under a shell (rather than as the PTY primary) so the
  /// tab stays interactive after the agent exits. Before injecting the
  /// agent command into that shell we wait for:
  /// 1. The surface to register with the injection registry.
  /// 2. The prompt to settle (no Ghostty render frames for `promptIdleNs`).
  /// Each wait is bounded so a misbehaving shell can't strand the tab.
  private enum AgentAutoLaunch {
    static let registryPollNs: UInt64 = 100_000_000
    static let registryTimeoutNs: UInt64 = 3_000_000_000
    static let renderPollNs: UInt64 = 50_000_000
    static let promptIdleNs: UInt64 = 150_000_000
    static let promptTimeoutNs: UInt64 = 3_000_000_000
  }

  let tab: Tab
  let isActive: Bool

  /// Called when the user interacts with this pane (click/mouse-down).
  /// Used by split view to update AppState focus.
  var onPaneFocused: (() -> Void)? = nil

  @State private var isReady: Bool = false
  @State private var agentUnavailableError: String?
  @State private var claudeSubmitDecision: ClaudeCooldownDecision?
  @State private var claudeCooldownMessage: String?
  @State private var isShowingClaudeCooldownOverlay: Bool = false
  @State private var claudeCooldownOverlayToken: Int = 0

  /// One-shot guard: the agent command must be injected exactly once per
  /// view lifetime. `.task` can re-fire if SwiftUI identity changes (tab
  /// reorder, workspace move); re-injecting would send the agent's own
  /// command into the already-running agent as a prompt.
  @State private var didAutoLaunchAgent: Bool = false

  /// True while we are waiting for the shell to become interactive so we
  /// can inject the agent command. Drives a lightweight status banner.
  @State private var isAutoLaunchingAgent: Bool = false

  private var submitGate: (() -> TerminalSubmitGateDecision)? {
    guard tab.agentType == .claude else {
      return nil
    }

    return {
      let decision = ClaudeCooldownService.shared.attemptSubmission()
      claudeSubmitDecision = decision

      switch decision {
      case .allowed:
        claudeCooldownMessage = nil
        isShowingClaudeCooldownOverlay = false

      case .blocked(let remainingSeconds):
        let formattedRemaining = ClaudeCooldownService.formatRemaining(seconds: remainingSeconds)
        claudeCooldownMessage = "Claude cooldown active - try again in \(formattedRemaining)"
        isShowingClaudeCooldownOverlay = true
        claudeCooldownOverlayToken += 1
      }

      switch decision {
      case .allowed:
        return .allow

      case .blocked:
        return .block
      }
    }
  }

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
          shouldAutoRunCommand: false,
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
          },
          onSubmitGate: submitGate
        )
        .environment(\.colorScheme, .dark)
      } else {
        ProgressView("Starting \(tab.agent?.displayName ?? "session")...")
          .environment(\.colorScheme, .dark)
      }

      if isShowingClaudeCooldownOverlay,
         let claudeCooldownMessage
      {
        VStack {
          HStack {
            Label(claudeCooldownMessage, systemImage: "clock.badge.exclamationmark")
              .font(.system(size: 12, weight: .semibold))
              .foregroundStyle(Color.white)
              .padding(.horizontal, 12)
              .padding(.vertical, 8)
              .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                  .fill(Color.orange.opacity(0.92))
              )
              .shadow(color: Color.black.opacity(0.18), radius: 10, y: 4)

            Spacer(minLength: 0)
          }

          Spacer()
        }
        .padding(.top, 12)
        .padding(.horizontal, 12)
        .transition(.move(edge: .top).combined(with: .opacity))
        .allowsHitTesting(false)
      }

      if isAutoLaunchingAgent {
        VStack {
          HStack {
            Label("Starting \(tab.agent?.displayName ?? "session")…", systemImage: "arrow.triangle.2.circlepath")
              .font(.system(size: 12, weight: .semibold))
              .foregroundStyle(Color.white)
              .padding(.horizontal, 12)
              .padding(.vertical, 8)
              .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                  .fill(Color.accentColor.opacity(0.92))
              )
              .shadow(color: Color.black.opacity(0.18), radius: 10, y: 4)

            Spacer(minLength: 0)
          }

          Spacer()
        }
        .padding(.top, 12)
        .padding(.horizontal, 12)
        .transition(.opacity)
        .allowsHitTesting(false)
      }
    }
    .animation(.easeOut(duration: 0.18), value: isShowingClaudeCooldownOverlay)
    .animation(.easeOut(duration: 0.18), value: isAutoLaunchingAgent)
    .task(id: claudeCooldownOverlayToken) {
      guard claudeCooldownOverlayToken > 0 else {
        return
      }

      try? await Task.sleep(nanoseconds: ClaudeCooldownOverlay.dismissDelayNanoseconds)

      guard !Task.isCancelled else {
        return
      }

      isShowingClaudeCooldownOverlay = false
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
      let shouldHostAgent = tab.agentType?.needsShellHost ?? false
      isReady = true
      tab.handleTerminalLaunch(shouldAutoRunCommand: shouldHostAgent)

      if shouldHostAgent, !didAutoLaunchAgent {
        didAutoLaunchAgent = true
        await autoLaunchAgentCommand()
      }
    }
  }

  /// Waits for the shell to become interactive, then injects the agent
  /// command so the shell remains as the PTY parent after the agent exits
  /// — otherwise the surface has no process left and the tab freezes.
  ///
  /// Readiness is detected in two phases:
  /// 1. Poll for the surface to register with `TerminalSurfaceRegistry`.
  /// 2. Poll Ghostty's render-dirty flag until we observe a quiet window
  ///    (the shell has finished drawing its prompt).
  /// A Ctrl+U is sent before the command to discard anything the user
  /// may have typed into the prompt during the startup window.
  private func autoLaunchAgentCommand() async {
    isAutoLaunchingAgent = true
    defer { isAutoLaunchingAgent = false }

    let trimmedCommand = tab.command.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !trimmedCommand.isEmpty else {
      return
    }

    guard let surface = await waitForRegisteredSurface() else {
      return
    }

    await waitForPromptIdle(on: surface)

    guard !Task.isCancelled else {
      return
    }

    let parts = [trimmedCommand] + tab.arguments
    let commandLine = parts.map(GhosttySurfaceView.shellEscape).joined(separator: " ")

    _ = surface.injectControl(.ctrlU)
    _ = surface.injectCommand(commandLine, submit: .execute)
  }

  /// Polls the registry until a surface is registered for this tab, or the
  /// bounded timeout elapses. Returns `nil` if the surface never appears
  /// (e.g., the tab was dismissed before becoming visible).
  private func waitForRegisteredSurface() async -> InjectableSurface? {
    let deadlineNs = AgentAutoLaunch.registryTimeoutNs
    var elapsedNs: UInt64 = 0

    while elapsedNs < deadlineNs {
      if let surface = TerminalSurfaceRegistry.shared.surface(for: tab.id) {
        return surface
      }

      try? await Task.sleep(nanoseconds: AgentAutoLaunch.registryPollNs)

      guard !Task.isCancelled else {
        return nil
      }

      elapsedNs += AgentAutoLaunch.registryPollNs
    }

    return TerminalSurfaceRegistry.shared.surface(for: tab.id)
  }

  /// Waits for the terminal to go quiet for at least `promptIdleNs`, using
  /// Ghostty's render-dirty flag as a proxy for prompt readiness. Bounded
  /// by `promptTimeoutNs` so a noisy shell (e.g., a login banner that
  /// never stops updating) cannot strand the injection forever.
  private func waitForPromptIdle(on surface: InjectableSurface) async {
    let pollNs = AgentAutoLaunch.renderPollNs
    let idleThresholdNs = AgentAutoLaunch.promptIdleNs
    let deadlineNs = AgentAutoLaunch.promptTimeoutNs

    var quietNs: UInt64 = 0
    var elapsedNs: UInt64 = 0

    surface.clearRenderDirty()

    while elapsedNs < deadlineNs {
      try? await Task.sleep(nanoseconds: pollNs)

      guard !Task.isCancelled else {
        return
      }

      elapsedNs += pollNs

      if surface.hasNewRenderSinceLastRead {
        surface.clearRenderDirty()
        quietNs = 0
        continue
      }

      quietNs += pollNs

      if quietNs >= idleThresholdNs {
        return
      }
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
