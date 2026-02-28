import SwiftUI

/// A modal view for selecting a working directory.
/// Shows recent folders and provides access to the system folder picker.
struct FolderSelectorModal: View {
  let agent: AgentType
  let onSelect: (URL, SavedPrompt?) -> Void

  @Environment(\.dismiss) private var dismiss
  private let recentFoldersManager = RecentFoldersManager.shared
  private let configManager = ConfigManager.shared
  @State private var selectedPromptID: UUID?

  private var savedPrompts: [SavedPrompt] {
    configManager.config.savedPrompts
  }

  private var selectedPrompt: SavedPrompt? {
    savedPrompts.find(by: selectedPromptID)
  }

  init(agent: AgentType, onSelect: @escaping (URL, SavedPrompt?) -> Void) {
    self.agent = agent
    self.onSelect = onSelect
  }

  private var showPromptPicker: Bool {
    agent.supportsInitialPrompt && !savedPrompts.isEmpty
  }

  var body: some View {
    VStack(spacing: 0) {
      /// Header.
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text("Select Working Directory")
            .font(.headline)

          Text("Choose a folder for your \(agent.rawValue) session")
            .font(.subheadline)
            .foregroundColor(.secondary)
        }

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

      if showPromptPicker {
        PromptPicker(selectedPromptID: $selectedPromptID, savedPrompts: savedPrompts)
          .padding(.horizontal, 20)
          .padding(.vertical, 12)

        Divider()
      }

      /// Recent folders section.
      if !recentFoldersManager.recentFolders.isEmpty {
        VStack(alignment: .leading, spacing: 12) {
          Text("RECENT FOLDERS")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.secondary)

          VStack(spacing: 4) {
            ForEach(recentFoldersManager.recentFolders.prefix(8), id: \.path) { folder in
              RecentFolderButton(
                folder: folder,
                accentColor: agent.accentColor,
                onSelect: {
                  selectFolder(folder)
                },
                onRemove: {
                  recentFoldersManager.removeRecentFolder(folder)
                }
              )
            }
          }
        }
        .padding(20)

        Divider()
      }

      /// Browse button section.
      VStack(spacing: 16) {
        if recentFoldersManager.recentFolders.isEmpty {
          VStack(spacing: 12) {
            Image(systemName: "folder.badge.plus")
              .font(.system(size: 40))
              .foregroundColor(.secondary)

            Text("No recent folders")
              .font(.subheadline)
              .foregroundColor(.secondary)
          }
          .padding(.vertical, 20)
        }

        Button {
          openSystemFolderPicker()
        } label: {
          HStack {
            Image(systemName: "folder")
            Text("Browse...")
          }
          .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(agent.accentColor)
        .controlSize(.large)
      }
      .padding(20)

      Divider()

      /// Footer with cancel button.
      HStack {
        Button("Cancel") {
          dismiss()
        }
        .keyboardShortcut(.escape)

        Spacer()
      }
      .padding(16)
    }
    .frame(width: 400)
    .fixedSize(horizontal: false, vertical: true)
    .background(appBackgroundColor)
  }

  /// Opens the system folder picker.
  private func openSystemFolderPicker() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true
    panel.message = "Select a working directory for \(agent.rawValue)"
    panel.prompt = "Select"

    /// Start in home directory or last used folder.
    if let lastFolder = recentFoldersManager.recentFolders.first {
      panel.directoryURL = lastFolder
    } else {
      panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
    }

    panel.begin { response in
      if response == .OK, let url = panel.url {
        selectFolder(url)
      }
    }
  }

  /// Selects a folder and closes the modal.
  private func selectFolder(_ url: URL) {
    recentFoldersManager.addRecentFolder(url)
    onSelect(url, selectedPrompt)
    dismiss()
  }
}

/// A button representing a recent folder.
struct RecentFolderButton: View {
  let folder: URL
  let accentColor: Color
  let onSelect: () -> Void
  let onRemove: () -> Void

  @State private var isHovered = false

