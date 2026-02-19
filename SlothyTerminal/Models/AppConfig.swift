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
  var defaultTabMode: TabMode = .chat

  /// The default agent to use when creating a new terminal-mode tab.
  var defaultAgent: AgentType = .claude

  /// Maximum number of recent folders to remember.
  var maxRecentFolders: Int = 10

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

  // MARK: - Chat Settings

  /// Which key sends a chat message (the other key inserts a newline).
  var chatSendKey: ChatSendKey = .enter

  /// Default render mode for chat messages.
  var chatRenderMode: ChatRenderMode = .markdown

  /// Text size for chat messages.
  var chatMessageTextSize: ChatMessageTextSize = .medium

  /// Whether to show timestamps on completed assistant messages.
  var chatShowTimestamps: Bool = true

  /// Whether to show token counts on completed assistant messages.
  var chatShowTokenMetadata: Bool = true

  /// Last explicitly selected model for OpenCode chat.
  /// Used to preselect model in new OpenCode chat tabs.
  var lastUsedOpenCodeModel: ChatModelSelection?

  /// Last explicitly selected mode for OpenCode chat.
  /// Used to preselect Build/Plan in new OpenCode chat tabs.
  var lastUsedOpenCodeMode: ChatMode?

  /// Whether OpenCode chat should prefer asking clarifying questions first.
  /// Used to preselect Ask mode in new OpenCode chat tabs.
  var lastUsedOpenCodeAskModeEnabled: Bool = false

  // MARK: - Keyboard Shortcuts

  /// Custom keyboard shortcuts.
  var shortcuts: [String: String] = [:]

  // MARK: - Telegram Settings

  /// Bot token for the Telegram Bot API.
  var telegramBotToken: String?

  /// User ID allowed to interact with the bot.
  var telegramAllowedUserID: Int64?

  /// Which agent to use for prompt execution.
  var telegramExecutionAgent: AgentType = .claude

  /// Whether the bot auto-starts when the tab is opened.
  var telegramAutoStartOnOpen: Bool = true

  /// Default listen mode when the bot starts.
  var telegramDefaultListenMode: TelegramBotMode = .passive

  /// Optional prefix prepended to bot replies.
  var telegramReplyPrefix: String?

  /// Root directory path for /open-directory command.
  var telegramRootDirectoryPath: String?

  /// Predefined subfolder appended to root directory for /open-directory.
  var telegramPredefinedOpenSubpath: String?

  /// Tab mode for tabs opened via /open-directory.
  var telegramOpenDirectoryTabMode: TabMode = .chat

  /// Agent type for tabs opened via /open-directory.
  var telegramOpenDirectoryAgent: AgentType = .claude

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

/// Which key sends a chat message.
enum ChatSendKey: String, Codable, CaseIterable {
  case enter = "Enter"
  case shiftEnter = "Shift+Enter"

  var displayName: String { rawValue }

  /// The key combination that inserts a newline (the opposite of sendKey).
  var newlineHint: String {
    switch self {
    case .enter:
      return "Shift+Return for new line"

    case .shiftEnter:
      return "Return for new line"
    }
  }
}

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

/// Chat message render mode.
enum ChatRenderMode: String, Codable, CaseIterable {
  case markdown
  case plainText

  var displayName: String {
    switch self {
    case .markdown:
      return "Markdown"

    case .plainText:
      return "Plain Text"
    }
  }
}

/// Chat message text size.
enum ChatMessageTextSize: String, Codable, CaseIterable {
  case small
  case medium
  case large

  var displayName: String {
    switch self {
    case .small:
      return "Small"

    case .medium:
      return "Medium"

    case .large:
      return "Large"
    }
  }

  /// Font size in points for message body text.
  var bodyFontSize: CGFloat {
    switch self {
    case .small:
      return 12

    case .medium:
      return 13

    case .large:
      return 15
    }
  }

  /// Font size in points for metadata and captions.
  var metadataFontSize: CGFloat {
    switch self {
    case .small:
      return 9

    case .medium:
      return 10

    case .large:
      return 11
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
  case explorer
  case gitChanges
  case tasks
  case automation

  var id: String { rawValue }

  var iconName: String {
    switch self {
    case .explorer:
      return "folder"

    case .gitChanges:
      return "arrow.triangle.branch"

    case .tasks:
      return "checklist"

    case .automation:
      return "gearshape.2"
    }
  }

  var tooltip: String {
    switch self {
    case .explorer:
      return "Explorer"

    case .gitChanges:
      return "Git Changes"

    case .tasks:
      return "Tasks"

    case .automation:
      return "Automation"
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
  case newChatTab
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
    case .newChatTab:
      return "New Chat Tab"
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
    case .newChatTab:
      return "⌘T"
    case .newTerminalTab:
      return "⌘⇧⌥T"
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
    case .newChatTab, .newTerminalTab, .newClaudeTab, .newOpencodeTab, .closeTab, .nextTab, .previousTab:
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
