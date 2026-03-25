import AppKit
import Combine
import SwiftUI

/// The sidebar showing usage statistics for the active tab.
struct SidebarView: View {
  @Environment(AppState.self) private var appState

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {

      if let tab = appState.activeTab {
        TerminalSidebarView(tab: tab)
      } else {
        EmptySidebarView()
      }

      Spacer()
    }
    .padding()
    .background(appBackgroundColor)
  }
}

/// Empty state when no tab is active.
struct EmptySidebarView: View {
  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: "chart.bar")
        .font(.system(size: 32))
        .foregroundColor(.secondary)

      Text("No active session")
        .font(.system(size: 12))
        .foregroundColor(.secondary)

      Text("Create a tab to view usage statistics")
        .font(.system(size: 11))
        .foregroundColor(.secondary)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding()
  }
}

/// Sidebar view for plain terminal tabs.
struct TerminalSidebarView: View {
  let tab: Tab

  var body: some View {
    VStack(spacing: 16) {
      /// Directory tree.
      DirectoryTreeView(rootDirectory: tab.workingDirectory)

      /// Usage stats.
      UsageStatsView()

      /// Project docs.
      ProjectDocsView(workingDirectory: tab.workingDirectory)
    }
  }
}

/// Collapsible directory tree showing files and folders.
struct DirectoryTreeView: View {
  let rootDirectory: URL
  @State private var isExpanded: Bool = true
  @State private var items: [FileItem] = []
  @State private var isLoading = false
  @State private var lastLoadedRootDirectory: URL?
  @State private var rootLoadGeneration = 0

  private var loadKey: String {
    "\(rootDirectory.path)|\(isExpanded)"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      /// Header with expand/collapse toggle.
      Button {
        isExpanded.toggle()
      } label: {
        HStack {
          Image(systemName: "folder.fill")
            .font(.system(size: 10))

          Text("Files")
            .font(.system(size: 10, weight: .semibold))

          Spacer()

          Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
            .font(.system(size: 10))
        }
        .foregroundColor(.secondary)
      }
      .buttonStyle(.plain)

      if isExpanded {
        /// Hint text.
        Text("Double-click to copy path. Right-click for more options.")
          .font(.system(size: 9))
          .foregroundColor(.secondary)
          .opacity(0.7)

        /// Tree content in a card.
        ScrollView {
          VStack(alignment: .leading, spacing: 0) {
            if isLoading {
              HStack(spacing: 8) {
                ProgressView()
                  .controlSize(.small)

                Text("Loading files...")
                  .font(.system(size: 11))
                  .foregroundColor(.secondary)
              }
              .padding(.vertical, 8)
            } else if items.isEmpty {
              Text("No files")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .padding(.vertical, 8)
            } else {
              ForEach($items) { $item in
                FileItemRow(item: $item, depth: 0, rootDirectory: rootDirectory)
              }
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 300)
        .padding(10)
        .background(appCardColor)
        .cornerRadius(8)
      }
    }
    .task(id: loadKey) {
      guard isExpanded else {
        rootLoadGeneration += 1
        isLoading = false
        return
      }

      guard lastLoadedRootDirectory != rootDirectory || items.isEmpty else {
        isLoading = false
        return
      }

      let directory = rootDirectory
      rootLoadGeneration += 1
      let loadGeneration = rootLoadGeneration
      isLoading = true

      if lastLoadedRootDirectory != directory {
        items = []
      }

      let loadedItems = await DirectoryTreeManager.shared.loadItems(in: directory)

      guard !Task.isCancelled,
            rootDirectory == directory,
            isExpanded,
            rootLoadGeneration == loadGeneration
      else {
        return
      }

      items = loadedItems
      lastLoadedRootDirectory = directory
      isLoading = false
    }
  }
}

/// A single row in the directory tree representing a file or folder.
struct FileItemRow: View {
  @Binding var item: FileItem
  let depth: Int
  let rootDirectory: URL
  @State private var showCopiedTooltip: Bool = false
  @State private var childLoadTask: Task<Void, Never>?

