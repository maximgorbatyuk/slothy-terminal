import SwiftUI

/// Application configuration that persists between sessions.
struct AppConfig: Codable, Equatable {
  // MARK: - Sidebar Settings

  /// Width of the sidebar in points.
  var sidebarWidth: CGFloat = 260

  /// Whether to show the sidebar by default when opening the app.
  var showSidebarByDefault: Bool = true

  /// Position of the sidebar.
  var sidebarPosition: SidebarPosition = .right

  // MARK: - Startup Settings

  /// The default agent to use when creating a new tab.
  var defaultAgent: AgentType = .claude

  /// Maximum number of recent folders to remember.
  var maxRecentFolders: Int = 10

  // MARK: - Agent Paths

  /// Custom path to Claude CLI (nil uses auto-detection).
  var claudePath: String?

  /// Custom path to OpenCode CLI (nil uses auto-detection).
  var opencodePath: String?

  // MARK: - Appearance Settings

  /// The color scheme for the app (always dark).
  var colorScheme: AppColorScheme = .dark

  /// Terminal font family name.
  var terminalFontName: String = "SF Mono"

  /// Terminal font size in points.
  var terminalFontSize: CGFloat = 13

  /// Custom accent color for Claude (nil uses default).
  var claudeAccentColor: CodableColor?

  /// Custom accent color for OpenCode (nil uses default).
  var opencodeAccentColor: CodableColor?

  // MARK: - Saved Prompts

  /// Saved reusable prompts for AI agent sessions.
  var savedPrompts: [SavedPrompt] = []

  // MARK: - Keyboard Shortcuts

  /// Custom keyboard shortcuts.
  var shortcuts: [String: String] = [:]

  // MARK: - Window State

  /// Saved window state for restoration.
  var windowState: WindowState?

  // MARK: - Default Config

  /// Returns the default configuration.
  static var `default`: AppConfig {
    AppConfig()
  }
}

// MARK: - Supporting Types

/// Sidebar position options.
enum SidebarPosition: String, Codable, CaseIterable {
  case left
  case right

  var displayName: String {
    switch self {
    case .left:
      return "Left"
    case .right:
      return "Right"
    }
  }
}

/// Color scheme options.
enum AppColorScheme: String, Codable, CaseIterable {
  case light
  case dark
  case system

  var displayName: String {
    switch self {
    case .light:
      return "Light"
    case .dark:
      return "Dark"
    case .system:
      return "System"
    }
  }

  /// Converts to SwiftUI ColorScheme.
  var colorScheme: ColorScheme? {
    switch self {
    case .light:
      return .light
    case .dark:
      return .dark
    case .system:
      return nil
    }
  }
}

/// A Codable wrapper for Color.
struct CodableColor: Codable, Equatable {
  var red: Double
  var green: Double
  var blue: Double
  var opacity: Double

  init(red: Double, green: Double, blue: Double, opacity: Double = 1.0) {
    self.red = red
    self.green = green
    self.blue = blue
    self.opacity = opacity
  }

  init(_ color: Color) {
    /// Convert Color to NSColor to extract components.
    let nsColor = NSColor(color)
    let rgbColor = nsColor.usingColorSpace(.deviceRGB) ?? nsColor

    self.red = Double(rgbColor.redComponent)
    self.green = Double(rgbColor.greenComponent)
    self.blue = Double(rgbColor.blueComponent)
    self.opacity = Double(rgbColor.alphaComponent)
  }

  var color: Color {
    Color(red: red, green: green, blue: blue, opacity: opacity)
  }

  /// Returns hex string representation.
  var hexString: String {
    let r = Int(red * 255)
    let g = Int(green * 255)
    let b = Int(blue * 255)
    return String(format: "#%02X%02X%02X", r, g, b)
  }
}

// MARK: - Shortcut Actions

/// Actions that can have keyboard shortcuts assigned.
enum ShortcutAction: String, Codable, CaseIterable {
  case newTerminalTab
  case newClaudeTab
  case newOpencodeTab
  case closeTab
  case nextTab
  case previousTab
  case toggleSidebar
  case focusTerminal
  case openSettings

  var displayName: String {
    switch self {
    case .newTerminalTab:
      return "New Terminal Tab"
    case .newClaudeTab:
      return "New Claude Tab"
    case .newOpencodeTab:
      return "New OpenCode Tab"
    case .closeTab:
      return "Close Tab"
    case .nextTab:
      return "Next Tab"
    case .previousTab:
      return "Previous Tab"
    case .toggleSidebar:
      return "Toggle Sidebar"
    case .focusTerminal:
      return "Focus Terminal"
    case .openSettings:
      return "Open Settings"
    }
  }

  var defaultShortcut: String {
    switch self {
    case .newTerminalTab:
      return "⌘T"
    case .newClaudeTab:
      return "⌘⇧T"
    case .newOpencodeTab:
      return "⌘⌥T"
    case .closeTab:
      return "⌘W"
    case .nextTab:
      return "⌘⇧]"
    case .previousTab:
      return "⌘⇧["
    case .toggleSidebar:
      return "⌘B"
    case .focusTerminal:
      return "⌘1"
    case .openSettings:
      return "⌘,"
    }
  }

  var category: ShortcutCategory {
    switch self {
    case .newTerminalTab, .newClaudeTab, .newOpencodeTab, .closeTab, .nextTab, .previousTab:
      return .tabs
    case .toggleSidebar:
      return .view
    case .focusTerminal:
      return .terminal
    case .openSettings:
      return .app
    }
  }
}

/// Categories for grouping shortcuts.
enum ShortcutCategory: String, CaseIterable {
  case tabs
  case view
  case terminal
  case app

  var displayName: String {
    switch self {
    case .tabs:
      return "Tabs"
    case .view:
      return "View"
    case .terminal:
      return "Terminal"
    case .app:
      return "Application"
    }
  }
}

/// Saved window state for restoration.
struct WindowState: Codable, Equatable {
  var x: CGFloat
  var y: CGFloat
  var width: CGFloat
  var height: CGFloat

  init(frame: CGRect) {
    self.x = frame.origin.x
    self.y = frame.origin.y
    self.width = frame.size.width
    self.height = frame.size.height
  }

  init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
  }

  var frame: CGRect {
    CGRect(x: x, y: y, width: width, height: height)
  }
}
