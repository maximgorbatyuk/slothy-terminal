import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Sidebar panel for workspace-level navigation and status.
struct WorkspacesSidebarView: View {
  @Environment(AppState.self) private var appState
  @State private var closeError: String?
  @State private var draggedWorkspaceID: UUID?
  @State private var swapCooldown = false

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      header

      if appState.workspaces.isEmpty {
        emptyState
      } else {
        ScrollView {
          VStack(alignment: .leading, spacing: 10) {
            ForEach(appState.workspaces) { workspace in
              WorkspaceRowView(
                workspace: workspace,
                isActive: workspace.id == appState.activeWorkspaceID,
                tabCount: appState.tabs(in: workspace.id).count,
                isDragging: draggedWorkspaceID == workspace.id,
                onSelect: {
                  appState.switchWorkspace(id: workspace.id)
                  closeError = nil
                },
                onClose: {
                  closeWorkspace(workspace.id)
                }
              )
              .onDrag {
                draggedWorkspaceID = workspace.id
                return NSItemProvider(object: workspace.id.uuidString as NSString)
              }
              .onDrop(
                of: [UTType.text],
                delegate: WorkspaceReorderDropDelegate(
                  targetWorkspaceID: workspace.id,
                  appState: appState,
                  draggedWorkspaceID: $draggedWorkspaceID,
                  swapCooldown: $swapCooldown
                )
              )
            }
          }
        }

        newWorkspaceButton
      }

      if let closeError {
        Text(closeError)
          .font(.system(size: 11))
          .foregroundColor(.red)
      }

      Spacer()
    }
    .padding()
    .background(appBackgroundColor)
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text("Workspaces")
        .font(.system(size: 16, weight: .semibold))

      Text("Group tabs by project root.")
        .font(.system(size: 11))
        .foregroundColor(.secondary)
    }
  }

  private var newWorkspaceButton: some View {
    Button("New workspace") {
      openFolderPickerForWorkspace()
    }
    .buttonStyle(.borderedProminent)
    .controlSize(.regular)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var emptyState: some View {
    VStack(spacing: 12) {
      Spacer()

      Image(systemName: "square.grid.2x2")
        .font(.system(size: 30))
        .foregroundColor(.secondary)

      Text("No workspaces yet")
        .font(.headline)

      Text("Open a folder to create your first workspace.")
        .font(.system(size: 12))
        .foregroundColor(.secondary)
        .multilineTextAlignment(.center)

      Button("Open Folder") {
        openFolderPickerForWorkspace()
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.regular)

      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func openFolderPickerForWorkspace() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true
    panel.message = "Select a folder for the new workspace"
    panel.prompt = "Create Workspace"

    panel.begin { response in
      guard response == .OK, let url = panel.url else {
        return
      }

      appState.createWorkspace(from: url)
    }
  }

  private func closeWorkspace(_ id: UUID) {
    let result = appState.closeWorkspace(id: id)

    switch result {
    case .closed:
      closeError = nil

    case .hasOpenTabs:
      closeError = "Close all tabs in the workspace before removing it."

    case .notFound:
      closeError = "Workspace not found."
    }
  }
}

// MARK: - Workspace Row

/// Row representing a workspace in the sidebar.
private struct WorkspaceRowView: View {
  let workspace: Workspace
  let isActive: Bool
  let tabCount: Int
  let isDragging: Bool
  let onSelect: () -> Void
  let onClose: () -> Void

  private var displayPath: String {
    let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
    let fullPath = workspace.rootDirectory.path

    if fullPath.hasPrefix(homeDir) {
      return "~" + fullPath.dropFirst(homeDir.count)
    }

    return fullPath
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .top, spacing: 8) {
        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: 6) {
            Text(workspace.name)
              .font(.system(size: 13, weight: .semibold))
              .lineLimit(1)

            if isActive {
              Text("Active")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.accentColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(Capsule())
            }
          }

          Text(displayPath)
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .lineLimit(2)
            .truncationMode(.middle)
        }

        Spacer()

        CloseButton {
          onClose()
        }
        .help(tabCount == 0 ? "Remove workspace" : "Close tabs before removing workspace")
      }

      HStack(spacing: 8) {
        Label("\(tabCount) tab\(tabCount == 1 ? "" : "s")", systemImage: "rectangle.on.rectangle")
          .font(.system(size: 11))
          .foregroundColor(.secondary)

        Spacer()

        Button(isActive ? "Selected" : "Select") {
          onSelect()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(isActive)
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(isActive ? Color.accentColor.opacity(0.08) : appCardColor)
    .overlay {
      RoundedRectangle(cornerRadius: 10)
        .stroke(isActive ? Color.accentColor.opacity(0.2) : Color.clear, lineWidth: 1)
    }
    .cornerRadius(10)
    .contentShape(Rectangle())
    .opacity(isDragging ? 0.5 : 1.0)
    .onTapGesture {
      onSelect()
    }
  }
}

// MARK: - Drag & Drop

/// Drop delegate that reorders workspaces when one is dragged over another.
/// Uses a cooldown flag to prevent double-swaps caused by views animating
/// through the cursor after a swap triggers a re-render.
private struct WorkspaceReorderDropDelegate: DropDelegate {
  let targetWorkspaceID: UUID
  let appState: AppState
  @Binding var draggedWorkspaceID: UUID?
  @Binding var swapCooldown: Bool

  func dropEntered(info: DropInfo) {
    guard let draggedWorkspaceID,
          draggedWorkspaceID != targetWorkspaceID,
          !swapCooldown
    else {
      return
    }

    swapCooldown = true

    withAnimation(.easeInOut(duration: 0.2)) {
      appState.swapWorkspaces(draggedWorkspaceID, targetWorkspaceID)
    }

    /// Allow the next swap after the animation settles.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
      swapCooldown = false
    }
  }

  func dropUpdated(info: DropInfo) -> DropProposal? {
    DropProposal(operation: .move)
  }

  func performDrop(info: DropInfo) -> Bool {
    draggedWorkspaceID = nil
    swapCooldown = false
    return true
  }

  func dropExited(info: DropInfo) {}
}
