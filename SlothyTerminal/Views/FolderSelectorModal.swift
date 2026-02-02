import SwiftUI

/// A modal view for selecting a working directory.
/// Shows recent folders and provides access to the system folder picker.
struct FolderSelectorModal: View {
  let agent: AgentType
  let onSelect: (URL) -> Void

  @Environment(\.dismiss) private var dismiss
  private let recentFoldersManager = RecentFoldersManager.shared

  init(agent: AgentType, onSelect: @escaping (URL) -> Void) {
    self.agent = agent
    self.onSelect = onSelect
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

    if panel.runModal() == .OK, let url = panel.url {
      selectFolder(url)
    }
  }

  /// Selects a folder and closes the modal.
  private func selectFolder(_ url: URL) {
    recentFoldersManager.addRecentFolder(url)
    onSelect(url)
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

#Preview("With Recent") {
  FolderSelectorModal(agent: .claude) { url in
    print("Selected: \(url)")
  }
}

#Preview("Empty") {
  FolderSelectorModal(agent: .opencode) { url in
    print("Selected: \(url)")
  }
}
