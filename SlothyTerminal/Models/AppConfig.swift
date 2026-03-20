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

  /// The active sidebar panel tab.
  var sidebarTab: SidebarTab = .explorer

  // MARK: - Startup Settings

  /// The default tab mode when creating a new tab via Cmd+T.
  var defaultTabMode: TabMode = .terminal

  /// The default agent to use when creating a new terminal-mode tab.
  var defaultAgent: AgentType = .claude

  /// Maximum number of recent folders to remember.
  var maxRecentFolders: Int = 10

  /// Last used launch type on the startup page, restored across sessions.
  var lastUsedLaunchType: LaunchType?

  /// Whether to launch Claude CLI with --dangerously-skip-permissions.
  var claudeSkipPermissions: Bool = false

  // MARK: - Agent Paths

  /// Custom path to Claude CLI (nil uses auto-detection).
  var claudePath: String?

  /// Custom path to OpenCode CLI (nil uses auto-detection).
  var opencodePath: String?

  // MARK: - Appearance Settings

  /// The color scheme for the app.
  var colorScheme: AppColorScheme = .system

  /// Terminal font family name.
  var terminalFontName: String = "SF Mono"

  /// Terminal font size in points.
  var terminalFontSize: CGFloat = 13

  /// How terminal mouse input is handled for TUI tabs.
  var terminalInteractionMode: TerminalInteractionMode = .hostSelection

  /// Custom accent color for Claude (nil uses default).
  var claudeAccentColor: CodableColor?

  /// Custom accent color for OpenCode (nil uses default).
  var opencodeAccentColor: CodableColor?

  // MARK: - Saved Prompts

  /// Saved reusable prompts for AI agent sessions.
  var savedPrompts: [SavedPrompt] = []

  /// Saved reusable tags for prompts.
  /// Optional for backward-compatible decoding with older config files.
  var savedPromptTags: [PromptTag]?

  /// Returns persisted prompt tags, defaulting to an empty collection.
  var promptTags: [PromptTag] {
    get {
      savedPromptTags ?? []
    }

    set {
      savedPromptTags = newValue
    }
  }

  /// Last explicitly selected model for OpenCode terminal sessions.
  var lastUsedOpenCodeModel: ChatModelSelection?

  /// Last explicitly selected mode for OpenCode terminal sessions.
  var lastUsedOpenCodeMode: ChatMode?

  /// Whether OpenCode should prefer asking clarifying questions first.
  var lastUsedOpenCodeAskModeEnabled: Bool = false

  // MARK: - Keyboard Shortcuts

  /// Custom keyboard shortcuts.
  var shortcuts: [String: String] = [:]

  // MARK: - Window State

  /// Saved window state for restoration.
  var windowState: WindowState?

  // MARK: - Default Config

  /// Creates a configuration with all default values.
  init() {}

  /// Returns the default configuration.
  static var `default`: AppConfig {
    AppConfig()
  }

  // MARK: - Resilient Decoding

  /// Decodes each field individually so that missing or unknown keys
  /// fall back to their default values instead of failing the entire decode.
  /// This prevents settings from being silently reset when new fields
  /// are added to `AppConfig`.
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let d = AppConfig()

    sidebarWidth = (try? c.decode(CGFloat.self, forKey: .sidebarWidth)) ?? d.sidebarWidth
    showSidebarByDefault = (try? c.decode(Bool.self, forKey: .showSidebarByDefault)) ?? d.showSidebarByDefault
    sidebarPosition = (try? c.decode(SidebarPosition.self, forKey: .sidebarPosition)) ?? d.sidebarPosition
    sidebarTab = (try? c.decode(SidebarTab.self, forKey: .sidebarTab)) ?? d.sidebarTab

    let decodedTabMode = (try? c.decode(TabMode.self, forKey: .defaultTabMode)) ?? d.defaultTabMode
    defaultTabMode = TabMode.defaultOptions.contains(decodedTabMode) ? decodedTabMode : d.defaultTabMode
    defaultAgent = (try? c.decode(AgentType.self, forKey: .defaultAgent)) ?? d.defaultAgent
    maxRecentFolders = (try? c.decode(Int.self, forKey: .maxRecentFolders)) ?? d.maxRecentFolders
    lastUsedLaunchType = try? c.decode(LaunchType.self, forKey: .lastUsedLaunchType)
    claudeSkipPermissions = (try? c.decode(Bool.self, forKey: .claudeSkipPermissions)) ?? d.claudeSkipPermissions

    claudePath = try? c.decode(String.self, forKey: .claudePath)
    opencodePath = try? c.decode(String.self, forKey: .opencodePath)

    colorScheme = (try? c.decode(AppColorScheme.self, forKey: .colorScheme)) ?? d.colorScheme
    terminalFontName = (try? c.decode(String.self, forKey: .terminalFontName)) ?? d.terminalFontName
    terminalFontSize = (try? c.decode(CGFloat.self, forKey: .terminalFontSize)) ?? d.terminalFontSize
    terminalInteractionMode = (try? c.decode(TerminalInteractionMode.self, forKey: .terminalInteractionMode)) ?? d.terminalInteractionMode
    claudeAccentColor = try? c.decode(CodableColor.self, forKey: .claudeAccentColor)
    opencodeAccentColor = try? c.decode(CodableColor.self, forKey: .opencodeAccentColor)

    savedPrompts = (try? c.decode([SavedPrompt].self, forKey: .savedPrompts)) ?? d.savedPrompts
    savedPromptTags = try? c.decode([PromptTag].self, forKey: .savedPromptTags)

    lastUsedOpenCodeModel = try? c.decode(ChatModelSelection.self, forKey: .lastUsedOpenCodeModel)
    lastUsedOpenCodeMode = try? c.decode(ChatMode.self, forKey: .lastUsedOpenCodeMode)
    lastUsedOpenCodeAskModeEnabled = (try? c.decode(Bool.self, forKey: .lastUsedOpenCodeAskModeEnabled)) ?? d.lastUsedOpenCodeAskModeEnabled

    shortcuts = (try? c.decode([String: String].self, forKey: .shortcuts)) ?? d.shortcuts

    windowState = try? c.decode(WindowState.self, forKey: .windowState)
  }
}

