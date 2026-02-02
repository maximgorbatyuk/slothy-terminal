# Implementation Plan: Slothy Terminal Application (Swift)

## Project Overview

Create a native macOS terminal application using Swift and SwiftUI that supports multiple AI agents (Claude CLI and GLM) with folder selection, usage statistics, and tabbed interface.

## Technology Stack

- **Language**: Swift 5.9+
- **UI Framework**: SwiftUI + AppKit (for terminal rendering)
- **PTY Handling**: Native POSIX APIs (`forkpty`, `posix_spawn`)
- **Terminal Emulation**: SwiftTerm library or custom implementation
- **Build System**: Swift Package Manager + Xcode

---

## Phase 1: Project Foundation

### 1.1 Project Setup
- Create new macOS app in Xcode with SwiftUI lifecycle
- Configure minimum deployment target (macOS 13+)
- Add Swift Package dependencies:
  - `SwiftTerm` (terminal emulation)
  - Or build custom PTY wrapper
- Create project structure:
  ```
  SlothyTerminal/
    App/
      SlothyTerminalApp.swift
      AppState.swift
    Views/
      MainView.swift
      TerminalView.swift
      TabBarView.swift
      SidebarView.swift
      FolderSelectorModal.swift
    Models/
      Tab.swift
      AgentType.swift
      UsageStats.swift
    Terminal/
      PTYController.swift
      TerminalEmulator.swift
      ANSIParser.swift
    Agents/
      AgentProtocol.swift
      ClaudeAgent.swift
      GLMAgent.swift
    Services/
      StatsParser.swift
      ConfigManager.swift
    Resources/
      Config.swift
  ```

### 1.2 PTY Implementation
- Create `PTYController` class wrapping POSIX `forkpty()`
- Handle file descriptor management
- Implement async read/write with Swift Concurrency
- Proper cleanup on process termination

```swift
// PTYController.swift
class PTYController: ObservableObject {
    private var masterFD: Int32 = -1
    private var childPID: pid_t = 0
    
    func spawn(command: String, args: [String], workingDirectory: URL) async throws
    func write(_ data: Data) async throws
    func read() -> AsyncStream<Data>
    func resize(cols: Int, rows: Int)
    func terminate()
}
```

### 1.3 Basic Terminal View
- Integrate SwiftTerm or build custom terminal renderer
- Handle keyboard input capture
- Render terminal output with proper fonts
- Support terminal resize

---

## Phase 2: Application Architecture

### 2.1 App State Management
- Create main `AppState` as `@Observable` class
- Manage tabs collection
- Handle global keyboard shortcuts
- Persist state between launches

```swift
// AppState.swift
@Observable
class AppState {
    var tabs: [Tab] = []
    var activeTabID: UUID?
    var isSidebarVisible: Bool = true
    var sidebarWidth: CGFloat = 260
    var activeModal: ModalType? = nil
    
    func createTab(agent: AgentType, directory: URL)
    func closeTab(id: UUID)
    func switchToTab(id: UUID)
}
```

### 2.2 Tab Model
```swift
// Tab.swift
@Observable
class Tab: Identifiable {
    let id: UUID
    let agentType: AgentType
    var workingDirectory: URL
    var title: String
    var ptyController: PTYController
    var terminalBuffer: TerminalBuffer
    var usageStats: UsageStats
    var isActive: Bool
}

enum AgentType: String, CaseIterable {
    case claude = "Claude"
    case glm = "GLM"
    
    var command: String { ... }
    var icon: String { ... }
    var accentColor: Color { ... }
}
```

### 2.3 Main Window Layout
```swift
// MainView.swift
struct MainView: View {
    @Environment(AppState.self) var appState
    
    var body: some View {
        VStack(spacing: 0) {
            TabBarView()
            HStack(spacing: 0) {
                // Terminal on left (flex)
                TerminalContainerView()
                
                // Sidebar on right (fixed width)
                if appState.isSidebarVisible {
                    SidebarView()
                        .frame(width: appState.sidebarWidth)
                }
            }
        }
        .sheet(item: $appState.activeModal) { modal in
            ModalRouter(modal: modal)
        }
    }
}
```