  /// Relative path from the root directory.
  private var relativePath: String {
    let fullPath = item.url.path
    let rootPath = rootDirectory.path

    if fullPath.hasPrefix(rootPath) {
      let relative = String(fullPath.dropFirst(rootPath.count))
      if relative.hasPrefix("/") {
        return String(relative.dropFirst())
      }
      return relative.isEmpty ? item.name : relative
    }

    return item.name
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 4) {
        /// Indentation based on depth.
        if depth > 0 {
          Spacer()
            .frame(width: CGFloat(depth) * 12)
        }

        /// Expand/collapse chevron for directories.
        if item.isDirectory {
          Image(systemName: item.isExpanded ? "chevron.down" : "chevron.right")
            .font(.system(size: 8))
            .foregroundColor(.secondary)
            .frame(width: 10)
        } else {
          Spacer()
            .frame(width: 10)
        }

        /// File/folder icon.
        Image(nsImage: item.icon)
          .resizable()
          .frame(width: 14, height: 14)

        /// Name.
        Text(item.name)
          .font(.system(size: 11))
          .lineLimit(1)
          .truncationMode(.middle)

        Spacer()
      }
      .padding(.vertical, 3)
      .contentShape(Rectangle())
      .onTapGesture(count: 1) {
        if item.isDirectory {
          toggleExpand()
        }
      }
      .onTapGesture(count: 2) {
        copyToClipboard(relativePath)
      }
      .contextMenu {
        Button("Copy Relative Path") {
          copyToClipboard(relativePath)
        }

        Button("Copy Filename") {
          copyToClipboard(item.name)
        }

        Button("Copy Full Path") {
          copyToClipboard(item.url.path)
        }
      }
      .overlay(alignment: .trailing) {
        if showCopiedTooltip {
          Text("Copied!")
            .font(.system(size: 9))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.green.opacity(0.9))
            .foregroundColor(.white)
            .cornerRadius(4)
            .transition(.opacity)
        }
      }

      /// Render children if expanded.
      if item.isDirectory && item.isExpanded {
        if item.isLoadingChildren {
          HStack(spacing: 6) {
            Spacer()
              .frame(width: CGFloat(depth + 1) * 12 + 20)

            ProgressView()
              .controlSize(.small)

            Text("Loading...")
              .font(.system(size: 10))
              .foregroundColor(.secondary)
          }
          .padding(.vertical, 3)
        } else {
          ForEach($item.children) { $child in
            FileItemRow(item: $child, depth: depth + 1, rootDirectory: rootDirectory)
          }
        }
      }
    }
    .onDisappear {
      childLoadTask?.cancel()
      childLoadTask = nil

      if item.isLoadingChildren {
        item.childLoadGeneration += 1
        item.isExpanded = false
        item.isLoadingChildren = false
      }
    }
  }

  private func toggleExpand() {
    item.isExpanded.toggle()

    guard item.isDirectory else {
      return
    }

    if !item.isExpanded {
      childLoadTask?.cancel()
      childLoadTask = nil
      item.childLoadGeneration += 1
      item.isLoadingChildren = false
      return
    }

    guard !item.didLoadChildren, !item.isLoadingChildren else {
      return
    }

    let itemID = item.id
    let itemURL = item.url
    item.childLoadGeneration += 1
    let loadGeneration = item.childLoadGeneration

    item.isLoadingChildren = true
    childLoadTask?.cancel()
    childLoadTask = Task { @MainActor in
      let children = await DirectoryTreeManager.shared.loadChildren(in: itemURL)

      guard item.id == itemID,
            item.childLoadGeneration == loadGeneration
      else {
        return
      }

      guard !Task.isCancelled, item.isExpanded else {
        item.isLoadingChildren = false
        return
      }

      item.children = children
      item.didLoadChildren = true
      item.isLoadingChildren = false
    }
  }

  private func copyToClipboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)

    withAnimation {
      showCopiedTooltip = true
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
      withAnimation {
        showCopiedTooltip = false
      }
    }
  }
}

/// Collapsible section showing project documentation files (README.md, AGENTS.md, CLAUDE.md).
///
/// Resolves the docs root from the git repository top-level when available,
/// falling back to the provided working directory. Only shows files that exist.
struct ProjectDocsView: View {
  let workingDirectory: URL

  @State private var isExpanded: Bool = true
  @State private var existingDocs: [(name: String, url: URL)] = []

  /// Fixed ordered list of project doc filenames to look for.
  private static let docFileNames = ["README.md", "AGENTS.md", "CLAUDE.md"]

