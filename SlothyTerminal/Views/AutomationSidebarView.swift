import SwiftUI

/// Sidebar panel listing scripts in the active tab's working directory.
struct AutomationSidebarView: View {
  @Environment(AppState.self) private var appState

  @State private var scripts: [ScriptItem] = []
  @State private var isLoading = false

  private var activeDirectory: URL? {
    appState.activeTab?.workingDirectory ?? appState.globalWorkingDirectory
  }

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      scriptHint
      Divider()

      if isLoading {
        ProgressView()
          .scaleEffect(0.7)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if scripts.isEmpty {
        emptyState
      } else {
        scriptList
      }
    }
    .background(appBackgroundColor)
    .task(id: activeDirectory) {
      await refreshScripts()
    }
  }

  // MARK: - Header

  private var header: some View {
    HStack {
      HStack(spacing: 4) {
        Image(systemName: "gearshape.2")
          .font(.system(size: 10))

        Text("Scripts")
          .font(.system(size: 10, weight: .semibold))
      }
      .foregroundColor(.secondary)

      Spacer()

      Button {
        Task { await refreshScripts() }
      } label: {
        Image(systemName: "arrow.clockwise")
          .font(.system(size: 10))
          .foregroundColor(.secondary)
      }
      .buttonStyle(.plain)
      .help("Refresh")

      Text("\(scripts.count)")
        .font(.system(size: 9))
        .foregroundColor(.secondary.opacity(0.6))
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
  }

  // MARK: - Hint

  private var scriptHint: some View {
    HStack(spacing: 4) {
      Image(systemName: "info.circle")
        .font(.system(size: 9))

      Text("Supports .py and .sh scripts")
        .font(.system(size: 9))
    }
    .foregroundColor(.secondary.opacity(0.7))
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
  }

  // MARK: - Empty State

  private var emptyState: some View {
    VStack(spacing: 12) {
      Spacer()

      Image(systemName: "doc.text")
        .font(.system(size: 24))
        .foregroundColor(.secondary)

      Text("No scripts found")
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(.secondary)

      if activeDirectory != nil {
        Text("Place .py or .sh files in project root or scripts/ folder.")
          .font(.system(size: 10))
          .foregroundColor(.secondary.opacity(0.7))
          .multilineTextAlignment(.center)
      } else {
        Text("Open a tab to scan for scripts.")
          .font(.system(size: 10))
          .foregroundColor(.secondary.opacity(0.7))
          .multilineTextAlignment(.center)
      }

      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  // MARK: - Script List

  private var scriptList: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 4) {
        ForEach(scripts) { script in
          ScriptRow(script: script, onExecute: { executeScript(script) })
        }
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 6)
    }
  }

  // MARK: - Actions

  private func refreshScripts() async {
    guard let directory = activeDirectory else {
      scripts = []
      return
    }

    isLoading = true
    scripts = await ScriptScanner.shared.scan(directory: directory)
    isLoading = false
  }

  /// Escapes a string for safe use in a shell command argument.
  private static func shellEscape(_ path: String) -> String {
    "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }

  private func executeScript(_ script: ScriptItem) {
    guard let directory = activeDirectory else {
      return
    }

    let escapedPath = Self.shellEscape(script.url.path)
    let command = script.kind.executionCommand(escapedPath: escapedPath)

    appState.createTab(
      agent: .terminal,
      directory: directory,
      launchArgumentsOverride: ["-c", "\(command); echo ''; echo 'Press Enter to close...'; read"]
    )
  }
}

// MARK: - Script Row

/// A single row displaying a script's name, kind, and line count.
private struct ScriptRow: View {
  let script: ScriptItem
  let onExecute: () -> Void

  private var editorApps: [ExternalApp] {
    ExternalAppManager.shared.installedEditorApps
  }

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: script.kind.iconName)
        .font(.system(size: 10))
        .foregroundColor(.secondary)

      VStack(alignment: .leading, spacing: 2) {
        Text(script.name)
          .font(.system(size: 11, weight: .medium))
          .foregroundColor(.primary)
          .lineLimit(1)

        HStack(spacing: 4) {
          Text(script.kind.displayName)
            .font(.system(size: 9))
            .foregroundColor(.secondary.opacity(0.7))

          Text("·")
            .font(.system(size: 9))
            .foregroundColor(.secondary.opacity(0.5))

          Text("\(script.lineCount) lines")
            .font(.system(size: 9))
            .foregroundColor(.secondary.opacity(0.7))
        }
      }

      Spacer()
    }
    .padding(8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(appCardColor)
    .cornerRadius(6)
    .contextMenu {
      Button("Execute") {
        onExecute()
      }

      Divider()

      if editorApps.isEmpty {
        Button("Open (no editors found)") {}
          .disabled(true)
      } else {
        ForEach(editorApps) { app in
          Button("Open in \(app.name)") {
            ExternalAppManager.shared.openFile(script.url, in: app)
          }
        }
      }

      Divider()

      Button("Reveal in Finder") {
        NSWorkspace.shared.selectFile(
          script.url.path,
          inFileViewerRootedAtPath: script.url.deletingLastPathComponent().path
        )
      }

      Button("Copy Path") {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(script.url.path, forType: .string)
      }
    }
  }
}
