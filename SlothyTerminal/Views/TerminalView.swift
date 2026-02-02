import AppKit
import SwiftTerm
import SwiftUI

/// A SwiftUI wrapper for SwiftTerm's terminal view with custom PTY integration.
struct TerminalViewRepresentable: NSViewRepresentable {
  let workingDirectory: URL
  let command: String
  let arguments: [String]

  func makeNSView(context: Context) -> SwiftTerm.LocalProcessTerminalView {
    let terminalView = SwiftTerm.LocalProcessTerminalView(frame: .zero)

    /// Configure terminal appearance.
    terminalView.configureNativeColors()
    terminalView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    /// Enable text selection and copy.
    terminalView.allowMouseReporting = true

    /// Set up the coordinator as the terminal delegate.
    terminalView.processDelegate = context.coordinator

    /// Store reference to terminal view in coordinator.
    context.coordinator.terminalView = terminalView
    context.coordinator.workingDirectory = workingDirectory

    /// Start the process after a brief delay to ensure the view is ready.
    Task { @MainActor in
      context.coordinator.startProcess(
        command: command,
        arguments: arguments
      )
    }

    return terminalView
  }

  func updateNSView(_ nsView: SwiftTerm.LocalProcessTerminalView, context: Context) {
    /// No updates needed.
  }

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
    weak var terminalView: SwiftTerm.LocalProcessTerminalView?
    var ptyController: PTYController?
    var workingDirectory: URL?
    private var readTask: Task<Void, Never>?

    @MainActor
    func startProcess(command: String, arguments: [String]) {
      guard let terminalView,
            let workingDirectory
      else {
        return
      }

      /// Build environment with proper PATH for finding node, etc.
      var environment = ProcessInfo.processInfo.environment

      /// Ensure common binary locations are in PATH.
      let additionalPaths = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin",
        "/opt/homebrew/sbin"
      ]

      if let existingPath = environment["PATH"] {
        let pathSet = Set(existingPath.split(separator: ":").map(String.init))
        let missingPaths = additionalPaths.filter { !pathSet.contains($0) }
        if !missingPaths.isEmpty {
          environment["PATH"] = existingPath + ":" + missingPaths.joined(separator: ":")
        }
      } else {
        environment["PATH"] = additionalPaths.joined(separator: ":")
      }

      /// Set working directory.
      environment["PWD"] = workingDirectory.path

      /// Convert environment to array of strings.
      let envArray = environment.map { "\($0.key)=\($0.value)" }

      /// Change to working directory before starting process.
      FileManager.default.changeCurrentDirectoryPath(workingDirectory.path)

      /// Use SwiftTerm's built-in process spawning.
      terminalView.startProcess(
        executable: command,
        args: arguments,
        environment: envArray,
        execName: nil
      )
    }

    func sizeChanged(source: SwiftTerm.LocalProcessTerminalView, newCols: Int, newRows: Int) {
      /// Size change is handled internally by LocalProcessTerminalView.
    }

    func setTerminalTitle(source: SwiftTerm.LocalProcessTerminalView, title: String) {
      /// Title changes can be handled here if needed.
    }

    func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {
      /// Directory change notifications.
    }

    func processTerminated(source: SwiftTerm.TerminalView, exitCode: Int32?) {
      /// Process termination handling.
    }

    deinit {
      readTask?.cancel()
    }
  }
}

/// A standalone terminal view that manages its own process.
struct StandaloneTerminalView: View {
  let workingDirectory: URL
  let command: String
  let arguments: [String]

  var body: some View {
    TerminalViewRepresentable(
      workingDirectory: workingDirectory,
      command: command,
      arguments: arguments
    )
  }
}

#Preview {
  StandaloneTerminalView(
    workingDirectory: FileManager.default.homeDirectoryForCurrentUser,
    command: "/bin/zsh",
    arguments: []
  )
  .frame(width: 800, height: 600)
}
