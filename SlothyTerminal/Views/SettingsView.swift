import SwiftUI

/// Main settings view with tabbed interface.
struct SettingsView: View {
  private var configManager = ConfigManager.shared
  private var recentFoldersManager = RecentFoldersManager.shared

  var body: some View {
    TabView {
      GeneralSettingsTab()
        .tabItem {
          Label("General", systemImage: "gear")
        }

      AgentsSettingsTab()
        .tabItem {
          Label("Agents", systemImage: "cpu")
        }

      AppearanceSettingsTab()
        .tabItem {
          Label("Appearance", systemImage: "paintbrush")
        }

      ShortcutsSettingsTab()
        .tabItem {
          Label("Shortcuts", systemImage: "keyboard")
        }

      PromptsSettingsTab()
        .tabItem {
          Label("Prompts", systemImage: "text.bubble")
        }
    }
    .frame(width: 550, height: 450)
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

      Section("Chat") {
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
  private var configManager = ConfigManager.shared
  @State private var editingPrompt: SavedPrompt?
  @State private var isAddingNew = false
  @State private var promptToDelete: SavedPrompt?

  var body: some View {
    Form {
      Section("Saved Prompts") {
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
          .frame(maxWidth: .infinity)
          .padding(.vertical, 16)
        } else {
          ForEach(configManager.config.savedPrompts) { prompt in
            SavedPromptRow(
              prompt: prompt,
              onEdit: {
                editingPrompt = prompt
              },
              onDelete: {
                promptToDelete = prompt
              }
            )
          }
        }
      }

      Section {
        Button {
          isAddingNew = true
        } label: {
          HStack {
            Image(systemName: "plus")
            Text("Add Prompt")
          }
        }
      }
    }
    .formStyle(.grouped)
    .scrollContentBackground(.hidden)
    .padding()
    .background(appBackgroundColor)
    .sheet(isPresented: $isAddingNew) {
      PromptEditorSheet(prompt: nil) { newPrompt in
        configManager.config.savedPrompts.append(newPrompt)
      }
    }
    .sheet(item: $editingPrompt) { prompt in
      PromptEditorSheet(prompt: prompt) { updatedPrompt in
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
          configManager.config.savedPrompts.removeAll { $0.id == prompt.id }
        }
        promptToDelete = nil
      }
    } message: {
      if let prompt = promptToDelete {
        Text("Are you sure you want to delete \"\(prompt.name)\"? This cannot be undone.")
      }
    }
  }
}

/// A row displaying a saved prompt with edit and delete actions.
struct SavedPromptRow: View {
  let prompt: SavedPrompt
  let onEdit: () -> Void
  let onDelete: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(prompt.name)
          .font(.system(size: 13, weight: .medium))

        Spacer()

        Button {
          onEdit()
        } label: {
          Image(systemName: "pencil")
            .font(.system(size: 12))
        }
        .buttonStyle(.plain)
        .foregroundColor(.secondary)

        Button {
          onDelete()
        } label: {
          Image(systemName: "trash")
            .font(.system(size: 12))
        }
        .buttonStyle(.plain)
        .foregroundColor(.secondary)
      }

      if !prompt.promptDescription.isEmpty {
        Text(prompt.promptDescription)
          .font(.system(size: 11))
          .foregroundColor(.secondary)
          .lineLimit(1)
      }

      Text(prompt.promptText)
        .font(.system(size: 11, design: .monospaced))
        .foregroundColor(.secondary)
        .lineLimit(2)
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(appCardColor)
        .cornerRadius(4)
    }
    .padding(.vertical, 4)
  }
}

/// A sheet for creating or editing a saved prompt.
struct PromptEditorSheet: View {
  let prompt: SavedPrompt?
  let onSave: (SavedPrompt) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var name: String = ""
  @State private var promptDescription: String = ""
  @State private var promptText: String = ""

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

        VStack(alignment: .leading, spacing: 6) {
          Text("Prompt Text")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.secondary)

          TextEditor(text: $promptText)
            .font(.system(size: 12, design: .monospaced))
            .frame(minHeight: 120)
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
    .frame(width: 450)
    .fixedSize(horizontal: false, vertical: true)
    .background(appBackgroundColor)
    .onAppear {
      if let prompt {
        name = prompt.name
        promptDescription = prompt.promptDescription
        promptText = prompt.promptText
      }
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
      createdAt: prompt?.createdAt ?? Date(),
      updatedAt: Date()
    )
    onSave(saved)
    dismiss()
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
