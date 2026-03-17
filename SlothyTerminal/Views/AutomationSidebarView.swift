import SwiftUI

/// Sidebar panel listing scripts in the active tab's working directory.
struct AutomationSidebarView: View {
  @Environment(AppState.self) private var appState

  @State private var scripts: [ScriptItem] = []
  @State private var isLoading = false
  @State private var actionStatus: String?
  @State private var isStatusError: Bool = false
  @State private var statusDismissTask: Task<Void, Never>?

  private var activeDirectory: URL? {
    appState.currentContextDirectory
  }

  private var isInjectable: Bool {
    guard let activeTab = appState.activeTab else {
      return false
    }

    guard activeTab.mode == .terminal else {
      return false
    }

    let injectableIds = Set(appState.listInjectableTabs())
    return injectableIds.contains(activeTab.id)
  }

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      scriptHint
      Divider()
      statusBar
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
          ScriptRow(
            script: script,
            isInsertDisabled: !isInjectable,
            onInsertPath: { insertScriptPath(script) }
          )
        }
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 6)
    }
  }

  // MARK: - Status Bar

  private var statusBar: some View {
    Group {
      if let status = actionStatus {
        HStack(spacing: 4) {
          Image(systemName: isStatusError ? "exclamationmark.circle" : "checkmark.circle")
            .font(.system(size: 9))

          Text(status)
            .font(.system(size: 9))
            .lineLimit(1)
        }
        .foregroundColor(isStatusError ? .red : .green)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .transition(.opacity)
      }
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

  private func insertScriptPath(_ script: ScriptItem) {
    guard activeTerminalIsInjectable() else {
      return
    }

    guard let directory = activeDirectory else {
      showStatus("No active directory", isError: true)
      return
    }

    var path = ScriptScanner.relativePath(from: directory, to: script.url)

    if script.kind.needsExplicitRelativePrefix && !path.hasPrefix("..") {
      path = "./\(path)"
    }

    let injectedText: String
    switch script.kind {
    case .python:
      injectedText = "python3 \(path)"

    case .shell:
      injectedText = path
    }

    let request = InjectionRequest(
      payload: .text(injectedText),
      target: .activeTab,
      origin: .ui
    )

    let result = appState.inject(request)

    guard let result else {
      showStatus("Insert failed", isError: true)
      return
    }

    switch result.status {
    case .completed, .written, .accepted, .queued:
      showStatus("Inserted: \(script.name)", isError: false)

    case .failed, .cancelled, .timeout:
      showStatus("Insert \(result.status.rawValue)", isError: true)
    }
  }

  private func activeTerminalIsInjectable() -> Bool {
    guard let activeTab = appState.activeTab else {
      showStatus("No active tab", isError: true)
      return false
    }

    guard activeTab.mode == .terminal else {
      showStatus("Active tab is not a terminal", isError: true)
      return false
    }

    let injectableIds = Set(appState.listInjectableTabs())

    guard injectableIds.contains(activeTab.id) else {
      showStatus("Terminal surface not ready", isError: true)
      return false
    }

    return true
  }

  // MARK: - Status Feedback

  private func showStatus(_ message: String, isError: Bool) {
    statusDismissTask?.cancel()

    withAnimation(.easeInOut(duration: 0.2)) {
      actionStatus = message
      isStatusError = isError
    }

    statusDismissTask = Task {
      try? await Task.sleep(nanoseconds: 2_500_000_000)

      guard !Task.isCancelled else {
        return
      }

      withAnimation(.easeInOut(duration: 0.3)) {
        actionStatus = nil
      }
    }
  }
}

// MARK: - Script Row

/// A single row displaying a script's name, kind, and line count.
private struct ScriptRow: View {
  let script: ScriptItem
  let isInsertDisabled: Bool
  let onInsertPath: () -> Void

  @State private var isHovered = false

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
    .background(isHovered ? Color.primary.opacity(0.05) : appCardColor)
    .cornerRadius(6)
    .opacity(isInsertDisabled ? 0.5 : 1.0)
    .contentShape(Rectangle())
    .onHover { hovering in
      isHovered = hovering
    }
    .onTapGesture(count: 2) {
      onInsertPath()
    }
    .help(isInsertDisabled ? "Open a terminal tab to insert script paths" : "Double-click to paste relative path to terminal")
    .contextMenu {
      Button("Insert Path to Terminal") {
        onInsertPath()
      }
      .disabled(isInsertDisabled)

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