---

## Phase 3: Tabbed Interface

### 3.1 Tab Bar Component
```swift
// TabBarView.swift
struct TabBarView: View {
    @Environment(AppState.self) var appState
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(appState.tabs) { tab in
                TabItemView(tab: tab)
            }
            NewTabButton()
            Spacer()
        }
        .background(Color(.windowBackgroundColor))
    }
}

struct TabItemView: View {
    let tab: Tab
    // Show agent icon, title, close button
    // Highlight active tab
    // Drag to reorder support
}
```

### 3.2 New Tab Flow
- Click "+" button or `Cmd+T`
- Show agent selection popover/sheet
- After agent selection, show folder selector
- Create tab with selected options

### 3.3 Tab Keyboard Shortcuts
```swift
// Register in App
.commands {
    CommandGroup(replacing: .newItem) {
        Button("New Claude Tab") { appState.showNewTabModal(.claude) }
            .keyboardShortcut("t", modifiers: .command)
        Button("New GLM Tab") { appState.showNewTabModal(.glm) }
            .keyboardShortcut("t", modifiers: [.command, .shift])
    }
}
.onKeyPress { ... } // Tab switching with Cmd+1-9
```

---

## Phase 4: Folder Selection Modal

### 4.1 Folder Browser View
```swift
// FolderSelectorModal.swift
struct FolderSelectorModal: View {
    @Environment(\.dismiss) var dismiss
    @State private var currentPath: URL
    @State private var contents: [URL] = []
    @State private var searchText: String = ""
    @State private var recentFolders: [URL] = []
    
    let onSelect: (URL) -> Void
    
    var body: some View {
        VStack {
            // Header with title and close button
            ModalHeader(title: "Select Working Directory")
            
            // Search/filter field
            TextField("Search folders...", text: $searchText)
            
            // Breadcrumb navigation
            PathBreadcrumbView(path: $currentPath)
            
            // Recent folders section
            if !recentFolders.isEmpty && searchText.isEmpty {
                RecentFoldersSection(folders: recentFolders)
            }
            
            // Directory listing
            List(filteredContents) { item in
                FolderRow(url: item)
                    .onTapGesture { navigate(to: item) }
            }
            
            // Action buttons
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)
                Button("Select Folder") { onSelect(currentPath); dismiss() }
                    .keyboardShortcut(.return)
            }
        }
        .frame(width: 520, height: 500)
    }
}
```

### 4.2 Features
- Show only directories (filter out files)
- Double-click to navigate into folder
- Enter key to select current folder
- Escape to cancel
- Cmd+Up to go to parent
- Store recent folders in UserDefaults
- Show hidden folders toggle

### 4.3 Folder Selector UI Layout

#### Default State (with Recent Folders)
```
┌─────────────────────────────────────────────────────────────────────────┐
│                      Select Working Directory                     [ ✕ ] │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  🔍 [Search folders...                                              ]   │
│                                                                         │
│  ─────────────────────────────────────────────────────────────────────  │
│                                                                         │
│  📍 CURRENT PATH                                                        │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │  🏠 ~  ›  📁 projects  ›  📁 macos                              │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│                                                                         │
│  ─────────────────────────────────────────────────────────────────────  │
│                                                                         │
│  🕐 RECENT FOLDERS                                                      │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │  📁 ~/projects/webapp                                       →   │    │
│  │  📁 ~/projects/api-service                                  →   │    │
│  │  📁 ~/documents/notes                                       →   │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│                                                                         │
│  ─────────────────────────────────────────────────────────────────────  │
│                                                                         │
│  📂 FOLDERS                                                             │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │  📁 slothy-terminal                                             │    │
│  │  📁 other-project                                               │    │
│  │  📁 swift-experiments                                           │    │
│  │  📁 .hidden-folder                              (hidden) ░░░░░  │    │
│  │                                                                 │    │
│  │                                                                 │    │
│  │                                                                 │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│                                                                         │
│  ☐ Show hidden folders                                                  │
│                                                                         │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│         [ Cancel ]                      [ Select "macos" ]              │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
                           520 x 500 pts
```

