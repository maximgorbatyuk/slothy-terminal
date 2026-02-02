import AppKit
import SwiftTerm
import SwiftUI

/// A SwiftUI wrapper for SwiftTerm's terminal view with output capture.
struct TerminalViewRepresentable: NSViewRepresentable {
  let workingDirectory: URL
  let command: String
  let arguments: [String]
  let onOutput: ((String) -> Void)?

  /// Whether to auto-run the command after the shell starts.
  let shouldAutoRunCommand: Bool

  /// Callback that provides a function to send text to the terminal.
  var onTerminalReady: ((@escaping (String) -> Void) -> Void)?

  /// Callback when user enters a command (presses Enter).
  var onCommandEntered: (() -> Void)?

  /// Callback when the current directory changes.
  var onDirectoryChanged: ((URL) -> Void)?

  /// Command to auto-run after shell starts (optional).
  var autoRunCommand: String? {
    guard shouldAutoRunCommand else {
      return nil
    }

    /// Build the command string from command and arguments.
    if arguments.isEmpty {
      return command
    } else {
      let escapedArgs = arguments.map { arg in
        arg.contains(" ") ? "\"\(arg)\"" : arg
      }
      return "\(command) \(escapedArgs.joined(separator: " "))"
    }
  }

  func makeNSView(context: Context) -> OutputCapturingTerminalView {
    let terminalView = OutputCapturingTerminalView(frame: .zero)

    /// Configure terminal appearance.
    terminalView.configureNativeColors()
    terminalView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    /// Set up output callback.
    terminalView.onDataReceived = { [onOutput] data in
      if let string = String(data: data, encoding: .utf8) {
        onOutput?(string)
      }
    }

    /// Set up command entered callback.
    terminalView.onCommandEntered = onCommandEntered

    /// Set up the coordinator as the terminal delegate.
    terminalView.processDelegate = context.coordinator

    /// Store reference to terminal view in coordinator.
    context.coordinator.terminalView = terminalView
    context.coordinator.workingDirectory = workingDirectory
    context.coordinator.autoRunCommand = autoRunCommand
    context.coordinator.onDirectoryChanged = onDirectoryChanged

    /// Start the process after a brief delay to ensure the view is ready.
    Task { @MainActor in
      context.coordinator.startProcess()
    }

    /// Provide send function to parent.
    onTerminalReady? { text in
      terminalView.send(txt: text)
    }

    return terminalView
  }

  func updateNSView(_ nsView: OutputCapturingTerminalView, context: Context) {
    /// No updates needed.
  }

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
    weak var terminalView: OutputCapturingTerminalView?
    var workingDirectory: URL?
    var autoRunCommand: String?
    var onDirectoryChanged: ((URL) -> Void)?

    @MainActor
    func startProcess() {
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

      /// Set terminal environment variables for proper CLI operation.
      environment["TERM"] = "xterm-256color"
      environment["COLORTERM"] = "truecolor"
      environment["LANG"] = environment["LANG"] ?? "en_US.UTF-8"
      environment["LC_ALL"] = environment["LC_ALL"] ?? "en_US.UTF-8"

      /// Ensure HOME is set (required by many Node.js CLIs).
      if environment["HOME"] == nil {
        environment["HOME"] = NSHomeDirectory()
      }

      /// Ensure USER is set.
      if environment["USER"] == nil {
        environment["USER"] = NSUserName()
      }

      /// Set SHELL if not present.
      if environment["SHELL"] == nil {
        environment["SHELL"] = "/bin/zsh"
      }

      /// Force interactive mode hints for CLIs.
      environment["FORCE_COLOR"] = "1"
      environment.removeValue(forKey: "CI")
      environment["TERM_PROGRAM"] = "SlothyTerminal"

      /// Convert environment to array of strings.
      let envArray = environment.map { "\($0.key)=\($0.value)" }

      /// Change to working directory before starting process.
      FileManager.default.changeCurrentDirectoryPath(workingDirectory.path)

      /// Start an interactive login shell.
      let shell = environment["SHELL"] ?? "/bin/zsh"
      terminalView.startProcess(
        executable: shell,
        args: ["--login"],
        environment: envArray,
        execName: nil
      )

      /// Send the auto-run command after a short delay to let the shell initialize.
      if let autoRunCommand {
        Task { @MainActor in
          try? await Task.sleep(for: .milliseconds(500))
          terminalView.send(txt: "\(autoRunCommand)\n")
        }
      }
    }

