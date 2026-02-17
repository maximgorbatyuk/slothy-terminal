import AppKit
import SwiftUI

/// SwiftUI wrapper for a GhosttySurfaceView (libghostty terminal surface).
struct GhosttyTerminalViewRepresentable: NSViewRepresentable {
  let workingDirectory: URL
  let command: String
  let arguments: [String]
  let environment: [String: String]

  /// Whether to auto-run the command after the shell starts.
  let shouldAutoRunCommand: Bool

  /// Whether this terminal tab is currently active/visible.
  var isActive: Bool = true

  /// Callback when the current directory changes.
  var onDirectoryChanged: ((URL) -> Void)?

  /// Callback when user presses Enter in terminal input.
  var onCommandEntered: (() -> Void)?

  /// Callback when the surface is closed (process exits).
  var onClosed: (() -> Void)?

  func makeNSView(context: Context) -> GhosttySurfaceView {
    let surfaceView = GhosttySurfaceView()
    context.coordinator.surfaceView = surfaceView

    /// Wire callbacks.
    surfaceView.onDirectoryChanged = onDirectoryChanged
    surfaceView.onCommandEntered = onCommandEntered
    surfaceView.onClosed = onClosed

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
    /// Update focus state when tab visibility changes.
    if isActive {
      nsView.setFocused(true)
      nsView.window?.makeFirstResponder(nsView)
    } else {
      nsView.setFocused(false)
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  class Coordinator {
    weak var surfaceView: GhosttySurfaceView?
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
      "/opt/homebrew/bin",
      "/usr/local/bin",
      "/usr/bin",
      "/bin",
      "/usr/sbin",
      "/sbin",
      "/opt/homebrew/sbin"
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
    nsView.destroySurface()
  }
}

/// A standalone terminal view that manages its own process.
struct StandaloneTerminalView: View {
  let workingDirectory: URL
  let command: String
  let arguments: [String]
  var environment: [String: String] = [:]

  /// Whether to auto-run the command (true for AI agents, false for plain terminal).
  var shouldAutoRunCommand: Bool = true

  /// Whether this terminal tab is currently active/visible.
  var isActive: Bool = true

  /// Callback when the current directory changes.
  var onDirectoryChanged: ((URL) -> Void)? = nil

  /// Callback when user presses Enter in terminal input.
  var onCommandEntered: (() -> Void)? = nil

  /// Callback when the surface is closed.
  var onClosed: (() -> Void)? = nil

  var body: some View {
    GhosttyTerminalViewRepresentable(
      workingDirectory: workingDirectory,
      command: command,
      arguments: arguments,
      environment: environment,
      shouldAutoRunCommand: shouldAutoRunCommand,
      isActive: isActive,
      onDirectoryChanged: onDirectoryChanged,
      onCommandEntered: onCommandEntered,
      onClosed: onClosed
    )
  }
}

#Preview {
  StandaloneTerminalView(
    workingDirectory: FileManager.default.homeDirectoryForCurrentUser,
    command: "/bin/zsh",
    arguments: [],
    shouldAutoRunCommand: false
  )
  .frame(width: 800, height: 600)
}