#### With Search Active
```
┌─────────────────────────────────────────────────────────────────────────┐
│                      Select Working Directory                     [ ✕ ] │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  🔍 [swift                                                     ✕    ]   │
│                                                                         │
│  ─────────────────────────────────────────────────────────────────────  │
│                                                                         │
│  🔎 SEARCH RESULTS (3 matches)                                          │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │                                                                 │    │
│  │  📁 ~/projects/macos/swift-experiments                          │    │
│  │     Last modified: 2 days ago                                   │    │
│  │                                                                 │    │
│  │  📁 ~/projects/ios/SwiftUI-Demo                                 │    │
│  │     Last modified: 1 week ago                                   │    │
│  │                                                                 │    │
│  │  📁 ~/Developer/swift-toolchain                                 │    │
│  │     Last modified: 3 weeks ago                                  │    │
│  │                                                                 │    │
│  │                                                                 │    │
│  │                                                                 │    │
│  │                                                                 │    │
│  │                                                                 │    │
│  │                                                                 │    │
│  │                                                                 │    │
│  │                                                                 │    │
│  │                                                                 │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│                                                                         │
│  ☐ Show hidden folders                                                  │
│                                                                         │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│         [ Cancel ]                           [ Select ]                 │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

#### Deep Navigation State
```
┌─────────────────────────────────────────────────────────────────────────┐
│                      Select Working Directory                     [ ✕ ] │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  🔍 [Search folders...                                              ]   │
│                                                                         │
│  ─────────────────────────────────────────────────────────────────────  │
│                                                                         │
│  📍 CURRENT PATH                                                        │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │  🏠 ~ › 📁 projects › 📁 macos › 📁 slothy-terminal › 📁 src    │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│      [⌘↑ Parent]                                                        │
│                                                                         │
│  ─────────────────────────────────────────────────────────────────────  │
│                                                                         │
│  📂 FOLDERS                                                             │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │  📁 App                                                         │    │
│  │  📁 Views                                                       │    │
│  │  📁 Models                                                      │    │
│  │  📁 Terminal                                                    │    │
│  │  📁 Agents                                                      │    │
│  │  📁 Services                                                    │    │
│  │  📁 Resources                                                   │    │
│  │                                                                 │    │
│  │                                                                 │    │
│  │                                                                 │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│                                                                         │
│  ☐ Show hidden folders                                                  │
│                                                                         │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│         [ Cancel ]                        [ Select "src" ]              │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

