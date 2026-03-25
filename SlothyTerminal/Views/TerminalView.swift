import AppKit
import SwiftUI

/// SwiftUI wrapper for a GhosttySurfaceView (libghostty terminal surface).
struct GhosttyTerminalViewRepresentable: NSViewRepresentable {
  let workingDirectory: URL
  let command: String
  let arguments: [String]
  let environment: [String: String]

  /// Tab ID for surface registry registration.
  let tabId: UUID

  /// Whether to auto-run the command after the shell starts.
  let shouldAutoRunCommand: Bool

  /// Whether this terminal tab is currently active/visible.
  var isActive: Bool = true

  /// Callback when the current directory changes.
  var onDirectoryChanged: ((URL) -> Void)?

  /// Callback when user presses Enter in terminal input.
  var onCommandEntered: (() -> Void)?

  /// Callback when a raw command line is submitted.
  var onCommandSubmitted: ((String) -> Void)?

  /// Callback when a command finishes executing.
  var onCommandFinished: (() -> Void)?

  /// Callback when the surface is closed (process exits).
  var onClosed: (() -> Void)?

  /// Callback when terminal content changes.
  var onTerminalActivity: (() -> Void)?

  /// Callback when background terminal output is detected.
  var onBackgroundActivity: (() -> Void)?

  /// Callback when the user clicks inside the terminal surface.
  var onMouseDown: (() -> Void)?

  /// Callback that synchronously decides whether plain Enter should submit.
  var onSubmitGate: (() -> TerminalSubmitGateDecision)?

  func makeNSView(context: Context) -> GhosttySurfaceView {
    let surfaceView = GhosttySurfaceView()
    context.coordinator.surfaceView = surfaceView
    context.coordinator.tabId = tabId

    /// Register surface for injection.
    TerminalSurfaceRegistry.shared.register(tabId: tabId, surface: surfaceView)

    configureCallbacks(for: surfaceView)

    let launchEnvironment = makeLaunchEnvironment(
      workingDirectory: workingDirectory,
      additionalEnvironment: environment
    )

    /// For AI tabs we run the explicit command with args.
    /// For plain terminal tabs we let Ghostty launch its default shell command
    /// path to preserve native prompt/redraw behavior.
    let resolvedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
    if shouldAutoRunCommand, !resolvedCommand.isEmpty {
      surfaceView.createSurface(
        command: resolvedCommand,
        args: arguments,
        workingDirectory: workingDirectory,
        environment: launchEnvironment
      )
    } else {
      surfaceView.createSurface(
        workingDirectory: workingDirectory,
        environment: launchEnvironment
      )
    }

    return surfaceView
  }

