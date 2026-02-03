import AppKit
import Foundation

/// Represents an external application that can open directories.
struct ExternalApp: Identifiable {
  /// Bundle identifier used as unique ID.
  let id: String

  /// Display name of the application.
  let name: String

  /// SF Symbol name for fallback icon.
  let icon: String

  /// Whether the application is installed on this system.
  var isInstalled: Bool {
    NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil
  }

  /// The application's icon from the system.
  var appIcon: NSImage? {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
      return nil
    }

    return NSWorkspace.shared.icon(forFile: url.path)
  }
}

/// Manages detection and launching of external developer applications.
final class ExternalAppManager {
  /// Shared singleton instance.
  static let shared = ExternalAppManager()

  /// List of known developer applications.
  let knownApps: [ExternalApp] = [
    ExternalApp(id: "com.anthropic.claudefordesktop", name: "Claude", icon: "bubble.left"),
    ExternalApp(id: "com.openai.chat", name: "ChatGPT", icon: "bubble.right"),
    ExternalApp(id: "com.openai.codex", name: "Codex", icon: "terminal"),
    ExternalApp(id: "com.microsoft.VSCode", name: "VS Code", icon: "chevron.left.forwardslash.chevron.right"),
    ExternalApp(id: "com.todesktop.230313mzl4w4u92", name: "Cursor", icon: "cursorarrow"),
    ExternalApp(id: "com.google.antigravity", name: "Antigravity", icon: "antigravity"),
    ExternalApp(id: "com.jetbrains.rider", name: "Rider", icon: "r.square"),
    ExternalApp(id: "com.jetbrains.idea", name: "IntelliJ", icon: "idea"),
    ExternalApp(id: "com.mitchellh.ghostty", name: "Ghostty", icon: "terminal"),
    ExternalApp(id: "com.apple.dt.Xcode", name: "Xcode", icon: "hammer"),
    ExternalApp(id: "com.sublimetext.4", name: "Sublime Text", icon: "text.alignleft"),
    ExternalApp(id: "com.googlecode.iterm2", name: "iTerm", icon: "terminal"),
    ExternalApp(id: "com.apple.Terminal", name: "Terminal", icon: "terminal"),
    ExternalApp(id: "dev.warp.Warp-Stable", name: "Warp", icon: "terminal"),
    ExternalApp(id: "com.panic.Nova", name: "Nova", icon: "star"),
    ExternalApp(id: "com.barebones.bbedit", name: "BBEdit", icon: "doc.text"),
    ExternalApp(id: "com.macromates.TextMate", name: "TextMate", icon: "doc.text"),
    ExternalApp(id: "com.jetbrains.fleet", name: "Fleet", icon: "bolt"),
  ]

  private init() {}

  /// Returns only the apps that are currently installed.
  var installedApps: [ExternalApp] {
    knownApps.filter { $0.isInstalled }
  }

  /// Opens a directory in the specified application.
  func openDirectory(_ url: URL, in app: ExternalApp) {
    guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.id) else {
      return
    }

    let configuration = NSWorkspace.OpenConfiguration()
    configuration.arguments = [url.path]

    NSWorkspace.shared.openApplication(
      at: appURL,
      configuration: configuration
    ) { _, error in
      if let error {
        print("Failed to open \(app.name): \(error)")
      }
    }
  }
}