#### Empty Folder State
```
┌─────────────────────────────────────────────────────────────────────────┐
│                      Select Working Directory                     [ ✕ ] │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  🔍 [Search folders...                                              ]   │
│                                                                         │
│  ─────────────────────────────────────────────────────────────────────  │
│                                                                         │
│  📍 CURRENT PATH                                                        │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │  🏠 ~  ›  📁 projects  ›  📁 empty-project                      │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│      [⌘↑ Parent]                                                        │
│                                                                         │
│  ─────────────────────────────────────────────────────────────────────  │
│                                                                         │
│  📂 FOLDERS                                                             │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │                                                                 │    │
│  │                                                                 │    │
│  │                                                                 │    │
│  │                      📭 No subfolders                           │    │
│  │                                                                 │    │
│  │              This folder contains no subdirectories             │    │
│  │                                                                 │    │
│  │                                                                 │    │
│  │                                                                 │    │
│  │                                                                 │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│                                                                         │
│  ☐ Show hidden folders                                                  │
│                                                                         │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│         [ Cancel ]                  [ Select "empty-project" ]          │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

#### Folder Selector Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Select current folder | `Enter` / `Return` |
| Cancel | `Escape` |
| Go to parent | `⌘ ↑` |
| Navigate into folder | `Double-click` or `→` |
| Quick search | Just start typing |

#### Folder Selector UI Components

| Component | Description |
|-----------|-------------|
| **Search Field** | Filters folders globally, shows matching paths |
| **Breadcrumb Path** | Clickable path segments for quick navigation |
| **Recent Folders** | Last 10 used folders (hidden when searching) |
| **Folder List** | Scrollable list of subdirectories only |
| **Hidden Toggle** | Checkbox to show/hide dotfiles |
| **Action Buttons** | Cancel (Esc) and Select (Enter) |

---

## Phase 5: Usage Statistics Sidebar (Right Side)

### 5.1 Sidebar Layout
```swift
// SidebarView.swift
struct SidebarView: View {
    @Environment(AppState.self) var appState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with collapse toggle
            HStack {
                Text("Usage Statistics")
                    .font(.system(size: 11, weight: .semibold))
                    .textCase(.uppercase)
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: { appState.isSidebarVisible.toggle() }) {
                    Image(systemName: "chevron.right")
                }
            }
            
            Divider()
            
            if let tab = appState.activeTab {
                AgentStatsView(tab: tab)
            }
            
            Spacer()
        }
        .padding()
        .frame(width: 260)
        .background(Color(.controlBackgroundColor))
        .border(width: 1, edges: [.leading], color: .separator)
    }
}
```

### 5.2 Stats Display Components
```swift
struct AgentStatsView: View {
    @Bindable var tab: Tab
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Agent badge with status indicator
            AgentBadge(type: tab.agentType, isActive: true)
            
            // Working directory card
            WorkingDirectoryCard(path: tab.workingDirectory)
            
            // Token Usage section
            StatsSection(title: "Token Usage") {
                StatRow(label: "Input Tokens", value: "\(tab.usageStats.tokensIn)")
                StatRow(label: "Output Tokens", value: "\(tab.usageStats.tokensOut)")
                StatRow(label: "Total", value: "\(tab.usageStats.totalTokens)", highlight: true)
            }
            
            // Session Info section
            StatsSection(title: "Session Info") {
                StatRow(label: "Messages", value: "\(tab.usageStats.messageCount)")
                StatRow(label: "Duration", value: tab.usageStats.formattedDuration)
                if let cost = tab.usageStats.estimatedCost {
                    StatRow(label: "Est. Cost", value: String(format: "$%.4f", cost), style: .cost)
                }
            }
            
            // Context window progress bar
            ContextWindowProgress(
                used: tab.usageStats.totalTokens,
                limit: 200_000
            )
        }
    }
}
```

### 5.3 Stats Parsing Service
```swift
// StatsParser.swift
class StatsParser {
    // Parse Claude CLI output for usage info
    func parseClaudeOutput(_ text: String) -> UsageUpdate? {
        // Look for patterns like:
        // "Tokens: 1234 in / 567 out"
        // "Cost: $0.0123"
        // Parse JSON status updates if available
    }
    
    // Parse GLM output
    func parseGLMOutput(_ text: String) -> UsageUpdate? {
        // GLM-specific parsing
    }
}

struct UsageUpdate {
    var tokensIn: Int?
    var tokensOut: Int?
    var cost: Double?
}
```

---

## Phase 6: Agent Integration

### 6.1 Agent Protocol
```swift
// AgentProtocol.swift
protocol AIAgent {
    var type: AgentType { get }
    var command: String { get }
    var defaultArgs: [String] { get }
    var environmentVariables: [String: String] { get }
    var accentColor: Color { get }
    
    func parseStats(from output: String) -> UsageUpdate?
    func formatStartupMessage() -> String?
}
```

### 6.2 Claude Agent
```swift
// ClaudeAgent.swift
struct ClaudeAgent: AIAgent {
    let type: AgentType = .claude
    let accentColor = Color(red: 0.85, green: 0.47, blue: 0.34) // #da7756
    