  var body: some View {
    Group {
      if !existingDocs.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
          /// Header with expand/collapse toggle.
          Button {
            isExpanded.toggle()
          } label: {
            HStack {
              Image(systemName: "doc.text.fill")
                .font(.system(size: 10))

              Text("Project docs")
                .font(.system(size: 10, weight: .semibold))

              Spacer()

              Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 10))
            }
            .foregroundColor(.secondary)
          }
          .buttonStyle(.plain)

          if isExpanded {
            VStack(alignment: .leading, spacing: 0) {
              ForEach(existingDocs, id: \.name) { doc in
                ProjectDocRow(name: doc.name, url: doc.url)
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(appCardColor)
            .cornerRadius(8)
          }
        }
      }
    }
    .task(id: workingDirectory) {
      let root = await GitService.shared.getRepositoryRoot(for: workingDirectory) ?? workingDirectory

      var found: [(name: String, url: URL)] = []
      for name in Self.docFileNames {
        let fileURL = root.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: fileURL.path) {
          found.append((name: name, url: fileURL))
        }
      }

      existingDocs = found
    }
  }
}

/// A single row representing a project documentation file.
struct ProjectDocRow: View {
  let name: String
  let url: URL

  private var editorApps: [ExternalApp] {
    ExternalAppManager.shared.installedEditorApps
  }

  var body: some View {
    HStack(spacing: 4) {
      Image(nsImage: DirectoryTreeManager.shared.fileIcon(for: url))
        .resizable()
        .frame(width: 14, height: 14)

      Text(name)
        .font(.system(size: 11))
        .lineLimit(1)

      Spacer()

      Button {
        openInDefaultEditor()
      } label: {
        Image(systemName: "square.and.pencil")
          .font(.system(size: 10))
          .foregroundColor(.secondary)
      }
      .buttonStyle(.plain)
      .help("Open in editor")
    }
    .padding(.vertical, 3)
    .contentShape(Rectangle())
    .contextMenu {
      Button("Open in Default Editor") {
        openInDefaultEditor()
      }

      if !editorApps.isEmpty {
        Divider()

        ForEach(editorApps) { app in
          Button("Open in \(app.name)") {
            ExternalAppManager.shared.openFile(url, in: app)
          }
        }
      }

      Divider()

      Button("Reveal in Finder") {
        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
      }

      Button("Copy Path") {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
      }
    }
  }

  private func openInDefaultEditor() {
    if let firstEditor = editorApps.first {
      ExternalAppManager.shared.openFile(url, in: firstEditor)
    } else {
      NSWorkspace.shared.open(url)
    }
  }
}

/// A section of statistics with a title.
struct StatsSection<Content: View>: View {
  let title: String
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.system(size: 10, weight: .semibold))
        .textCase(.uppercase)
        .foregroundColor(.secondary)

      VStack(spacing: 6) {
        content
      }
      .padding(10)
      .background(appCardColor)
      .cornerRadius(8)
    }
  }
}

/// Style for stat row values.
enum StatRowStyle {
  case normal
  case cost
  case warning
}

/// A single row displaying a stat label and value.
struct StatRow: View {
  let label: String
  let value: String
  var isHighlighted: Bool = false
  var style: StatRowStyle = .normal

  private var valueColor: Color {
    switch style {
    case .normal:
      return isHighlighted ? .primary : .secondary
    case .cost:
      return .orange
    case .warning:
      return .red
    }
  }

  var body: some View {
    HStack {
      Text(label)
        .font(.system(size: 11))
        .foregroundColor(.secondary)

      Spacer()

      Text(value)
        .font(.system(size: 11, weight: isHighlighted ? .semibold : .regular))
        .foregroundColor(valueColor)
        .monospacedDigit()
    }
  }
}

#Preview("With Active Tab") {
  let appState = AppState()
  let tab = Tab(workspaceID: UUID(), agentType: .claude, workingDirectory: URL(fileURLWithPath: "/Users/demo/projects"))
  appState.tabs.append(tab)
  appState.activeTabID = tab.id

  return SidebarView()
    .environment(appState)
    .frame(width: 260, height: 600)
}

#Preview("Empty State") {
  SidebarView()
    .environment(AppState())
    .frame(width: 260, height: 600)
}
