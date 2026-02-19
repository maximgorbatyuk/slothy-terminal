import SwiftUI

/// Settings navigation sections.
enum SettingsSection: String, CaseIterable, Identifiable {
  case general
  case chat
  case agents
  case telegram
  case appearance
  case shortcuts
  case prompts
  case licenses

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .general:
      return "General"

    case .chat:
      return "Chat"

    case .agents:
      return "Agents"

    case .telegram:
      return "Telegram"

    case .appearance:
      return "Appearance"

    case .shortcuts:
      return "Shortcuts"

    case .prompts:
      return "Prompts"

    case .licenses:
      return "Licenses"
    }
  }

  var icon: String {
    switch self {
    case .general:
      return "gear"

    case .chat:
      return "bubble.left.and.bubble.right"

    case .agents:
      return "cpu"

    case .telegram:
      return "paperplane"

    case .appearance:
      return "paintbrush"

    case .shortcuts:
      return "keyboard"

    case .prompts:
      return "text.bubble"

    case .licenses:
      return "doc.text"
    }
  }
}

/// Main settings view with sidebar navigation.
struct SettingsView: View {
  @State private var selectedSection: SettingsSection = .general

  var body: some View {
    NavigationSplitView {
      List(SettingsSection.allCases, selection: $selectedSection) { section in
        Label(section.displayName, systemImage: section.icon)
          .tag(section)
      }
      .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
      .listStyle(.sidebar)
    } detail: {
      Group {
        switch selectedSection {
        case .general:
          GeneralSettingsTab()

        case .chat:
          ChatSettingsTab()

        case .agents:
          AgentsSettingsTab()

        case .telegram:
          TelegramSettingsTab()

        case .appearance:
          AppearanceSettingsTab()

        case .shortcuts:
          ShortcutsSettingsTab()

        case .prompts:
          PromptsSettingsTab()

        case .licenses:
          LicensesSettingsTab()
        }
      }
    }
    .frame(minWidth: 600, idealWidth: 700, minHeight: 450)
    .background(appBackgroundColor)
  }
}

// MARK: - General Settings Tab

struct GeneralSettingsTab: View {
  private var configManager = ConfigManager.shared
  private var recentFoldersManager = RecentFoldersManager.shared
  @Environment(AppState.self) private var appState