    var command: String { 
        ProcessInfo.processInfo.environment["CLAUDE_PATH"] ?? "/usr/local/bin/claude"
    }
    var defaultArgs: [String] { [] }
    
    func parseStats(from output: String) -> UsageUpdate? {
        // Parse Claude's output format
    }
}
```

### 6.3 GLM Agent
```swift
// GLMAgent.swift
struct GLMAgent: AIAgent {
    let type: AgentType = .glm
    let accentColor = Color(red: 0.29, green: 0.62, blue: 1.0) // #4a9eff
    
    var command: String {
        // GLM CLI path
    }
    
    func parseStats(from output: String) -> UsageUpdate? {
        // GLM-specific parsing
    }
}
```

---

## Phase 7: Configuration & Persistence

### 7.1 Configuration Model
```swift
// Config.swift
struct AppConfig: Codable {
    var sidebarWidth: CGFloat = 260
    var showSidebarByDefault: Bool = true
    var sidebarPosition: SidebarPosition = .right
    var defaultAgent: AgentType = .claude
    var recentFolders: [URL] = []
    var maxRecentFolders: Int = 10
    
    // Agent paths
    var claudePath: String?
    var glmPath: String?
    
    // Appearance
    var terminalFont: String = "JetBrains Mono"
    var terminalFontSize: CGFloat = 13
    var theme: ThemeType = .dark
    
    // Keyboard shortcuts
    var shortcuts: [ShortcutAction: KeyEquivalent] = [:]
}

enum SidebarPosition: String, Codable {
    case left, right
}
```

### 7.2 Config Manager
```swift
// ConfigManager.swift
@Observable
class ConfigManager {
    static let shared = ConfigManager()
    
    var config: AppConfig {
        didSet { save() }
    }
    
    private let configURL: URL = {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SlothyTerminal/config.json")
    }()
    
    func load()
    func save()
    func reset()
}
```

### 7.3 Settings View
```swift
struct SettingsView: View {
    @Environment(ConfigManager.self) var config

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gear") }
            AgentsSettingsTab()
                .tabItem { Label("Agents", systemImage: "cpu") }
            AppearanceSettingsTab()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            ShortcutsSettingsTab()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
        }
        .frame(width: 500, height: 400)
    }
}
```

### 7.4 Settings UI Layout

#### Tab 1: General Settings
```
┌─────────────────────────────────────────────────────────────────────────┐
│  ⚙️ General  │  🔲 Agents  │  🎨 Appearance  │  ⌨️ Shortcuts            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  STARTUP                                                                │
│  ───────────────────────────────────────────────────────────────────    │
│                                                                         │
│  Default Agent          [  Claude  ▼]                                   │
│                                                                         │
│                                                                         │
│  SIDEBAR                                                                │
│  ───────────────────────────────────────────────────────────────────    │
│                                                                         │
│  Show sidebar by default          [✓]                                   │
│                                                                         │
│  Sidebar position                 (○) Left   (●) Right                  │
│                                                                         │
│  Sidebar width                    [====●=====] 260px                    │
│                                                                         │
│                                                                         │
│  RECENT FOLDERS                                                         │
│  ───────────────────────────────────────────────────────────────────    │
│                                                                         │
│  Max recent folders               [  10  ▼]                             │
│                                                                         │
│  Recent folder history:                                                 │
│   • ~/projects/webapp                               [✕]                 │
│   • ~/projects/api-service                          [✕]                 │
│   • ~/documents/notes                               [✕]                 │
│                                                                         │
│                              [ Clear All Recent ]                       │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

