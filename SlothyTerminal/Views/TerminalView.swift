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

    /// Set up the coordinator as the terminal delegate.
    terminalView.processDelegate = context.coordinator

    /// Store reference to terminal view in coordinator.
    context.coordinator.terminalView = terminalView

    /// Start the process after a brief delay to ensure the view is ready.
    Task { @MainActor in
      context.coordinator.startProcess(
        command: command,
        arguments: arguments,
        workingDirectory: workingDirectory
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
    private var readTask: Task<Void, Never>?

    @MainActor
    func startProcess(command: String, arguments: [String], workingDirectory: URL) {
      guard let terminalView else {
        return
      }

      /// Use SwiftTerm's built-in process spawning for simplicity.
      terminalView.startProcess(
        executable: command,
        args: arguments,
        environment: nil,
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
