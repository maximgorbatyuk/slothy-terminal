import AppKit
import SwiftUI

/// App delegate providing dock menu and other AppKit integrations.
class AppDelegate: NSObject, NSApplicationDelegate {
  private var recentFoldersManager = RecentFoldersManager.shared
  private var configManager = ConfigManager.shared
  private var windowObserver: NSObjectProtocol?

  func applicationDidFinishLaunching(_ notification: Notification) {
    /// Restore window state after a short delay to allow window to be created.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
      self?.restoreWindowState()
      self?.observeWindowChanges()
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    saveWindowState()
  }

  private func restoreWindowState() {
    guard let windowState = configManager.config.windowState,
          let window = NSApplication.shared.windows.first
    else {
      return
    }

    /// Validate the frame is on screen.
    let frame = windowState.frame
    if NSScreen.screens.contains(where: { $0.frame.intersects(frame) }) {
      window.setFrame(frame, display: true)
    }
  }

  private func saveWindowState() {
    guard let window = NSApplication.shared.windows.first else {
      return
    }

    configManager.config.windowState = WindowState(frame: window.frame)
  }

  private func observeWindowChanges() {
    windowObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.didEndLiveResizeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.saveWindowState()
    }

    /// Also observe window move.
    NotificationCenter.default.addObserver(
      forName: NSWindow.didMoveNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.saveWindowState()
    }
  }

  func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
    let menu = NSMenu()

    /// New tab items.
    let claudeItem = NSMenuItem(
      title: "New Claude Tab",
      action: #selector(newClaudeTab),
      keyEquivalent: ""
    )
    claudeItem.target = self
    menu.addItem(claudeItem)

    let glmItem = NSMenuItem(
      title: "New GLM Tab",
      action: #selector(newGLMTab),
      keyEquivalent: ""
    )
    glmItem.target = self
    menu.addItem(glmItem)

    /// Recent folders submenu.
    let recentFolders = recentFoldersManager.recentFolders
    if !recentFolders.isEmpty {
      menu.addItem(NSMenuItem.separator())

      let recentMenu = NSMenu()
      for folder in recentFolders.prefix(5) {
        let folderItem = NSMenuItem(
          title: shortenedPath(folder),
          action: #selector(openRecentFolder(_:)),
          keyEquivalent: ""
        )
        folderItem.target = self
        folderItem.representedObject = folder
        recentMenu.addItem(folderItem)
      }

      let recentMenuItem = NSMenuItem(
        title: "Recent Folders",
        action: nil,
        keyEquivalent: ""
      )
      recentMenuItem.submenu = recentMenu
      menu.addItem(recentMenuItem)
    }

    return menu
  }

  @objc private func newClaudeTab() {
    NotificationCenter.default.post(
      name: .newTabRequested,
      object: nil,
      userInfo: ["agentType": AgentType.claude]
    )
  }

  @objc private func newGLMTab() {
    NotificationCenter.default.post(
      name: .newTabRequested,
      object: nil,
      userInfo: ["agentType": AgentType.glm]
    )
  }

  @objc private func openRecentFolder(_ sender: NSMenuItem) {
    guard let folder = sender.representedObject as? URL else {
      return
    }

    NotificationCenter.default.post(
      name: .openFolderRequested,
      object: nil,
      userInfo: ["folder": folder, "agentType": AgentType.claude]
    )
  }

  private func shortenedPath(_ url: URL) -> String {
    let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
    let path = url.path
    if path.hasPrefix(homeDir) {
      return "~" + path.dropFirst(homeDir.count)
    }
    return path
  }
}

// MARK: - Notification Names

extension Notification.Name {
  static let newTabRequested = Notification.Name("newTabRequested")
  static let openFolderRequested = Notification.Name("openFolderRequested")
}