#### Tab 2: Agents Settings
```
┌─────────────────────────────────────────────────────────────────────────┐
│  ⚙️ General  │  🔲 Agents  │  🎨 Appearance  │  ⌨️ Shortcuts            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  CLAUDE CLI                                                 ● Connected │
│  ───────────────────────────────────────────────────────────────────    │
│                                                                         │
│  Path    [/usr/local/bin/claude                    ] [ Browse... ]      │
│                                                                         │
│  Version: Claude Code v1.0.8                                            │
│                                                                         │
│          [ Verify Installation ]                                        │
│                                                                         │
│                                                                         │
│  GLM                                                       ○ Not Found  │
│  ───────────────────────────────────────────────────────────────────    │
│                                                                         │
│  Path    [                                         ] [ Browse... ]      │
│                                                                         │
│  Version: Not detected                                                  │
│                                                                         │
│          [ Verify Installation ]                                        │
│                                                                         │
│                                                                         │
│  ─────────────────────────────────────────────────────────────────────  │
│  ⓘ Agent paths are auto-detected from PATH. Override here if needed.   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

#### Tab 3: Appearance Settings
```
┌─────────────────────────────────────────────────────────────────────────┐
│  ⚙️ General  │  🔲 Agents  │  🎨 Appearance  │  ⌨️ Shortcuts            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  THEME                                                                  │
│  ───────────────────────────────────────────────────────────────────    │
│                                                                         │
│  Color scheme         (○) Light   (●) Dark   (○) System                 │
│                                                                         │
│                                                                         │
│  TERMINAL FONT                                                          │
│  ───────────────────────────────────────────────────────────────────    │
│                                                                         │
│  Font family          [ JetBrains Mono              ▼]                  │
│                                                                         │
│  Font size            [====●=====]  13pt                                │
│                                                                         │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │                                                                   │  │
│  │  claude ❯ Hello, this is a preview of your terminal font.        │  │
│  │  ABCDEFGHIJKLMNOPQRSTUVWXYZ                                       │  │
│  │  abcdefghijklmnopqrstuvwxyz                                       │  │
│  │  0123456789 !@#$%^&*()                                            │  │
│  │                                                                   │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                                                         │
│                                                                         │
│  AGENT COLORS                                                           │
│  ───────────────────────────────────────────────────────────────────    │
│                                                                         │
│  Claude accent        [■] #da7756    [ Change ]                         │
│  GLM accent           [■] #4a9eff    [ Change ]                         │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