  var body: some View {
    Form {
      Section("Startup") {
        Picker("Default tab mode", selection: Bindable(configManager).config.defaultTabMode) {
          ForEach(TabMode.allCases, id: \.self) { mode in
            Text(mode.displayName).tag(mode)
          }
        }
        .pickerStyle(.segmented)

        Picker("Default agent (TUI)", selection: Bindable(configManager).config.defaultAgent) {
          ForEach(AgentType.allCases) { agent in
            Text(agent.rawValue).tag(agent)
          }
        }
        .pickerStyle(.menu)
      }

      Section("Sidebar") {
        Toggle("Show sidebar by default", isOn: Binding(
          get: { configManager.config.showSidebarByDefault },
          set: { newValue in
            configManager.config.showSidebarByDefault = newValue
            appState.isSidebarVisible = newValue
          }
        ))

        Picker("Sidebar position", selection: Bindable(configManager).config.sidebarPosition) {
          ForEach(SidebarPosition.allCases, id: \.self) { position in
            Text(position.displayName).tag(position)
          }
        }
        .pickerStyle(.segmented)

        HStack {
          Text("Sidebar width")
          Slider(
            value: Bindable(configManager).config.sidebarWidth,
            in: 200...400,
            step: 10
          )
          Text("\(Int(configManager.config.sidebarWidth))px")
            .monospacedDigit()
            .frame(width: 50, alignment: .trailing)
        }
      }

      Section("Updates") {
        Toggle(
          "Check for updates automatically",
          isOn: Binding(
            get: { UpdateManager.shared.automaticallyChecksForUpdates },
            set: { UpdateManager.shared.automaticallyChecksForUpdates = $0 }
          )
        )

        if let lastCheck = UpdateManager.shared.lastUpdateCheckDate {
          Text("Last checked: \(lastCheck.formatted(date: .abbreviated, time: .shortened))")
            .font(.caption)
            .foregroundColor(.secondary)
        }

        Button("Check for Updates Now") {
          UpdateManager.shared.checkForUpdates()
        }
        .disabled(!UpdateManager.shared.canCheckForUpdates)
      }

      Section("Recent Folders") {
        Picker("Max recent folders", selection: Bindable(configManager).config.maxRecentFolders) {
          ForEach([5, 10, 15, 20], id: \.self) { count in
            Text("\(count)").tag(count)
          }
        }
        .pickerStyle(.menu)

        if !recentFoldersManager.recentFolders.isEmpty {
          VStack(alignment: .leading, spacing: 4) {
            Text("Recent folder history:")
              .font(.caption)
              .foregroundColor(.secondary)

            ForEach(recentFoldersManager.recentFolders.prefix(5), id: \.path) { folder in
              HStack {
                Text(shortenedPath(folder.path))
                  .font(.system(size: 11, design: .monospaced))
                  .lineLimit(1)
                  .truncationMode(.middle)

                Spacer()

                Button {
                  recentFoldersManager.removeRecentFolder(folder)
                } label: {
                  Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
              }
              .padding(.horizontal, 8)
              .padding(.vertical, 4)
              .background(appCardColor)
              .cornerRadius(4)
            }
          }

          Button("Clear All Recent") {
            recentFoldersManager.clearRecentFolders()
          }
        }
      }

      Section("Configuration File") {
        Text(shortenedPath(configManager.configFilePath))
          .font(.system(size: 11, design: .monospaced))
          .foregroundColor(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)

        HStack(spacing: 8) {
          ForEach(editorApps) { app in
            Button {
              ExternalAppManager.shared.openFile(URL(fileURLWithPath: configManager.configFilePath), in: app)
            } label: {
              HStack(spacing: 4) {
                if let icon = app.appIcon {
                  Image(nsImage: icon)
                    .resizable()
                    .frame(width: 16, height: 16)
                } else {
                  Image(systemName: app.icon)
                    .font(.system(size: 12))
                }

                Text(app.name)
                  .font(.system(size: 12))
              }
            }
            .buttonStyle(.bordered)
          }
        }

        if editorApps.isEmpty {
          Text("No supported editors found. Install VS Code, Cursor, or Antigravity.")
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }
    }
    .formStyle(.grouped)
    .scrollContentBackground(.hidden)
    .padding()
    .background(appBackgroundColor)
  }

  private var editorApps: [ExternalApp] {
    let editorBundleIDs = [
      "com.google.antigravity",
      "com.todesktop.230313mzl4w4u92",
      "com.microsoft.VSCode",
    ]
    return ExternalAppManager.shared.knownApps.filter { app in
      editorBundleIDs.contains(app.id) && app.isInstalled
    }
  }

  private func shortenedPath(_ path: String) -> String {
    let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
    if path.hasPrefix(homeDir) {
      return "~" + path.dropFirst(homeDir.count)
    }
    return path
  }
}

// MARK: - Chat Settings Tab

struct ChatSettingsTab: View {
  private var configManager = ConfigManager.shared

  var body: some View {
    Form {
      Section("Input") {
        Picker("Send message with", selection: Bindable(configManager).config.chatSendKey) {
          ForEach(ChatSendKey.allCases, id: \.self) { key in
            Text(key.displayName).tag(key)
          }
        }
        .pickerStyle(.segmented)

        Text(configManager.config.chatSendKey.newlineHint)
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Section("Display") {
        Picker("Render mode", selection: Bindable(configManager).config.chatRenderMode) {
          ForEach(ChatRenderMode.allCases, id: \.self) { mode in
            Text(mode.displayName).tag(mode)
          }
        }
        .pickerStyle(.segmented)

        Text("Controls how assistant messages are displayed by default.")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Section("Text Size") {
        Picker("Message text size", selection: Bindable(configManager).config.chatMessageTextSize) {
          ForEach(ChatMessageTextSize.allCases, id: \.self) { size in
            Text(size.displayName).tag(size)
          }
        }
        .pickerStyle(.segmented)

        /// Preview text at the selected size.
        Text("The quick brown fox jumps over the lazy dog.")
          .font(.system(size: configManager.config.chatMessageTextSize.bodyFontSize))
          .foregroundColor(.secondary)
          .padding(.vertical, 4)
      }

      Section("Metadata") {
        Toggle(
          "Show message timestamps",
          isOn: Bindable(configManager).config.chatShowTimestamps
        )

        Toggle(
          "Show token counts",
          isOn: Bindable(configManager).config.chatShowTokenMetadata
        )
      }
    }
    .formStyle(.grouped)
    .scrollContentBackground(.hidden)
    .padding()
    .background(appBackgroundColor)
  }
}

// MARK: - Agents Settings Tab

struct AgentsSettingsTab: View {
  private var configManager = ConfigManager.shared
  @State private var claudeStatus: AgentStatus = .checking
  @State private var opencodeStatus: AgentStatus = .checking

  var body: some View {
    Form {
      AgentSettingsSection(
        agentType: .claude,
        customPath: Bindable(configManager).config.claudePath,
        status: $claudeStatus
      )

      AgentSettingsSection(
        agentType: .opencode,
        customPath: Bindable(configManager).config.opencodePath,
        status: $opencodeStatus
      )

      Section {
        Text("Agent paths are auto-detected. Override here if needed.")
          .font(.caption)
          .foregroundColor(.secondary)
      }
    }
    .formStyle(.grouped)
    .scrollContentBackground(.hidden)
    .padding()
    .background(appBackgroundColor)
    .task {
      await checkAgentStatuses()
    }
  }

  private func checkAgentStatuses() async {
    claudeStatus = checkAgent(.claude)
    opencodeStatus = checkAgent(.opencode)
  }

  private func checkAgent(_ type: AgentType) -> AgentStatus {
    let agent = AgentFactory.createAgent(for: type)
    if agent.isAvailable() {
      return .connected
    }
    return .notFound
  }
}

/// Status of an agent installation.
enum AgentStatus {
  case checking
  case connected
  case notFound

  /// Muted status colors that work with the dark theme.
  var color: Color {
    switch self {
    case .checking:
      return Color(red: 0.85, green: 0.65, blue: 0.35)

    case .connected:
      return Color(red: 0.45, green: 0.75, blue: 0.55)

    case .notFound:
      return Color(red: 0.85, green: 0.45, blue: 0.45)
    }
  }

  var text: String {
    switch self {
    case .checking:
      return "Checking..."

    case .connected:
      return "Connected"

    case .notFound:
      return "Not Found"
    }
  }
}

/// Settings section for a single agent.
struct AgentSettingsSection: View {
  let agentType: AgentType
  @Binding var customPath: String?
  @Binding var status: AgentStatus

  @State private var pathText: String = ""
  @State private var isVerifying: Bool = false

  private var agent: AIAgent {
    AgentFactory.createAgent(for: agentType)
  }

  var body: some View {
    Section {
      HStack {
        Image(systemName: agent.iconName)
          .foregroundColor(agent.accentColor)

        Text(agent.displayName)
          .font(.headline)

        Spacer()

        HStack(spacing: 4) {
          Circle()
            .fill(status.color)
            .frame(width: 8, height: 8)

          Text(status.text)
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }

      HStack {
        TextField("Path", text: $pathText, prompt: Text(agent.command).foregroundStyle(.secondary))
          .textFieldStyle(.roundedBorder)

        Button("Browse...") {
          browseForExecutable()
        }
      }

      if !pathText.isEmpty || customPath != nil {
        HStack {
          Text("Using: \(customPath ?? agent.command)")
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)

          Spacer()

          if customPath != nil {
            Button("Reset") {
              customPath = nil
              pathText = ""
              verifyInstallation()
            }
            .font(.caption)
          }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(appCardColor)
        .cornerRadius(4)
      }

      Button("Verify Installation") {
        verifyInstallation()
      }
      .disabled(isVerifying)
    }
    .onAppear {
      pathText = customPath ?? ""
    }
    .onChange(of: pathText) { _, newValue in
      if newValue.isEmpty {
        customPath = nil
      } else {
        customPath = newValue
      }
    }
  }

  private func browseForExecutable() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.message = "Select the \(agent.displayName) CLI executable"

    panel.begin { response in
      if response == .OK, let url = panel.url {
        pathText = url.path
        customPath = url.path
        verifyInstallation()
      }
    }
  }

  private func verifyInstallation() {
    isVerifying = true
    status = .checking

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      let path = customPath ?? agent.command
      if FileManager.default.isExecutableFile(atPath: path) {
        status = .connected
      } else {
        status = .notFound
      }
      isVerifying = false
    }
  }
}

// MARK: - Appearance Settings Tab

struct AppearanceSettingsTab: View {
  private var configManager = ConfigManager.shared

  var body: some View {
    Form {
      Section("Color Scheme") {
        Picker("Appearance", selection: Bindable(configManager).config.colorScheme) {
          ForEach(AppColorScheme.allCases, id: \.self) { scheme in
            Text(scheme.displayName).tag(scheme)
          }
        }
        .pickerStyle(.segmented)
      }

      Section("Terminal Font") {
        Picker("Font family", selection: Bindable(configManager).config.terminalFontName) {
          ForEach(ConfigManager.availableMonospacedFonts, id: \.self) { font in
            Text(font).tag(font)
          }
        }

        HStack {
          Text("Font size")
          Slider(
            value: Bindable(configManager).config.terminalFontSize,
            in: 10...24,
            step: 1
          )
          Text("\(Int(configManager.config.terminalFontSize))pt")
            .monospacedDigit()
            .frame(width: 40, alignment: .trailing)
        }

        /// Font preview.
        VStack(alignment: .leading, spacing: 4) {
          Text("Preview")
            .font(.caption)
            .foregroundColor(.secondary)

          Text("claude ❯ Hello, this is a preview.\nABCDEFGHIJKLMNOPQRSTUVWXYZ\nabcdefghijklmnopqrstuvwxyz\n0123456789 !@#$%^&*()")
            .font(.custom(
              configManager.config.terminalFontName,
              size: configManager.config.terminalFontSize
            ))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(appCardColor)
            .cornerRadius(6)
        }
      }

      Section("Terminal Interaction") {
        Picker("Mouse mode", selection: Bindable(configManager).config.terminalInteractionMode) {
          ForEach(TerminalInteractionMode.allCases, id: \.self) { mode in
            Text(mode.displayName).tag(mode)
          }
        }
        .pickerStyle(.segmented)

        Text(configManager.config.terminalInteractionMode.description)
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Section("Agent Colors") {
        AgentColorPicker(
          agentType: .claude,
          customColor: Bindable(configManager).config.claudeAccentColor
        )

        AgentColorPicker(
          agentType: .opencode,
          customColor: Bindable(configManager).config.opencodeAccentColor
        )
      }
    }
    .formStyle(.grouped)
    .scrollContentBackground(.hidden)
    .padding()
    .background(appBackgroundColor)
  }
}

/// Color picker for an agent's accent color.
struct AgentColorPicker: View {
  let agentType: AgentType
  @Binding var customColor: CodableColor?

  private var currentColor: Color {
    customColor?.color ?? agentType.accentColor
  }

  var body: some View {
    HStack {
      Text("\(agentType.rawValue) accent")

      Spacer()

      ColorPicker("", selection: Binding(
        get: { currentColor },
        set: { customColor = CodableColor($0) }
      ))
      .labelsHidden()

      if customColor != nil {
        Button("Reset") {
          customColor = nil
        }
        .font(.caption)
      }
    }
  }
}

// MARK: - Shortcuts Settings Tab

struct ShortcutsSettingsTab: View {
  private var configManager = ConfigManager.shared

  var body: some View {
    Form {
      ForEach(ShortcutCategory.allCases, id: \.self) { category in
        Section(category.displayName) {
          ForEach(ShortcutAction.allCases.filter { $0.category == category }, id: \.self) { action in
            ShortcutRow(action: action)
          }
        }
      }

      Section {
        Button("Reset All to Defaults") {
          configManager.config.shortcuts = [:]
        }
      }
    }
    .formStyle(.grouped)
    .scrollContentBackground(.hidden)
    .padding()
    .background(appBackgroundColor)
  }
}

/// A row displaying a shortcut action and its key binding.
struct ShortcutRow: View {
  let action: ShortcutAction
  private var configManager = ConfigManager.shared

  init(action: ShortcutAction) {
    self.action = action
  }

  private var shortcut: String {
    configManager.config.shortcuts[action.rawValue] ?? action.defaultShortcut
  }

  var body: some View {
    HStack {
      Text(action.displayName)

      Spacer()

      Text(shortcut)
        .font(.system(size: 12, design: .monospaced))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(appCardColor)
        .cornerRadius(4)
    }
  }
}

// MARK: - Prompts Settings Tab

struct PromptsSettingsTab: View {
  private enum PromptSortOption: String, CaseIterable, Identifiable {
    case updatedNewest
    case updatedOldest
    case nameAscending
    case nameDescending

    var id: String {
      rawValue
    }

    var displayName: String {
      switch self {
      case .updatedNewest:
        return "Updated (Newest)"

      case .updatedOldest:
        return "Updated (Oldest)"

      case .nameAscending:
        return "Name (A-Z)"

      case .nameDescending:
        return "Name (Z-A)"
      }
    }
  }

  private var configManager = ConfigManager.shared
  @State private var editingPrompt: SavedPrompt?
  @State private var isAddingNew = false
  @State private var promptToDelete: SavedPrompt?
  @State private var selectedPromptID: UUID?
  @State private var isManagingTags = false
  @State private var sortOption: PromptSortOption = .updatedNewest

  private var selectedPrompt: SavedPrompt? {
    configManager.config.savedPrompts.find(by: selectedPromptID)
  }

  private var sortedPrompts: [SavedPrompt] {
    switch sortOption {
    case .updatedNewest:
      return configManager.config.savedPrompts.sorted { lhs, rhs in
        lhs.updatedAt > rhs.updatedAt
      }

    case .updatedOldest:
      return configManager.config.savedPrompts.sorted { lhs, rhs in
        lhs.updatedAt < rhs.updatedAt
      }

    case .nameAscending:
      return configManager.config.savedPrompts.sorted { lhs, rhs in
        lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
      }

    case .nameDescending:
      return configManager.config.savedPrompts.sorted { lhs, rhs in
        lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedDescending
      }
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Saved Prompts")
          .font(.headline)

        Spacer()

        Picker("Sort", selection: $sortOption) {
          ForEach(PromptSortOption.allCases) { option in
            Text(option.displayName).tag(option)
          }
        }
        .pickerStyle(.menu)
      }

      if configManager.config.savedPrompts.isEmpty {
        VStack(spacing: 12) {
          Image(systemName: "text.bubble")
            .font(.system(size: 32))
            .foregroundColor(.secondary)

          Text("No saved prompts")
            .font(.subheadline)
            .foregroundColor(.secondary)

          Text("Create reusable prompts to attach when opening AI agent tabs.")
            .font(.caption)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
      } else {
        Table(sortedPrompts, selection: $selectedPromptID) {
          TableColumn("Name") { prompt in
            Text(prompt.name)
              .lineLimit(1)
              .contextMenu {
                Button("Edit Prompt") {
                  beginEditing(prompt)
                }

                Button("Delete Prompt", role: .destructive) {
                  beginDeletion(prompt)
                }
              }
              .onTapGesture(count: 2) {
                beginEditing(prompt)
              }
          }

          TableColumn("Description") { prompt in
            Text(prompt.promptDescription.isEmpty ? "-" : prompt.promptDescription)
              .lineLimit(1)
              .foregroundColor(prompt.promptDescription.isEmpty ? .secondary : .primary)
          }

          TableColumn("Tags") { prompt in
            Text(tagListText(for: prompt))
              .lineLimit(1)
              .foregroundColor(prompt.tagIDs.isEmpty ? .secondary : .primary)
          }

          TableColumn("Prompt") { prompt in
            Text(prompt.previewText())
              .font(.system(size: 11, design: .monospaced))
              .lineLimit(1)
              .foregroundColor(.secondary)
          }

          TableColumn("Updated") { prompt in
            Text(prompt.updatedAt, format: .dateTime.year().month().day().hour().minute())
              .foregroundColor(.secondary)
          }
        }
        .frame(minHeight: 220)
        .onDeleteCommand(perform: handleDeleteCommand)
      }

      HStack(spacing: 8) {
        Button {
          isAddingNew = true
        } label: {
          HStack {
            Image(systemName: "plus")
            Text("Add Prompt")
          }
        }

        Button {
          editingPrompt = selectedPrompt
        } label: {
          HStack {
            Image(systemName: "pencil")
            Text("Edit")
          }
        }
        .disabled(selectedPrompt == nil)

        Button(role: .destructive) {
          promptToDelete = selectedPrompt
        } label: {
          HStack {
            Image(systemName: "trash")
            Text("Delete")
          }
        }
        .disabled(selectedPrompt == nil)

        Spacer()

        Button {
          isManagingTags = true
        } label: {
          HStack {
            Image(systemName: "tag")
            Text("Manage Tags")
          }
        }
      }

      Text("Tags are shared across prompts and can be renamed or deleted globally.")
        .font(.caption)
        .foregroundColor(.secondary)
    }
    .padding()
    .background(appBackgroundColor)
    .sheet(isPresented: $isManagingTags) {
      PromptTagsManagerSheet(tags: configManager.config.promptTags) { updatedTags in
        applyTagChanges(updatedTags)
      }
    }
    .sheet(isPresented: $isAddingNew) {
      PromptEditorSheet(prompt: nil, availableTags: configManager.config.promptTags) { newPrompt in
        configManager.config.savedPrompts.append(newPrompt)
        selectedPromptID = newPrompt.id
      }
    }
    .sheet(item: $editingPrompt) { prompt in
      PromptEditorSheet(prompt: prompt, availableTags: configManager.config.promptTags) { updatedPrompt in
        if let index = configManager.config.savedPrompts.firstIndex(where: { $0.id == updatedPrompt.id }) {
          configManager.config.savedPrompts[index] = updatedPrompt
        }
      }
    }
    .alert(
      "Delete Prompt",
      isPresented: Binding(
        get: { promptToDelete != nil },
        set: { if !$0 { promptToDelete = nil } }
      )
    ) {
      Button("Cancel", role: .cancel) {
        promptToDelete = nil
      }

      Button("Delete", role: .destructive) {
        if let prompt = promptToDelete {
          deletePrompt(prompt)
        }
        promptToDelete = nil
      }
    } message: {
      if let prompt = promptToDelete {
        Text("Are you sure you want to delete \"\(prompt.name)\"? This cannot be undone.")
      }
    }
  }

  private func applyTagChanges(_ updatedTags: [PromptTag]) {
    let previousTagIDs = Set(configManager.config.promptTags.map(\.id))
    let nextTagIDs = Set(updatedTags.map(\.id))
    let removedTagIDs = previousTagIDs.subtracting(nextTagIDs)
    configManager.config.promptTags = updatedTags

    guard !removedTagIDs.isEmpty else {
      return
    }

    for index in configManager.config.savedPrompts.indices {
      let filtered = configManager.config.savedPrompts[index].tagIDs.filter { tagID in
        !removedTagIDs.contains(tagID)
      }
      configManager.config.savedPrompts[index].tagIDs = filtered
    }
  }

  private func beginEditing(_ prompt: SavedPrompt) {
    selectedPromptID = prompt.id
    editingPrompt = prompt
  }

  private func beginDeletion(_ prompt: SavedPrompt) {
    selectedPromptID = prompt.id
    promptToDelete = prompt
  }

  private func handleDeleteCommand() {
    guard let selectedPrompt else {
      return
    }

    promptToDelete = selectedPrompt
  }

  private func deletePrompt(_ prompt: SavedPrompt) {
    configManager.config.savedPrompts.removeAll { existingPrompt in
      existingPrompt.id == prompt.id
    }

    if selectedPromptID == prompt.id {
      selectedPromptID = nil
    }
  }

  private func tagListText(for prompt: SavedPrompt) -> String {
    let names = prompt.tagIDs.compactMap { tagID in
      configManager.config.promptTags.find(by: tagID)?.name
    }

    guard !names.isEmpty else {
      return "-"
    }

    return names.joined(separator: ", ")
  }
}

/// A sheet for creating, renaming, and deleting reusable prompt tags.
struct PromptTagsManagerSheet: View {
  let onSave: ([PromptTag]) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var tags: [PromptTag]
  @State private var newTagName: String = ""
  @State private var validationMessage: String?

  init(
    tags: [PromptTag],
    onSave: @escaping ([PromptTag]) -> Void
  ) {
    self.onSave = onSave
    _tags = State(initialValue: tags.sorted(by: { lhs, rhs in
      lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }))
  }

  private var canSave: Bool {
    validationError == nil
  }

  private var validationError: String? {
    let normalized = tags.map { normalizeTagName($0.name) }

    if normalized.contains(where: \.isEmpty) {
      return "Tag names cannot be empty."
    }

    let uniqueCount = Set(normalized).count
    if uniqueCount != normalized.count {
      return "Tag names must be unique."
    }

    return nil
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text("Manage Prompt Tags")
          .font(.headline)

        Spacer()

        Button {
          dismiss()
        } label: {
          Image(systemName: "xmark.circle.fill")
            .font(.system(size: 20))
            .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
      }
      .padding(20)

      Divider()

      VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 8) {
          TextField("New tag", text: $newTagName)
            .textFieldStyle(.roundedBorder)

          Button("Add") {
            addTag()
          }
          .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }

        if let validationMessage {
          Text(validationMessage)
            .font(.caption)
            .foregroundColor(.red)
        } else if let validationError {
          Text(validationError)
            .font(.caption)
            .foregroundColor(.red)
        }

        if tags.isEmpty {
          VStack(spacing: 8) {
            Image(systemName: "tag")
              .font(.system(size: 24))
              .foregroundColor(.secondary)

            Text("No tags yet")
              .font(.subheadline)
              .foregroundColor(.secondary)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          List {
            ForEach($tags) { $tag in
              HStack(spacing: 8) {
                TextField("Tag name", text: $tag.name)
                  .textFieldStyle(.roundedBorder)

                Button(role: .destructive) {
                  deleteTag(tag.id)
                } label: {
                  Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
              }
            }
          }
          .listStyle(.inset)
        }
      }
      .padding(20)

      Divider()

      HStack {
        Button("Cancel") {
          dismiss()
        }
        .keyboardShortcut(.escape)

        Spacer()

        Button("Save") {
          save()
        }
        .buttonStyle(.borderedProminent)
        .disabled(!canSave)
        .keyboardShortcut(.return, modifiers: .command)
      }
      .padding(16)
    }
    .frame(width: 460, height: 420)
    .background(appBackgroundColor)
  }

  private func addTag() {
    validationMessage = nil
    let trimmed = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !trimmed.isEmpty else {
      return
    }

    let normalized = normalizeTagName(trimmed)
    let hasDuplicate = tags.contains { tag in
      normalizeTagName(tag.name) == normalized
    }

    guard !hasDuplicate else {
      validationMessage = "Tag \"\(trimmed)\" already exists."
      return
    }

    tags.append(PromptTag(name: trimmed))
    tags.sort { lhs, rhs in
      lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
    newTagName = ""
  }

  private func deleteTag(_ tagID: UUID) {
    tags.removeAll { tag in
      tag.id == tagID
    }
  }

  private func save() {
    let cleaned = tags.map { tag in
      PromptTag(id: tag.id, name: tag.name.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    onSave(cleaned)
    dismiss()
  }

  private func normalizeTagName(_ value: String) -> String {
    value
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
  }
}

/// A sheet for creating or editing a saved prompt.
struct PromptEditorSheet: View {
  let prompt: SavedPrompt?
  let availableTags: [PromptTag]
  let onSave: (SavedPrompt) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var name: String = ""
  @State private var promptDescription: String = ""
  @State private var promptText: String = ""
  @State private var selectedTagIDs: Set<UUID> = []

  /// Maximum allowed length for prompt text to stay within CLI argument limits.
  private let maxPromptLength = 10_000

  private var isValid: Bool {
    !name.trimmingCharacters(in: .whitespaces).isEmpty
    && !promptText.trimmingCharacters(in: .whitespaces).isEmpty
    && promptText.count <= maxPromptLength
  }

  var body: some View {
    VStack(spacing: 0) {
      /// Header.
      HStack {
        Text(prompt == nil ? "New Prompt" : "Edit Prompt")
          .font(.headline)

        Spacer()

        Button {
          dismiss()
        } label: {
          Image(systemName: "xmark.circle.fill")
            .font(.system(size: 20))
            .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
      }
      .padding(20)

      Divider()

      /// Form fields.
      VStack(alignment: .leading, spacing: 16) {
        VStack(alignment: .leading, spacing: 6) {
          Text("Name")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.secondary)

          TextField("e.g. Code Reviewer", text: $name)
            .textFieldStyle(.roundedBorder)
        }

        VStack(alignment: .leading, spacing: 6) {
          Text("Description (optional)")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.secondary)

          TextField("Brief description of this prompt", text: $promptDescription)
            .textFieldStyle(.roundedBorder)
        }

        if !availableTags.isEmpty {
          VStack(alignment: .leading, spacing: 6) {
            Text("Tags")
              .font(.system(size: 11, weight: .semibold))
              .foregroundColor(.secondary)

            ScrollView {
              VStack(alignment: .leading, spacing: 6) {
                ForEach(sortedAvailableTags) { tag in
                  Toggle(isOn: tagBinding(for: tag.id)) {
                    Text(tag.name)
                      .font(.system(size: 12))
                  }
                  .toggleStyle(.checkbox)
                }
              }
            }
            .frame(maxWidth: .infinity, maxHeight: 110)
            .padding(10)
            .background(appCardColor)
            .cornerRadius(6)
          }
        }

        VStack(alignment: .leading, spacing: 6) {
          Text("Prompt Text")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.secondary)

          TextEditor(text: $promptText)
            .font(.system(size: 12, design: .monospaced))
            .frame(maxHeight: .infinity)
            .scrollContentBackground(.hidden)
            .padding(8)
            .background(appCardColor)
            .cornerRadius(6)

          HStack {
            Spacer()

            Text("\(promptText.count) / \(maxPromptLength)")
              .font(.system(size: 10))
              .foregroundColor(promptText.count > maxPromptLength ? .red : .secondary)
          }
        }
      }
      .padding(20)

      Divider()

      /// Footer with action buttons.
      HStack {
        Button("Cancel") {
          dismiss()
        }
        .keyboardShortcut(.escape)

        Spacer()

        Button("Save") {
          save()
        }
        .buttonStyle(.borderedProminent)
        .disabled(!isValid)
        .keyboardShortcut(.return, modifiers: .command)
      }
      .padding(16)
    }
    .frame(width: 450, height: 450)
    .background(appBackgroundColor)
    .onAppear {
      if let prompt {
        name = prompt.name
        promptDescription = prompt.promptDescription
        promptText = prompt.promptText
        selectedTagIDs = Set(prompt.tagIDs)
      }
    }
  }

  private var sortedAvailableTags: [PromptTag] {
    availableTags.sorted { lhs, rhs in
      lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
  }

  private func save() {
    let trimmedName = name.trimmingCharacters(in: .whitespaces)
    let trimmedText = promptText.trimmingCharacters(in: .whitespaces)

    guard !trimmedName.isEmpty,
          !trimmedText.isEmpty
    else {
      return
    }

    let saved = SavedPrompt(
      id: prompt?.id ?? UUID(),
      name: trimmedName,
      promptDescription: promptDescription.trimmingCharacters(in: .whitespaces),
      promptText: trimmedText,
      tagIDs: selectedTagIDs.sorted(by: { lhs, rhs in
        lhs.uuidString < rhs.uuidString
      }),
      createdAt: prompt?.createdAt ?? Date(),
      updatedAt: Date()
    )
    onSave(saved)
    dismiss()
  }

  private func tagBinding(for tagID: UUID) -> Binding<Bool> {
    Binding(
      get: {
        selectedTagIDs.contains(tagID)
      },
      set: { isSelected in
        if isSelected {
          selectedTagIDs.insert(tagID)
        } else {
          selectedTagIDs.remove(tagID)
        }
      }
    )
  }
}

// MARK: - Licenses Settings Tab

struct LicensesSettingsTab: View {
  var body: some View {
    Form {
      Section("SlothyTerminal") {
        LicenseSection(
          name: "SlothyTerminal",
          description: "AI coding assistant terminal for macOS",
          licenseFileName: "SLOTHYTERMINAL_LICENSE"
        )
      }

      Section("Third-Party Licenses") {
        Text("SlothyTerminal uses the following open source software:")
          .font(.caption)
          .foregroundColor(.secondary)

        LicenseSection(
          name: "Ghostty",
          description: "Fast, native, feature-rich terminal emulator",
          licenseFileName: "GHOSTTY_LICENSE"
        )

        LicenseSection(
          name: "Sparkle",
          description: "Software update framework for macOS",
          licenseFileName: "SPARKLE_LICENSE"
        )
      }
    }
    .formStyle(.grouped)
    .scrollContentBackground(.hidden)
    .padding()
    .background(appBackgroundColor)
  }
}

struct LicenseSection: View {
  let name: String
  let description: String
  let licenseFileName: String

  @State private var licenseText: String = ""
  @State private var isExpanded: Bool = false

  var body: some View {
    Section {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text(name)
            .font(.headline)

          Text(description)
            .font(.caption)
            .foregroundColor(.secondary)
        }

        Spacer()

        Button {
          withAnimation {
            isExpanded.toggle()
          }
        } label: {
          Text(isExpanded ? "Hide License" : "View License")
            .font(.caption)
        }
        .buttonStyle(.bordered)
      }

      if isExpanded {
        ScrollView {
          Text(licenseText)
            .font(.system(size: 10, design: .monospaced))
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
        .frame(maxHeight: 200)
        .background(appCardColor)
        .cornerRadius(6)
      }
    }
    .onAppear {
      loadLicense()
    }
  }

  private func loadLicense() {
    guard let url = Bundle.main.url(forResource: licenseFileName, withExtension: nil) else {
      licenseText = "License file not found."
      return
    }

    if let text = try? String(contentsOf: url, encoding: .utf8) {
      licenseText = text
    } else {
      licenseText = "Could not load license file."
    }
  }
}

// MARK: - Previews

#Preview("General") {
  GeneralSettingsTab()
    .frame(width: 500, height: 400)
}

#Preview("Agents") {
  AgentsSettingsTab()
    .frame(width: 500, height: 400)
}

#Preview("Appearance") {
  AppearanceSettingsTab()
    .frame(width: 500, height: 400)
}

#Preview("Shortcuts") {
  ShortcutsSettingsTab()
    .frame(width: 500, height: 400)
}