  private var displayPath: String {
    let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
    let path = folder.path

    if path.hasPrefix(homeDir) {
      return "~" + path.dropFirst(homeDir.count)
    }
    return path
  }

  private var folderExists: Bool {
    FileManager.default.fileExists(atPath: folder.path)
  }

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: "folder.fill")
        .font(.system(size: 16))
        .foregroundColor(folderExists ? accentColor : .secondary)

      VStack(alignment: .leading, spacing: 2) {
        Text(folder.lastPathComponent)
          .font(.system(size: 13, weight: .medium))
          .foregroundColor(folderExists ? .primary : .secondary)

        Text(displayPath)
          .font(.system(size: 11))
          .foregroundColor(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }

      Spacer()

      if isHovered {
        Button {
          onRemove()
        } label: {
          Image(systemName: "xmark.circle.fill")
            .font(.system(size: 14))
            .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .help("Remove from recent")
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(
      RoundedRectangle(cornerRadius: 8)
        .fill(isHovered ? appCardColor : Color.clear)
    )
    .contentShape(Rectangle())
    .onHover { hovering in
      isHovered = hovering
    }
    .onTapGesture {
      if folderExists {
        onSelect()
      }
    }
    .opacity(folderExists ? 1.0 : 0.6)
    .help(folderExists ? "Open \(folder.lastPathComponent)" : "Folder not found")
  }
}

// MARK: - Prompt Picker

/// A reusable picker for selecting a saved prompt.
struct PromptPicker: View {
  @Binding var selectedPromptID: UUID?
  let savedPrompts: [SavedPrompt]

  private var selectedPrompt: SavedPrompt? {
    savedPrompts.find(by: selectedPromptID)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("PROMPT")
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(.secondary)

      Menu {
        Button {
          selectedPromptID = nil
        } label: {
          PromptMenuRow(
            title: "No prompt",
            subtitle: "Start without predefined prompt",
            isSelected: selectedPromptID == nil
          )
        }

        Divider()

        ForEach(savedPrompts) { prompt in
          Button {
            selectedPromptID = prompt.id
          } label: {
            PromptMenuRow(
              title: prompt.name,
              subtitle: prompt.previewText(),
              isSelected: selectedPromptID == prompt.id
            )
          }
        }
      } label: {
        PromptSelectionLabel(
          title: selectedPrompt?.name ?? "No prompt",
          subtitle: selectedPrompt?.previewText() ?? "Start without predefined prompt"
        )
      }
      .menuStyle(.borderlessButton)
      .fixedSize(horizontal: false, vertical: true)
    }
  }
}

/// The selected prompt label displayed above the prompt options menu.
private struct PromptSelectionLabel: View {
  let title: String
  let subtitle: String

  var body: some View {
    HStack(spacing: 8) {
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.system(size: 12, weight: .medium))
          .foregroundColor(.primary)
          .lineLimit(1)

        Text(subtitle)
          .font(.system(size: 11))
          .foregroundColor(.secondary)
          .lineLimit(1)
      }

      Spacer()

      Image(systemName: "chevron.up.chevron.down")
        .font(.system(size: 10, weight: .semibold))
        .foregroundColor(.secondary)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(appCardColor)
    .cornerRadius(8)
  }
}

/// A menu row with prompt title and short preview text.
private struct PromptMenuRow: View {
  let title: String
  let subtitle: String
  let isSelected: Bool

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: "checkmark")
        .foregroundColor(.accentColor)
        .opacity(isSelected ? 1 : 0)
        .frame(width: 12, alignment: .leading)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .lineLimit(1)

        Text(subtitle)
          .font(.caption)
          .foregroundColor(.secondary)
          .lineLimit(1)
      }
    }
  }
}

#Preview("With Recent") {
  FolderSelectorModal(agent: .claude) { url, prompt in
    print("Selected: \(url), prompt: \(prompt?.name ?? "none")")
  }
}

#Preview("Empty") {
  FolderSelectorModal(agent: .opencode) { url, prompt in
    print("Selected: \(url), prompt: \(prompt?.name ?? "none")")
  }
}