// MARK: - Supporting Types

/// Controls how mouse input is routed in terminal tabs.
enum TerminalInteractionMode: String, Codable, CaseIterable {
  case hostSelection
  case appMouse

  var displayName: String {
    switch self {
    case .hostSelection:
      return "Host Selection"

    case .appMouse:
      return "App Mouse"
    }
  }

  /// Whether mouse events should be forwarded to the process.
  var allowsMouseReporting: Bool {
    switch self {
    case .hostSelection:
      return false

    case .appMouse:
      return true
    }
  }

  /// Short explanation shown in settings.
  var description: String {
    switch self {
    case .hostSelection:
      return "Use mouse for terminal text selection and copy."

    case .appMouse:
      return "Send mouse events to the running TUI for in-app interactions."
    }
  }
}

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

/// Sidebar panel tabs.
enum SidebarTab: String, Codable, CaseIterable, Identifiable {
  case workspaces
  case explorer
  case gitChanges
  case prompts
  case automation

  var id: String { rawValue }

  var iconName: String {
    switch self {
    case .workspaces:
      return "square.grid.2x2"

    case .explorer:
      return "folder"

    case .gitChanges:
      return "arrow.triangle.branch"

    case .prompts:
      return "text.bubble"

    case .automation:
      return "gearshape.2"
    }
  }

  var tooltip: String {
    switch self {
    case .workspaces:
      return "Workspaces"

    case .explorer:
      return "Current directory"

    case .gitChanges:
      return "Git Changes"

    case .prompts:
      return "Prompts"

    case .automation:
      return "Automation"
    }
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let rawValue = try container.decode(String.self)

    self = SidebarTab(rawValue: rawValue) ?? .explorer
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
      return "New Claude TUI Tab"
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