    func sizeChanged(source: SwiftTerm.LocalProcessTerminalView, newCols: Int, newRows: Int) {
      /// Size change is handled internally by LocalProcessTerminalView.
    }

    func setTerminalTitle(source: SwiftTerm.LocalProcessTerminalView, title: String) {
      /// Title changes can be handled here if needed.
    }

    func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {
      /// Notify when the current directory changes.
      guard let directory,
            !directory.isEmpty
      else {
        return
      }

      /// The directory can come as a file:// URL string (OSC 7 format) or a plain path.
      let url: URL
      if directory.hasPrefix("file://") {
        /// Parse as URL string.
        guard let parsedURL = URL(string: directory) else {
          return
        }
        url = parsedURL
      } else {
        /// Treat as plain path.
        url = URL(fileURLWithPath: directory)
      }

      onDirectoryChanged?(url)
    }

    func processTerminated(source: SwiftTerm.TerminalView, exitCode: Int32?) {
      /// Process termination handling.
    }
  }
}

/// Custom LocalProcessTerminalView that captures output data and tracks commands.
class OutputCapturingTerminalView: LocalProcessTerminalView {
  var onDataReceived: ((Data) -> Void)?
  var onCommandEntered: (() -> Void)?
  private var eventMonitor: Any?

  override func dataReceived(slice: ArraySlice<UInt8>) {
    /// Call the parent implementation to display the data.
    super.dataReceived(slice: slice)

    /// Forward the data to our callback.
    let data = Data(slice)
    onDataReceived?(data)
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()

    /// Set up event monitor when view is added to window.
    if window != nil && eventMonitor == nil {
      eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        guard let self,
              self.window?.firstResponder === self || self.isDescendant(of: self.window?.firstResponder as? NSView ?? NSView())
        else {
          return event
        }

        /// Check if Enter/Return key was pressed (keyCode 36 = Return, 76 = Numpad Enter).
        if event.keyCode == 36 || event.keyCode == 76 {
          self.onCommandEntered?()
        }

        return event
      }
    }
  }

  override func removeFromSuperview() {
    /// Clean up event monitor.
    if let monitor = eventMonitor {
      NSEvent.removeMonitor(monitor)
      eventMonitor = nil
    }
    super.removeFromSuperview()
  }

  deinit {
    if let monitor = eventMonitor {
      NSEvent.removeMonitor(monitor)
    }
  }
}

/// A standalone terminal view that manages its own process.
struct StandaloneTerminalView: View {
  let workingDirectory: URL
  let command: String
  let arguments: [String]
  var onOutput: ((String) -> Void)? = nil

  /// Whether to auto-run the command (true for AI agents, false for plain terminal).
  var shouldAutoRunCommand: Bool = true

  /// Callback that provides a function to send text to the terminal.
  var onTerminalReady: ((@escaping (String) -> Void) -> Void)? = nil

  /// Callback when user enters a command (presses Enter).
  var onCommandEntered: (() -> Void)? = nil

  /// Callback when the current directory changes.
  var onDirectoryChanged: ((URL) -> Void)? = nil

  var body: some View {
    TerminalViewRepresentable(
      workingDirectory: workingDirectory,
      command: command,
      arguments: arguments,
      onOutput: onOutput,
      shouldAutoRunCommand: shouldAutoRunCommand,
      onTerminalReady: onTerminalReady,
      onCommandEntered: onCommandEntered,
      onDirectoryChanged: onDirectoryChanged
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
