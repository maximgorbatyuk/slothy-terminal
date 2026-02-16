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

  /// Callback when the surface is closed (process exits).
  var onClosed: (() -> Void)?

  func makeNSView(context: Context) -> GhosttySurfaceView {
    let surfaceView = GhosttySurfaceView()
    context.coordinator.surfaceView = surfaceView

    /// Wire callbacks.
    surfaceView.onDirectoryChanged = onDirectoryChanged
    surfaceView.onClosed = onClosed

    /// Determine the command to run.
    /// For AI agents (shouldAutoRunCommand=true), we pass the command directly
    /// to libghostty as the surface command so it runs immediately.
    /// For plain terminal, we let libghostty use the default shell.
    if shouldAutoRunCommand {
      surfaceView.createSurface(
        command: command,
        args: arguments,
        workingDirectory: workingDirectory,
        environment: environment
      )
    } else {
      /// Plain terminal — launch default shell, let ghostty config control it.
      surfaceView.createSurface(
        workingDirectory: workingDirectory,
        environment: environment
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
