import AppKit
import SwiftUI

/// The main application view containing the tab bar, terminal, and sidebar.
struct MainView: View {
  @Environment(AppState.self) private var appState
  private var configManager = ConfigManager.shared
  @State private var sidebarDragStartWidth: CGFloat?
  @State private var isSidebarResizing = false
  @State private var containerWidth: CGFloat = 800

  private let minSidebarWidth: CGFloat = 200
  private let maxSidebarWidth: CGFloat = 500
  private let minMainContentWidth: CGFloat = 420

  private var sidebarPosition: SidebarPosition {
    configManager.config.sidebarPosition
  }

  var body: some View {
    @Bindable var appState = appState

    VStack(spacing: 0) {
      TabBarView()
        .padding(.horizontal, 8)
        .padding(.top, 8)

      HStack(spacing: 0) {
        /// Sidebar on the left.
        if appState.isSidebarVisible && sidebarPosition == .left {
          SidebarContainerView()
            .frame(maxHeight: .infinity)
            .frame(width: appState.sidebarWidth)
          .padding(.vertical, 8)
          .padding(.leading, 8)

          sidebarResizeHandle(totalWidth: containerWidth)
        }

        /// Terminal container takes remaining space.
        TerminalContainerView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .padding(8)

        /// Sidebar on the right.
        if appState.isSidebarVisible && sidebarPosition == .right {
          sidebarResizeHandle(totalWidth: containerWidth)

          SidebarContainerView()
            .frame(maxHeight: .infinity)
            .frame(width: appState.sidebarWidth)
          .padding(.vertical, 8)
          .padding(.trailing, 8)
        }
      }
      .background {
        GeometryReader { proxy in
          Color.clear
            .onChange(of: proxy.size.width, initial: true) { _, newWidth in
              containerWidth = newWidth
            }
        }
      }

      /// Status bar at the bottom.
      StatusBarView()
    }
    .frame(minWidth: 800, minHeight: 600)
    .background(appBackgroundColor)
    .sheet(item: $appState.activeModal) { modal in
      ModalRouter(modal: modal)
    }
    .onAppear {
      updateWindowTitle()
    }
    .onChange(of: appState.activeTabID) {
      updateWindowTitle()
    }
    .onChange(of: appState.activeWorkspaceID) {
      updateWindowTitle()
    }
  }

  private func sidebarResizeHandle(totalWidth: CGFloat) -> some View {
    Rectangle()
      .fill(Color.clear)
      .frame(width: 8)
      .overlay {
        Rectangle()
          .fill(Color.primary.opacity(isSidebarResizing ? 0.25 : 0.12))
          .frame(width: 1)
      }
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            if sidebarDragStartWidth == nil {
              sidebarDragStartWidth = appState.sidebarWidth
            }

            isSidebarResizing = true

            let startWidth = sidebarDragStartWidth ?? appState.sidebarWidth
            let signedDelta = sidebarPosition == .left ? value.translation.width : -value.translation.width
            let proposedWidth = startWidth + signedDelta
            let clampedWidth = clampedSidebarWidth(proposedWidth, totalWidth: totalWidth)

            appState.sidebarWidth = clampedWidth
          }
          .onEnded { _ in
            sidebarDragStartWidth = nil
            isSidebarResizing = false
          }
      )
      .onHover { hovering in
        if hovering {
          NSCursor.resizeLeftRight.push()
        } else {
          NSCursor.pop()
        }
      }
  }

  private func clampedSidebarWidth(_ proposedWidth: CGFloat, totalWidth: CGFloat) -> CGFloat {
    let availableMax = max(minSidebarWidth, totalWidth - minMainContentWidth)
    let upperBound = min(maxSidebarWidth, availableMax)
    return min(max(proposedWidth, minSidebarWidth), upperBound)
  }

  /// Window title pattern: `📁 <workspace> — <directory> | Slothy Terminal`.
  private func updateWindowTitle() {
    let title = windowTitleText

    if let window = NSApplication.shared.mainWindow ?? NSApplication.shared.windows.first {
      window.title = title
      window.titleVisibility = .visible
    }
  }

  private var windowTitleText: String {
    if let activeTab = appState.activeTab {
      let directory = activeTab.workingDirectory.lastPathComponent
      if let workspace = appState.workspace(for: activeTab.workspaceID) {
        return "📁 \(workspace.name) — \(directory) | Slothy Terminal"
      }
      return "📁 \(directory) | Slothy Terminal"
    }

    return "Slothy Terminal"
  }
}