#### Tab 4: Keyboard Shortcuts
```
┌─────────────────────────────────────────────────────────────────────────┐
│  ⚙️ General  │  🔲 Agents  │  🎨 Appearance  │  ⌨️ Shortcuts            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  TABS                                                                   │
│  ───────────────────────────────────────────────────────────────────    │
│                                                                         │
│  New Claude Tab                                       [ ⌘ T         ]   │
│  New GLM Tab                                          [ ⌘ ⇧ T       ]   │
│  Close Tab                                            [ ⌘ W         ]   │
│  Next Tab                                             [ ⌘ ⇧ ]       ]   │
│  Previous Tab                                         [ ⌘ ⇧ [       ]   │
│  Switch to Tab 1-9                                    [ ⌘ 1-9       ]   │
│                                                                         │
│                                                                         │
│  WINDOW                                                                 │
│  ───────────────────────────────────────────────────────────────────    │
│                                                                         │
│  Toggle Sidebar                                       [ ⌘ B         ]   │
│  Open Folder                                          [ ⌘ O         ]   │
│  Settings                                             [ ⌘ ,         ]   │
│                                                                         │
│                                                                         │
│  TERMINAL                                                               │
│  ───────────────────────────────────────────────────────────────────    │
│                                                                         │
│  Clear Terminal                                       [ ⌘ K         ]   │
│  Copy                                                 [ ⌘ C         ]   │
│  Paste                                                [ ⌘ V         ]   │
│                                                                         │
│                                                                         │
│  ─────────────────────────────────────────────────────────────────────  │
│  Click on a shortcut field and press new key combination to change.    │
│                                                                         │
│                          [ Restore Defaults ]                           │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

#### Settings UI Design Principles

| Aspect | Implementation |
|--------|----------------|
| **Window Size** | 500 x 400 pts |
| **Tab Navigation** | Native macOS tab bar style |
| **Sections** | Grouped with uppercase headers + dividers |
| **Controls** | Standard macOS controls (dropdowns, toggles, sliders) |
| **Typography** | Section headers: 11pt semibold, uppercase, secondary color |
| **Feedback** | Status indicators for agent connectivity |
| **Preview** | Live font preview in Appearance tab |

---

## Phase 8: Polish & Native Features

### 8.1 macOS Integration
- Menu bar with proper menus
- Touch Bar support (if applicable)
- Dock menu with recent folders
- Services menu integration
- Handoff support between devices

### 8.2 Keyboard Shortcuts Summary
| Action | Shortcut |
|--------|----------|
| New Claude Tab | `Cmd+T` |
| New GLM Tab | `Cmd+Shift+T` |
| Close Tab | `Cmd+W` |
| Next Tab | `Cmd+Shift+]` or `Ctrl+Tab` |
| Previous Tab | `Cmd+Shift+[` or `Ctrl+Shift+Tab` |
| Switch to Tab 1-9 | `Cmd+1` through `Cmd+9` |
| Toggle Sidebar | `Cmd+B` |
| Open Folder | `Cmd+O` |
| Settings | `Cmd+,` |
| Clear Terminal | `Cmd+K` |

### 8.3 Window Management
- Remember window position and size
- Support multiple windows
- Full screen support
- Split view support

---

## UI Layout Reference

```
┌─────────────────────────────────────────────────────────────────────────┐
│ ● ● ●                        Slothy Terminal                                │
├─────────────────────────────────────────────────────────────────────────┤
│ [C] ~/projects/webapp  │ [G] ~/documents  │ [C] ~/api-service  │  [+]   │
├───────────────────────────────────────────────────┬─────────────────────┤
│                                                   │ USAGE STATISTICS  ▶ │
│  claude ❯ Can you help me refactor...            │                     │
│                                                   │ ● Claude CLI Active │
│  I'll help you refactor the authentication       │                     │
│  module. Let me first examine...                 │ ┌─────────────────┐ │
│                                                   │ │ ~/projects/     │ │
│  Reading: src/auth/index.ts                      │ │ webapp          │ │
│  Reading: src/auth/middleware.ts                 │ └─────────────────┘ │
│                                                   │                     │
│  I've analyzed the authentication module.        │ TOKEN USAGE         │
│  Here are my suggestions:                        │ Input      12,847   │
│                                                   │ Output      8,234   │
│  1. Extract token validation logic...            │ Total      21,081   │
│  2. Implement strategy pattern...                │                     │
│  3. Add proper error handling...                 │ SESSION INFO        │
│                                                   │ Messages       24   │
│  claude ❯ █                                      │ Duration    47m 23s │
│                                                   │ Est. Cost   $0.0847 │
│                                                   │                     │
│                                                   │ CONTEXT WINDOW      │
│                                                   │ ████░░░░░░░░ 10.5%  │
├───────────────────────────────────────────────────┴─────────────────────┤
│ ● Connected │ Claude 3.5 Sonnet     │ ⌘B Sidebar │ ⌘T New │ ⌘O Folder  │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Implementation Timeline

| Week | Phase | Deliverable |
|------|-------|-------------|
| 1 | Phase 1 | Basic terminal with PTY working |
| 2 | Phase 2-3 | App architecture + tabs |
| 3 | Phase 4 | Folder selection modal |
| 4 | Phase 5 | Usage statistics sidebar (right side) |
| 5 | Phase 6 | Agent integration |
| 6 | Phase 7-8 | Configuration + polish |

---

## Dependencies

Add to `Package.swift` or via Xcode:

```swift
dependencies: [
    .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.0.0"),
]
```

---

## Testing Strategy

- Unit tests for stats parsing
- Unit tests for configuration
- UI tests for modal flows
- Integration tests with mock PTY
- Manual testing with actual Claude CLI and GLM

---

## Future Enhancements

- Split panes within tabs
- Sidebar position toggle (left/right) in settings
- Shortcuts app integration
- Widgets for usage stats
- Multiple window support with tab dragging
- Plugin architecture for additional agents
