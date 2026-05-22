import AppKit
import OSLog
import SwiftUI

/// Main settings view with sidebar navigation.
struct SettingsView: View {
  @Environment(AppState.self) private var appState
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

        case .appearance:
          AppearanceSettingsTab()

        case .shortcuts:
          ShortcutsSettingsTab()

        case .prompts:
          PromptsSettingsTab()

        case .usage:
          UsageSettingsTab()

        case .logs:
          LogsSettingsTab()

        case .licenses:
          LicensesSettingsTab()
        }
      }
    }
    .frame(minWidth: 600, idealWidth: 700, minHeight: 450)
    .background(appBackgroundColor)
    .onAppear {
      if let section = appState.pendingSettingsSection {
        selectedSection = section
        appState.pendingSettingsSection = nil
      }
    }
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
            value: Binding(
              get: {
                appState.sidebarWidth
              },
              set: { newValue in
                appState.sidebarWidth = newValue
              }
            ),
            in: 200...500,
            step: 10
          )
          Text("\(Int(appState.sidebarWidth))px")
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
            .appFont(.caption)
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
              .appFont(.caption)
              .foregroundColor(.secondary)

            ForEach(recentFoldersManager.recentFolders.prefix(5), id: \.path) { folder in
              HStack {
                Text(shortenedPath(folder.path))
                  .appFont(size: 11, design: .monospaced)
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
          .appFont(size: 11, design: .monospaced)
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
                    .appFont(size: 12)
                }

                Text(app.name)
                  .appFont(size: 12)
              }
            }
            .buttonStyle(.bordered)
          }
        }

        if editorApps.isEmpty {
          Text("No supported editors found. Install VS Code, Cursor, or Antigravity.")
            .appFont(.caption)
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
    ExternalAppManager.shared.installedEditorApps
  }

  private func shortenedPath(_ path: String) -> String {
    let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
    if path.hasPrefix(homeDir) {
      return "~" + path.dropFirst(homeDir.count)
    }
    return path
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

      Section("App Font") {
        Picker("UI font", selection: Bindable(configManager).config.appFont) {
          ForEach(AppFont.allCases, id: \.self) { font in
            Text(font.displayName).tag(font)
          }
        }
        .pickerStyle(.segmented)

        VStack(alignment: .leading, spacing: 4) {
          Text("Preview")
            .appFont(.caption)
            .foregroundColor(.secondary)

          Text("The quick brown fox jumps over the lazy dog. 0123456789")
            .appFont(configManager.config.appFont)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(appCardColor)
            .cornerRadius(6)
        }

        /// This caption intentionally renders in the picked font — it doubles
        /// as a live preview of the selection. Do not force it back to system.
        Text("Affects in-app UI text. Native window chrome and the terminal use their own fonts.")
          .appFont(.caption)
          .foregroundColor(.secondary)
      }

      Section("Editor Font") {
        Picker("Font family", selection: Bindable(configManager).config.editorFontName) {
          ForEach(ConfigManager.availableMonospacedFonts, id: \.self) { font in
            Text(font).tag(font)
          }
        }

        HStack {
          Text("Font size")
          Slider(
            value: Bindable(configManager).config.editorFontSize,
            in: 10...24,
            step: 1
          )
          Text("\(Int(configManager.config.editorFontSize))pt")
            .monospacedDigit()
            .frame(width: 40, alignment: .trailing)
        }

        /// Font preview — Swift-flavored sample so users can judge how
        /// code reads in the picked family.
        VStack(alignment: .leading, spacing: 4) {
          Text("Preview")
            .appFont(.caption)
            .foregroundColor(.secondary)

          Text("func greet(name: String) -> String {\n  return \"Hello, \\(name)!\"\n}\n// 0123456789 → != <= >=")
            .font(.custom(
              configManager.config.editorFontName,
              size: configManager.config.editorFontSize
            ))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(appCardColor)
            .cornerRadius(6)
        }
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
            .appFont(.caption)
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
          .appFont(.caption)
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
        .appFont(.caption)
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
        .appFont(size: 12, design: .monospaced)
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
          .appFont(.headline)

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
            .appFont(size: 32)
            .foregroundColor(.secondary)

          Text("No saved prompts")
            .appFont(.subheadline)
            .foregroundColor(.secondary)

          Text("Create reusable prompts to attach when opening AI agent tabs.")
            .appFont(.caption)
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
              .appFont(size: 11, design: .monospaced)
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
        .appFont(.caption)
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
          .appFont(.headline)

        Spacer()

        Button {
          dismiss()
        } label: {
          Image(systemName: "xmark.circle.fill")
            .appFont(size: 20)
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
            .appFont(.caption)
            .foregroundColor(.red)
        } else if let validationError {
          Text(validationError)
            .appFont(.caption)
            .foregroundColor(.red)
        }

        if tags.isEmpty {
          VStack(spacing: 8) {
            Image(systemName: "tag")
              .appFont(size: 24)
              .foregroundColor(.secondary)

            Text("No tags yet")
              .appFont(.subheadline)
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
        AppButton("Cancel") {
          dismiss()
        }
        .keyboardShortcut(.escape)

        Spacer()

        AppButton("Save") {
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
          .appFont(.headline)

        Spacer()

        Button {
          dismiss()
        } label: {
          Image(systemName: "xmark.circle.fill")
            .appFont(size: 20)
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
            .appFont(size: 11, weight: .semibold)
            .foregroundColor(.secondary)

          TextField("e.g. Code Reviewer", text: $name)
            .textFieldStyle(.roundedBorder)
        }

        VStack(alignment: .leading, spacing: 6) {
          Text("Description (optional)")
            .appFont(size: 11, weight: .semibold)
            .foregroundColor(.secondary)

          TextField("Brief description of this prompt", text: $promptDescription)
            .textFieldStyle(.roundedBorder)
        }

        if !availableTags.isEmpty {
          VStack(alignment: .leading, spacing: 6) {
            Text("Tags")
              .appFont(size: 11, weight: .semibold)
              .foregroundColor(.secondary)

            ScrollView {
              VStack(alignment: .leading, spacing: 6) {
                ForEach(sortedAvailableTags) { tag in
                  Toggle(isOn: tagBinding(for: tag.id)) {
                    Text(tag.name)
                      .appFont(size: 12)
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
            .appFont(size: 11, weight: .semibold)
            .foregroundColor(.secondary)

          TextEditor(text: $promptText)
            .appFont(size: 12, design: .monospaced)
            .frame(maxHeight: .infinity)
            .scrollContentBackground(.hidden)
            .padding(8)
            .background(appCardColor)
            .cornerRadius(6)

          HStack {
            Spacer()

            Text("\(promptText.count) / \(maxPromptLength)")
              .appFont(size: 10)
              .foregroundColor(promptText.count > maxPromptLength ? .red : .secondary)
          }
        }
      }
      .padding(20)

      Divider()

      /// Footer with action buttons.
      HStack {
        AppButton("Cancel") {
          dismiss()
        }
        .keyboardShortcut(.escape)

        Spacer()

        AppButton("Save") {
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

// MARK: - Usage Settings Tab

struct UsageSettingsTab: View {
  private var configManager = ConfigManager.shared
  private var usageService = UsageService.shared
  private var responseStore = ProviderResponseStore.shared

  @State private var cursorJWTInput: String = ""
  @State private var hasSavedCursorJWT: Bool = false
  @State private var cursorAutoDetected: Bool = false
  @State private var saveError: String?
  @State private var showManualOverride: Bool = false
  @State private var expandedResponseIDs: Set<String> = []
  @State private var minimaxAPIKeyInput: String = ""
  @State private var hasSavedMinimaxKey: Bool = false
  @State private var minimaxTestResult: String? = nil

  var body: some View {
    Form {
      Section("Usage Tracking") {
        Toggle("Enable usage tracking", isOn: Binding(
          get: { configManager.config.usagePreferences.isEnabled },
          set: { newValue in
            configManager.config.usagePreferences.isEnabled = newValue
            usageService.startIfEnabled()
          }
        ))

        Text("When enabled, SlothyTerminal periodically fetches usage and rate-limit data for connected providers and shows them in the status bar.")
          .appFont(.caption)
          .foregroundColor(.secondary)
      }

      providerResponsesSection

      Section("Cursor") {
        HStack(alignment: .top, spacing: 8) {
          Image(systemName: cursorStatusIcon)
            .foregroundColor(cursorStatusColor)

          VStack(alignment: .leading, spacing: 2) {
            Text(cursorStatusHeadline)
              .appFont(size: 12, weight: .medium)

            Text(cursorStatusDetail)
              .appFont(.caption)
              .foregroundColor(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }

          Spacer()
        }

        DisclosureGroup(isExpanded: $showManualOverride) {
          VStack(alignment: .leading, spacing: 8) {
            Text("Use this only when Cursor.app isn't installed or auto-detect isn't working. Open cursor.com signed in, copy the `WorkosCursorSessionToken` cookie, and paste the part after `::` below.")
              .appFont(.caption)
              .foregroundColor(.secondary)
              .fixedSize(horizontal: false, vertical: true)

            SecureField("Cursor session JWT", text: $cursorJWTInput)
              .textFieldStyle(.roundedBorder)
              .appFont(size: 11, design: .monospaced)

            HStack {
              Button("Save Token") {
                saveCursorJWT()
              }
              .disabled(cursorJWTInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

              if hasSavedCursorJWT {
                Button("Clear Saved Token") {
                  clearCursorJWT()
                }
                .buttonStyle(.borderless)
              }

              if let saveError {
                Text(saveError)
                  .appFont(.caption)
                  .foregroundColor(.red)
              }
            }
          }
          .padding(.top, 4)
        } label: {
          Text("Manual override")
            .appFont(size: 11, weight: .semibold)
            .foregroundColor(.secondary)
        }
      }

      Section("MiniMax") {
        HStack(alignment: .top, spacing: 8) {
          Image(systemName: hasSavedMinimaxKey ? "checkmark.circle.fill" : "exclamationmark.circle")
            .foregroundColor(hasSavedMinimaxKey ? .green : .secondary)

          VStack(alignment: .leading, spacing: 2) {
            Text(hasSavedMinimaxKey ? "API key saved" : "MiniMax not connected")
              .appFont(size: 12, weight: .medium)

            Text("Get your key from platform.minimax.io → User Center → Interface Key.")
              .appFont(.caption)
              .foregroundColor(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }

          Spacer()
        }

        VStack(alignment: .leading, spacing: 8) {
          SecureField("MiniMax API key", text: $minimaxAPIKeyInput)
            .textFieldStyle(.roundedBorder)
            .appFont(size: 11, design: .monospaced)

          HStack {
            Button("Save Key") {
              saveMinimaxKey()
            }
            .disabled(minimaxAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if hasSavedMinimaxKey {
              Button("Fetch Usage") {
                fetchMinimaxUsageViaService()
              }

              Button("Test Connection") {
                testMinimaxConnection()
              }
              .buttonStyle(.borderless)

              Button("Clear Saved Key") {
                clearMinimaxKey()
              }
              .buttonStyle(.borderless)
            }
          }

          if let result = minimaxTestResult {
            Text(result)
              .appFont(.caption)
              .foregroundColor(result.hasPrefix("✓") ? .green : (result.hasPrefix("✗") ? .red : .secondary))
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
    }
    .formStyle(.grouped)
    .scrollContentBackground(.hidden)
    .padding()
    .background(appBackgroundColor)
    .onAppear {
      refreshCursorState()
      refreshMinimaxState()

      // Re-resolve auth sources whenever Settings opens. Catches the case
      // where the app launched without the MiniMax key in Keychain (so
      // .minimax wasn't in resolvedSources), the user later saved a key,
      // but the save-time fetch somehow didn't reach the status bar.
      Task {
        Logger.usage.info("[usage-settings] onAppear — re-resolving auth + fetching MiniMax")
        await usageService.resolveAuthSources()

        if usageService.authSource(for: .minimax) != nil {
          await usageService.fetch(provider: .minimax)
        }
      }
    }
  }

  // MARK: - Cursor Status

  private var cursorStatusIcon: String {
    if cursorAutoDetected {
      return "checkmark.circle.fill"
    }

    if hasSavedCursorJWT {
      return "checkmark.circle"
    }

    return "exclamationmark.circle"
  }

  private var cursorStatusColor: Color {
    if cursorAutoDetected {
      return .green
    }

    if hasSavedCursorJWT {
      return .blue
    }

    return .secondary
  }

  private var cursorStatusHeadline: String {
    if cursorAutoDetected {
      return "Auto-detected from Cursor.app"
    }

    if hasSavedCursorJWT {
      return "Using manually-pasted token"
    }

    return "Cursor not connected"
  }

  private var cursorStatusDetail: String {
    if cursorAutoDetected {
      return "Reading the session token directly from Cursor's local state. Refreshes automatically when Cursor rotates the token."
    }

    if hasSavedCursorJWT {
      return "Cursor.app isn't installed or its state file isn't readable, so SlothyTerminal is using the JWT you pasted. Install Cursor.app to switch to auto-detect."
    }

    return "Install Cursor.app and sign in, or expand Manual override to paste a session token."
  }

  // MARK: - Actions

  private func refreshCursorState() {
    cursorAutoDetected = CursorUsageProvider.canReadStateDB()
    hasSavedCursorJWT = UsageKeychainStore.loadString(
      provider: .cursor,
      sourceKind: .apiKey
    ) != nil
  }

  private func saveCursorJWT() {
    let trimmed = cursorJWTInput.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !trimmed.isEmpty else {
      return
    }

    let saved = UsageKeychainStore.saveString(
      trimmed,
      provider: .cursor,
      sourceKind: .apiKey
    )

    if saved {
      saveError = nil
      hasSavedCursorJWT = true
      cursorJWTInput = ""
      Task {
        await usageService.resolveAuthSources()
        await usageService.fetch(provider: .cursor)
      }
    } else {
      saveError = "Failed to save token to Keychain."
    }
  }

  private func clearCursorJWT() {
    UsageKeychainStore.delete(provider: .cursor, sourceKind: .apiKey)
    hasSavedCursorJWT = false
    cursorJWTInput = ""
    saveError = nil
    usageService.clearProvider(.cursor)
  }

  private func refreshMinimaxState() {
    hasSavedMinimaxKey = UsageKeychainStore.loadString(
      provider: .minimax,
      sourceKind: .apiKey
    ) != nil
  }

  private func saveMinimaxKey() {
    let trimmed = minimaxAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)

    Logger.usage.info("[minimax] saveMinimaxKey entry — inputLength=\(trimmed.count)")

    guard !trimmed.isEmpty else {
      Logger.usage.warning("[minimax] Save aborted — empty input")
      return
    }

    let saved = UsageKeychainStore.saveString(
      trimmed,
      provider: .minimax,
      sourceKind: .apiKey
    )

    Logger.usage.info("[minimax] Keychain save returned: \(saved)")

    if saved {
      hasSavedMinimaxKey = true
      minimaxAPIKeyInput = ""
      Task {
        Logger.usage.info("[minimax] Save-time Task starting")
        await usageService.resolveAuthSources()
        Logger.usage.info("[minimax] resolveAuthSources done — about to fetch")
        await usageService.fetch(provider: .minimax)
        Logger.usage.info("[minimax] Save-time fetch complete")
      }
    } else {
      saveError = "Failed to save MiniMax key to Keychain."
    }
  }

  private func clearMinimaxKey() {
    UsageKeychainStore.delete(provider: .minimax, sourceKind: .apiKey)
    hasSavedMinimaxKey = false
    minimaxAPIKeyInput = ""
    minimaxTestResult = nil
    usageService.clearProvider(.minimax)
  }

  /// Direct end-to-end smoke test that bypasses the status-bar wiring.
  /// Reads the saved key from Keychain, calls MiniMax, and shows the
  /// outcome inline. Used to isolate API/auth issues from SwiftUI
  /// plumbing issues.
  private func testMinimaxConnection() {
    minimaxTestResult = "Testing…"

    Task {
      guard let key = UsageKeychainStore.loadString(
        provider: .minimax,
        sourceKind: .apiKey
      ) else {
        minimaxTestResult = "✗ No saved key in Keychain"
        return
      }

      do {
        let snapshot = try await MinimaxUsageProvider.fetchUsage(apiKey: key)

        if let percent = snapshot.percentUsed {
          minimaxTestResult = "✓ Connected — \(snapshot.used) / \(snapshot.limit ?? "?") (\(Int(percent * 100))%)"
        } else {
          minimaxTestResult = "✓ Connected — \(snapshot.used)"
        }
      } catch UsageFetchError.tokenExpired {
        minimaxTestResult = "✗ HTTP 401/403 — key rejected by MiniMax"
      } catch UsageFetchError.httpError(let code) {
        minimaxTestResult = "✗ HTTP \(code) — see Console.app logs"
      } catch UsageFetchError.parseError {
        minimaxTestResult = "✗ Could not parse response — see Console.app logs"
      } catch {
        minimaxTestResult = "✗ \(error.localizedDescription)"
      }
    }
  }

  /// Runs the full UsageService fetch chain — same path the status bar
  /// reads from. Distinct from `testMinimaxConnection`, which calls the
  /// provider's HTTP client directly. Reading back `status(for: .minimax)`
  /// after the await makes any Observable / service-layer issue inspectable.
  private func fetchMinimaxUsageViaService() {
    minimaxTestResult = "Fetching via UsageService…"

    Task {
      await usageService.resolveAuthSources()
      await usageService.fetch(provider: .minimax)

      let status = usageService.status(for: .minimax)
      let snapshot = usageService.snapshot(for: .minimax)

      switch status {
      case .loaded:
        if let snapshot, let percent = snapshot.percentUsed {
          minimaxTestResult = "✓ Status: loaded — \(snapshot.used) / \(snapshot.limit ?? "?") (\(Int(percent * 100))%) — bar should be visible"
        } else if let snapshot {
          minimaxTestResult = "✓ Status: loaded — \(snapshot.used) — bar should be visible"
        } else {
          minimaxTestResult = "✓ Status: loaded but snapshot is nil (Observable bug?)"
        }

      case .loading:
        minimaxTestResult = "… Status: loading (still in flight)"

      case .failed(let msg):
        minimaxTestResult = "✗ Status: failed — \(msg)"

      case .tokenExpired:
        minimaxTestResult = "✗ Status: token expired — MiniMax rejected the key"

      case .unavailable(let reason):
        minimaxTestResult = "✗ Status: unavailable — \(reason)"

      case .idle:
        minimaxTestResult = "✗ Status: idle — fetch never ran (Task cancelled / Observable bug)"
      }
    }
  }

  // MARK: - Provider Responses

  /// Sorted snapshot of captured responses, grouped by provider and then by
  /// endpoint name so the UI order is stable across refetches.
  private var sortedResponses: [ProviderResponseStore.Entry] {
    responseStore.entries.sorted { lhs, rhs in
      if lhs.provider.rawValue != rhs.provider.rawValue {
        return lhs.provider.rawValue < rhs.provider.rawValue
      }

      return lhs.endpoint < rhs.endpoint
    }
  }

  @ViewBuilder
  private var providerResponsesSection: some View {
    Section {
      Text("The most recent JSON each provider returned. Useful when deciding what new data to surface — auth headers aren't stored, and email-shaped strings are scrubbed before display.")
        .appFont(.caption)
        .foregroundColor(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      if sortedResponses.isEmpty {
        Text("No responses captured yet. Enable usage tracking and connect a provider, then trigger a fetch.")
          .appFont(.caption)
          .foregroundColor(.secondary)
      } else {
        ForEach(sortedResponses) { entry in
          ProviderResponseRow(
            entry: entry,
            isExpanded: expandedResponseIDs.contains(entry.id),
            onToggleExpand: {
              if expandedResponseIDs.contains(entry.id) {
                expandedResponseIDs.remove(entry.id)
              } else {
                expandedResponseIDs.insert(entry.id)
              }
            },
            onRefetch: {
              Task {
                await usageService.fetch(provider: entry.provider)
              }
            }
          )
        }

        Button("Clear Captured Responses") {
          responseStore.clear()
          expandedResponseIDs.removeAll()
        }
        .buttonStyle(.borderless)
      }
    } header: {
      Text("Latest JSON Responses")
    }
  }
}

/// One captured response row with status badge, URL, body preview, and
/// per-row actions (copy, refetch, expand).
private struct ProviderResponseRow: View {
  let entry: ProviderResponseStore.Entry
  let isExpanded: Bool
  let onToggleExpand: () -> Void
  let onRefetch: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        Text(entry.provider.displayName)
          .appFont(size: 12, weight: .semibold)

        Text(entry.endpoint)
          .appFont(size: 11, design: .monospaced)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(appCardColor)
          .cornerRadius(3)

        statusBadge

        Spacer()

        Text(entry.fetchedAt, style: .relative)
          .appFont(.caption)
          .foregroundColor(.secondary)

        Button {
          onToggleExpand()
        } label: {
          Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(isExpanded ? "Collapse response" : "Expand response")
      }

      /// URL path (host omitted) — keeps the meaningful endpoint visible
      /// even when the row is narrow. Full URL is reachable via Copy JSON
      /// for the rare case it matters.
      Text(displayURL)
        .appFont(size: 10, design: .monospaced)
        .foregroundColor(.secondary)
        .lineLimit(1)
        .truncationMode(.middle)

      if let error = entry.error {
        Text("Error: \(error)")
          .appFont(.caption)
          .foregroundColor(.red)
      }

      if isExpanded {
        ScrollView([.horizontal, .vertical]) {
          Text(entry.prettyBody)
            .appFont(size: 11, design: .monospaced)
            .textSelection(.enabled)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 320)
        .background(appCardColor)
        .cornerRadius(6)

        HStack(spacing: 8) {
          Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(entry.prettyBody, forType: .string)
          } label: {
            Label("Copy JSON", systemImage: "doc.on.doc")
          }
          .buttonStyle(.bordered)

          Button {
            onRefetch()
          } label: {
            Label("Refetch", systemImage: "arrow.clockwise")
          }
          .buttonStyle(.bordered)

          Spacer()

          Text("\(entry.byteCount) bytes")
            .appFont(.caption)
            .foregroundColor(.secondary)
        }
      }
    }
    .padding(.vertical, 2)
  }

  /// Host + path — drops scheme noise but keeps enough to disambiguate
  /// providers that share an endpoint name (e.g. `admin-orgs` vs
  /// `browser-orgs`).
  private var displayURL: String {
    guard let parsed = URL(string: entry.url),
          let host = parsed.host
    else {
      return entry.url
    }

    return host + parsed.path
  }

  private var statusBadge: some View {
    let descriptor = statusDescriptor

    return Text(descriptor.label)
      .appFont(size: 10, weight: .semibold, design: .monospaced)
      .foregroundColor(descriptor.foreground)
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(descriptor.background)
      .cornerRadius(3)
      .accessibilityLabel("HTTP status \(descriptor.label)")
  }

  private var statusDescriptor: (label: String, foreground: Color, background: Color) {
    guard let code = entry.statusCode else {
      // Transport error / no status — keep readable on the muted background.
      return ("—", .primary, Color.secondary.opacity(0.25))
    }

    switch code {
    case 200..<300:
      return ("\(code)", .white, .green)

    case 400..<500:
      return ("\(code)", .white, .orange)

    case 500..<600:
      return ("\(code)", .white, .red)

    default:
      return ("\(code)", .primary, Color.secondary.opacity(0.25))
    }
  }
}

// MARK: - Logs Settings Tab

struct LogsSettingsTab: View {
  @State private var entries: [LogReader.Entry] = []
  @State private var minLevel: LogReader.Level = .error
  @State private var selectedCategory: String = "All"
  @State private var isPaused: Bool = false
  @State private var lastRefreshDate: Date = .now
  @State private var lastError: String?
  @State private var hasLoadedOnce: Bool = false

  /// Rolling 2-hour window, anchored at "now" on every fetch.
  private let timeWindowSeconds: TimeInterval = 2 * 60 * 60
  private let refreshInterval: Duration = .seconds(2)

  private var availableCategories: [String] {
    var categories = Set(entries.map(\.category))

    if selectedCategory != "All" {
      categories.insert(selectedCategory)
    }

    return ["All"] + categories.sorted()
  }

  private var filteredEntries: [LogReader.Entry] {
    let matched = entries.filter { entry in
      selectedCategory == "All" || entry.category == selectedCategory
    }

    return matched.sorted { lhs, rhs in
      lhs.date > rhs.date
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      controls

      if let lastError {
        Text("Failed to read logs: \(lastError)")
          .appFont(.caption)
          .foregroundColor(.red)
      }

      Divider()

      if filteredEntries.isEmpty {
        emptyState
      } else {
        logList
      }

      Divider()

      footer
    }
    .padding()
    .background(appBackgroundColor)
    .task(id: isPaused) {
      guard !isPaused else {
        return
      }

      while !Task.isCancelled {
        await refresh()

        do {
          try await Task.sleep(for: refreshInterval)
        } catch {
          return
        }
      }
    }
    .onChange(of: minLevel) { _, _ in
      Task {
        await refresh()
      }
    }
  }

  private var controls: some View {
    HStack(spacing: 12) {
      Picker("Min level", selection: $minLevel) {
        ForEach(LogReader.Level.allCases, id: \.self) { level in
          Text(level.displayName).tag(level)
        }
      }
      .pickerStyle(.menu)
      .frame(maxWidth: 200)

      Picker("Category", selection: $selectedCategory) {
        ForEach(availableCategories, id: \.self) { category in
          Text(category).tag(category)
        }
      }
      .pickerStyle(.menu)
      .frame(maxWidth: 220)

      Spacer()

      Button {
        isPaused.toggle()
      } label: {
        Label(
          isPaused ? "Resume" : "Pause",
          systemImage: isPaused ? "play.fill" : "pause.fill"
        )
      }

      Button {
        Task {
          await refresh()
        }
      } label: {
        Label("Refresh", systemImage: "arrow.clockwise")
      }
    }
  }

  private var emptyState: some View {
    VStack(spacing: 8) {
      Image(systemName: "doc.text.magnifyingglass")
        .appFont(size: 32)
        .foregroundColor(.secondary)

      Text(hasLoadedOnce ? "No log entries match the current filter." : "Loading…")
        .appFont(.subheadline)
        .foregroundColor(.secondary)

      Text("Showing entries from the last 2 hours.")
        .appFont(.caption)
        .foregroundColor(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var logList: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 0) {
        ForEach(filteredEntries) { entry in
          LogRow(entry: entry)
          Divider()
        }
      }
    }
    .background(appCardColor)
    .cornerRadius(6)
  }

  private var footer: some View {
    HStack {
      TimelineView(.periodic(from: .now, by: 1.0)) { context in
        Text(statusText(now: context.date))
          .appFont(.caption)
          .foregroundColor(.secondary)
      }

      Spacer()

      Button {
        copyAllToClipboard()
      } label: {
        Label("Copy All", systemImage: "doc.on.doc")
      }
      .disabled(filteredEntries.isEmpty)
    }
  }

  private func statusText(now: Date) -> String {
    let count = filteredEntries.count
    let countText = count == 1 ? "1 entry" : "\(count) entries"

    let agoText: String
    if isPaused {
      agoText = "Paused"
    } else {
      let secondsAgo = max(0, Int(now.timeIntervalSince(lastRefreshDate)))
      agoText = secondsAgo <= 1 ? "Refreshed just now" : "Refreshed \(secondsAgo)s ago"
    }

    return "\(countText) · Last 2h · \(agoText)"
  }

  @MainActor
  private func refresh() async {
    let level = minLevel
    let since = Date().addingTimeInterval(-timeWindowSeconds)

    let result = await Task.detached(priority: .userInitiated) {
      Result {
        try LogReader.fetch(minLevel: level, since: since)
      }
    }.value

    switch result {
    case .success(let fetched):
      entries = fetched
      lastError = nil

    case .failure(let error):
      lastError = error.localizedDescription
    }

    lastRefreshDate = .now
    hasLoadedOnce = true
  }

  private func copyAllToClipboard() {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    let text = filteredEntries.map { entry in
      let timestamp = formatter.string(from: entry.date)
      let level = entry.level.displayName.uppercased()
      return "\(timestamp) \(level) \(entry.category): \(entry.message)"
    }.joined(separator: "\n")

    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }
}

private struct LogRow: View {
  let entry: LogReader.Entry

  private static let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss.SSS"
    return formatter
  }()

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      Text(Self.timeFormatter.string(from: entry.date))
        .appFont(size: 11, design: .monospaced)
        .foregroundColor(.secondary)
        .frame(width: 90, alignment: .leading)

      Text(entry.level.displayName.uppercased())
        .appFont(size: 10, weight: .semibold, design: .monospaced)
        .foregroundColor(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(levelColor)
        .cornerRadius(3)
        .frame(width: 60, alignment: .leading)

      Text(entry.category)
        .appFont(size: 11, design: .monospaced)
        .foregroundColor(.primary)
        .frame(width: 90, alignment: .leading)

      Text(entry.message)
        .appFont(size: 11, design: .monospaced)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
  }

  private var levelColor: Color {
    switch entry.level {
    case .fault, .error:
      return .red

    case .notice:
      return .orange

    case .info:
      return .blue

    case .debug:
      return .gray
    }
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
          .appFont(.caption)
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
            .appFont(.headline)

          Text(description)
            .appFont(.caption)
            .foregroundColor(.secondary)
        }

        Spacer()

        Button {
          withAnimation {
            isExpanded.toggle()
          }
        } label: {
          Text(isExpanded ? "Hide License" : "View License")
            .appFont(.caption)
        }
        .buttonStyle(.bordered)
      }

      if isExpanded {
        ScrollView {
          Text(licenseText)
            .appFont(size: 10, design: .monospaced)
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

#Preview("Appearance") {
  AppearanceSettingsTab()
    .frame(width: 500, height: 400)
}

#Preview("Shortcuts") {
  ShortcutsSettingsTab()
    .frame(width: 500, height: 400)
}