/// Status bar at the bottom of the window.
struct StatusBarView: View {
  @Environment(AppState.self) private var appState

  /// Current git branch for the active tab's directory.
  @State private var gitBranch: String?

  /// App version from bundle.
  private var appVersion: String {
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
  }

  /// Build number from bundle.
  private var buildNumber: String {
    Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
  }

  /// Whether this is a development build.
  private var isDevelopment: Bool {
    BuildConfig.isDevelopment
  }

  /// The working directory of the active tab.
  private var activeDirectory: URL? {
    appState.activeTab?.workingDirectory
  }

  /// Installed developer apps for "Open in" menu.
  private var installedApps: [ExternalApp] {
    ExternalAppManager.shared.installedApps
  }

  /// Display path with ~ prefix for home directory.
  private var displayPath: String? {
    guard let directory = activeDirectory else {
      return nil
    }

    let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
    let fullPath = directory.path

    if fullPath.hasPrefix(homeDir) {
      return "~" + fullPath.dropFirst(homeDir.count)
    }
    return fullPath
  }

  var body: some View {
    HStack(spacing: 12) {
      /// Working directory path.
      if let path = displayPath {
        HStack(spacing: 4) {
          Image(systemName: "folder.fill")
            .font(.system(size: 9))
          Text(path)
            .font(.system(size: 10))
            .lineLimit(1)
            .truncationMode(.middle)
        }
        .foregroundColor(.secondary)
      }

      /// Git branch.
      if let branch = gitBranch {
        statusSeparator

        HStack(spacing: 4) {
          Image(systemName: "arrow.triangle.branch")
            .font(.system(size: 9))
          Text(branch)
            .font(.system(size: 10))
        }
        .foregroundColor(.secondary)
      }

      /// Open in external app menu.
      if let directory = activeDirectory, !installedApps.isEmpty {
        statusSeparator

        Menu {
          ForEach(installedApps) { app in
            Button {
              ExternalAppManager.shared.openDirectory(directory, in: app)
            } label: {
              if let appIcon = app.appIcon {
                Label {
                  Text(app.name)
                } icon: {
                  Image(nsImage: appIcon)
                }
              } else {
                Label(app.name, systemImage: app.icon)
              }
            }
          }
        } label: {
          HStack(spacing: 3) {
            Image(systemName: "arrow.up.forward.app")
              .font(.system(size: 9))
            Text("Open in...")
              .font(.system(size: 10))
          }
          .foregroundColor(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
      }

      Spacer()

      /// Usage bars (hover for detail popover).
      StatusBarUsageBars()

      statusSeparator

      /// Version info on the right.
      HStack(spacing: 6) {
        Text("v\(appVersion)")
          .font(.system(size: 10))
          .foregroundColor(.secondary)

        if isDevelopment {
          Text("dev")
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(.orange)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Color.orange.opacity(0.2))
            .cornerRadius(3)
        }
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 4)
    .background(appCardColor)
    .task(id: appState.gitBranchRefreshContext) {
      await updateGitBranch()
    }
    .task {
      UsageService.shared.ensureStarted()
    }
  }

  private var statusSeparator: some View {
    Text("|")
      .font(.system(size: 10))
      .foregroundColor(.secondary.opacity(0.5))
  }

  /// Updates the git branch for the current directory.
  private func updateGitBranch() async {
    guard let directory = activeDirectory else {
      gitBranch = nil
      return
    }

    gitBranch = await GitService.shared.getCurrentBranch(in: directory)
  }
}

/// Routes to the appropriate modal view based on the modal type.
struct ModalRouter: View {
  let modal: ModalType
  @Environment(AppState.self) private var appState

  var body: some View {
    switch modal {
    case .startupPage:
      StartupPageView()

    case .startupPageSplit:
      StartupPageView(splitDestination: true)

    case .folderSelector(let agent):
      FolderSelectorModal(agent: agent) { selectedDirectory, selectedPrompt in
        appState.createTab(agent: agent, directory: selectedDirectory, initialPrompt: selectedPrompt)
      }

    case .settings:
      Text("Settings")
        .frame(width: 500, height: 400)
    }
  }
}


#Preview {
  MainView()
    .environment(AppState())
}