  func updateNSView(_ nsView: GhosttySurfaceView, context: Context) {
    configureCallbacks(for: nsView)

    let wasActive = nsView.isTabActive

    /// Update tab-active state (has its own dedup guard).
    nsView.setTabActive(isActive)

    /// Only send focus changes on actual tab transitions to avoid
    /// redundant ghostty_surface_set_focus calls that can cause
    /// the terminal to re-evaluate scroll position (scroll-to-top-then-bottom).
    if isActive != wasActive {
      nsView.setFocused(isActive)
    }

    /// Ensure first responder is set when the tab is active.
    if isActive,
       nsView.window?.firstResponder !== nsView
    {
      DispatchQueue.main.async {
        if nsView.window?.firstResponder !== nsView {
          nsView.window?.makeFirstResponder(nsView)
        }
      }
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  class Coordinator {
    weak var surfaceView: GhosttySurfaceView?
    var tabId: UUID?
  }

  private func configureCallbacks(for surfaceView: GhosttySurfaceView) {
    surfaceView.onDirectoryChanged = onDirectoryChanged
    surfaceView.onCommandEntered = onCommandEntered
    surfaceView.onCommandSubmitted = onCommandSubmitted
    surfaceView.onCommandFinished = onCommandFinished
    surfaceView.onClosed = onClosed
    surfaceView.onTerminalActivity = onTerminalActivity
    surfaceView.onBackgroundActivity = onBackgroundActivity
    surfaceView.onMouseDown = onMouseDown
    surfaceView.onSubmitGate = onSubmitGate
  }

  private func makeLaunchEnvironment(
    workingDirectory: URL,
    additionalEnvironment: [String: String]
  ) -> [String: String] {
    var env = ProcessInfo.processInfo.environment

    for (key, value) in additionalEnvironment {
      env[key] = value
    }

    let defaultPaths = [
      "\(NSHomeDirectory())/.local/bin",
      "/opt/homebrew/bin",
      "/usr/local/bin",
      "/usr/bin",
      "/bin",
      "/usr/sbin",
      "/sbin",
      "/opt/homebrew/sbin",
    ]

    var pathEntries = env["PATH"]?
      .split(separator: ":")
      .map(String.init) ?? []

    for path in defaultPaths where !pathEntries.contains(path) {
      pathEntries.append(path)
    }

    env["PATH"] = pathEntries.joined(separator: ":")
    env["PWD"] = workingDirectory.path
    env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
    env["LC_ALL"] = env["LC_ALL"] ?? "en_US.UTF-8"
    env["HOME"] = env["HOME"] ?? NSHomeDirectory()
    env["USER"] = env["USER"] ?? NSUserName()
    env["SHELL"] = env["SHELL"] ?? "/bin/zsh"

    env["TERM"] = env["TERM"] ?? "xterm-256color"
    env["COLORTERM"] = env["COLORTERM"] ?? "truecolor"
    env["TERM_PROGRAM"] = "SlothyTerminal"
    env["TERM_PROGRAM_VERSION"] = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

    env.removeValue(forKey: "CI")

    return env
  }

  static func dismantleNSView(_ nsView: GhosttySurfaceView, coordinator: Coordinator) {
    if let tabId = coordinator.tabId {
      TerminalSurfaceRegistry.shared.unregister(tabId: tabId)
    }
    nsView.destroySurface()
  }
}

/// A standalone terminal view that manages its own process.
struct StandaloneTerminalView: View {
  let workingDirectory: URL
  let command: String
  let arguments: [String]
  var environment: [String: String] = [:]

  /// Tab ID for surface registry registration.
  let tabId: UUID

  /// Whether to auto-run the command (true for AI agents, false for plain terminal).
  var shouldAutoRunCommand: Bool = true

  /// Whether this terminal tab is currently active/visible.
  var isActive: Bool = true

  /// Callback when the current directory changes.
  var onDirectoryChanged: ((URL) -> Void)? = nil

  /// Callback when user presses Enter in terminal input.
  var onCommandEntered: (() -> Void)? = nil

  /// Callback when a raw command line is submitted.
  var onCommandSubmitted: ((String) -> Void)? = nil

  /// Callback when a command finishes executing.
  var onCommandFinished: (() -> Void)? = nil

  /// Callback when the surface is closed.
  var onClosed: (() -> Void)? = nil

  /// Callback when terminal content changes.
  var onTerminalActivity: (() -> Void)? = nil

  /// Callback when background terminal output is detected.
  var onBackgroundActivity: (() -> Void)? = nil

  /// Callback when the user clicks inside the terminal surface.
  var onMouseDown: (() -> Void)? = nil

  /// Callback that synchronously decides whether plain Enter should submit.
  var onSubmitGate: (() -> TerminalSubmitGateDecision)? = nil

  var body: some View {
    GhosttyTerminalViewRepresentable(
      workingDirectory: workingDirectory,
      command: command,
      arguments: arguments,
      environment: environment,
      tabId: tabId,
      shouldAutoRunCommand: shouldAutoRunCommand,
      isActive: isActive,
      onDirectoryChanged: onDirectoryChanged,
      onCommandEntered: onCommandEntered,
      onCommandSubmitted: onCommandSubmitted,
      onCommandFinished: onCommandFinished,
      onClosed: onClosed,
      onTerminalActivity: onTerminalActivity,
      onBackgroundActivity: onBackgroundActivity,
      onMouseDown: onMouseDown,
      onSubmitGate: onSubmitGate
    )
  }
}

#Preview {
  StandaloneTerminalView(
    workingDirectory: FileManager.default.homeDirectoryForCurrentUser,
    command: "/bin/zsh",
    arguments: [],
    tabId: UUID(),
    shouldAutoRunCommand: false
  )
  .frame(width: 800, height: 600)
}
