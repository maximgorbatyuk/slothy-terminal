import SwiftUI

// MARK: - Tree Node

/// A node in the hierarchical file tree displayed in the sidebar.
private struct MakeCommitTreeNode: Identifiable {
  let id: String
  let name: String
  let isFolder: Bool
  let depth: Int
  let status: GitStatusColumn?
  let change: GitScopedChange?
  let children: [MakeCommitTreeNode]
}

// MARK: - MakeCommitSidebarView

/// Sidebar with staged and unstaged file sections for the Make Commit view.
struct MakeCommitSidebarView: View {
  let snapshot: GitWorkingTreeSnapshot
  @Binding var selectedChange: MakeCommitSelection?
  @Binding var collapsedFolders: Set<String>
  @Binding var pendingConfirmation: MakeCommitConfirmation?
  let isBusy: Bool
  let isLoadingSnapshot: Bool
  let onStageSelected: () -> Void
  let onUnstageSelected: () -> Void
  let onToggleStage: (GitScopedChange, GitChangeSection) -> Void

  var body: some View {
    VStack(spacing: 0) {
      sidebarSection(
        title: "Unstaged",
        actionLabel: "Stage",
        changes: snapshot.unstagedChanges,
        section: .unstaged
      ) {
        onStageSelected()
      }

      Divider()

      sidebarSection(
        title: "Staged",
        actionLabel: "Unstage",
        changes: snapshot.stagedChanges,
        section: .staged
      ) {
        onUnstageSelected()
      }
    }
    .background(appCardColor)
  }

  // MARK: - Section

  private func sidebarSection(
    title: String,
    actionLabel: String,
    changes: [GitScopedChange],
    section: GitChangeSection,
    headerAction: @escaping () -> Void
  ) -> some View {
    VStack(spacing: 0) {
      HStack {
        Text(title)
          .font(.system(size: 11, weight: .semibold))

        Spacer()

        Button(actionLabel) {
          headerAction()
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .disabled(isBusy || !hasSelectedChangeIn(section))
      }
      .padding(.horizontal, 12)
      .frame(height: 44)
      .background(makeCommitSectionHeaderColor)

      if isLoadingSnapshot {
        ProgressView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if changes.isEmpty {
        Spacer()
      } else {
        let tree = Self.buildTree(from: changes, section: section)
        let flat = flattenedTree(from: tree)

        ScrollView {
          VStack(spacing: 0) {
            ForEach(flat) { node in
              if node.isFolder {
                folderRow(node)
              } else {
                fileRow(node, section: section)
              }
            }
          }
          .padding(.vertical, 2)
        }
      }
    }
    .frame(maxHeight: .infinity)
  }

  // MARK: - Rows

  private func folderRow(_ node: MakeCommitTreeNode) -> some View {
    Button {
      if collapsedFolders.contains(node.id) {
        collapsedFolders.remove(node.id)
      } else {
        collapsedFolders.insert(node.id)
      }
    } label: {
      HStack(spacing: 4) {
        Image(
          systemName: collapsedFolders.contains(node.id)
            ? "chevron.right"
            : "chevron.down"
        )
        .font(.system(size: 8, weight: .semibold))
        .foregroundStyle(.secondary)
        .frame(width: 10)

        Image(systemName: "folder.fill")
          .font(.system(size: 11))
          .foregroundStyle(.blue)

        Text(node.name)
          .font(.system(size: 12))
          .lineLimit(1)

        Spacer()
      }
      .padding(.leading, CGFloat(node.depth) * 16 + 8)
      .padding(.trailing, 8)
      .frame(height: 30)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private func fileRow(
    _ node: MakeCommitTreeNode,
    section: GitChangeSection
  ) -> some View {
    let isSelected: Bool = {
      guard let change = node.change else {
        return false
      }

      return selectedChange == MakeCommitSelection(
        path: change.repoRelativePath,
        section: section
      )
    }()

    return Button {
      if let change = node.change {
        select(change: change, section: section)
      }
    } label: {
      HStack(spacing: 4) {
        Image(systemName: "doc.text")
          .font(.system(size: 11))
          .foregroundStyle(isSelected ? .white : .secondary)

        Text(node.name)
          .font(.system(size: 12))
          .foregroundStyle(isSelected ? .white : .primary)
          .lineLimit(1)

        Spacer(minLength: 4)

        if let status = node.status {
          Text(status.badge)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(
              isSelected ? .white.opacity(0.8) : statusColor(status)
            )
        }
      }
      .padding(.leading, CGFloat(node.depth) * 16 + 8)
      .padding(.trailing, 8)
      .frame(height: 30)
      .background {
        if isSelected {
          RoundedRectangle(cornerRadius: 5)
            .fill(Color.accentColor)
            .padding(.horizontal, 4)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .contextMenu {
      if let change = node.change {
        fileContextMenu(for: change, section: section)
      }
    }
  }

  @ViewBuilder
  private func fileContextMenu(
    for change: GitScopedChange,
    section: GitChangeSection
  ) -> some View {
    switch section {
    case .staged:
      Button("Unstage") {
        onToggleStage(change, section)
      }

      Button("Discard All Changes\u{2026}", role: .destructive) {
        pendingConfirmation = MakeCommitConfirmation(
          action: .discardStaged,
          change: change
        )
      }

    case .unstaged:
      Button("Stage") {
        onToggleStage(change, section)
      }

      Divider()

      if change.isUntracked {
        Button("Delete File\u{2026}", role: .destructive) {
          pendingConfirmation = MakeCommitConfirmation(
            action: .deleteUntracked,
            change: change
          )
        }
      } else {
        Button("Discard Changes\u{2026}", role: .destructive) {
          pendingConfirmation = MakeCommitConfirmation(
            action: .discardTracked,
            change: change
          )
        }
      }
    }
  }

  // MARK: - Helpers

  private func select(
    change: GitScopedChange,
    section: GitChangeSection
  ) {
    selectedChange = MakeCommitSelection(
      path: change.repoRelativePath,
      section: section
    )
  }

  private func hasSelectedChangeIn(_ section: GitChangeSection) -> Bool {
    guard let selectedChange else {
      return false
    }

    return selectedChange.section == section
  }

  private func statusColor(_ status: GitStatusColumn) -> Color {
    switch status {
    case .modified:
      return .orange

    case .added, .copied:
      return .green

    case .deleted:
      return .red

    case .renamed:
      return .blue

    case .untracked:
      return .secondary

    case .unmerged:
      return .pink

    case .ignored, .unmodified:
      return .secondary
    }
  }

  // MARK: - Tree Builder

  private static func buildTree(
    from changes: [GitScopedChange],
    section: GitChangeSection
  ) -> [MakeCommitTreeNode] {
    let entries = changes.map { change in
      (
        components: change.repoRelativePath.split(separator: "/").map(String.init),
        change: change
      )
    }

    return buildSubtree(
      from: entries,
      section: section,
      depth: 0,
      pathPrefix: ""
    )
  }

  private static func buildSubtree(
    from entries: [(components: [String], change: GitScopedChange)],
    section: GitChangeSection,
    depth: Int,
    pathPrefix: String
  ) -> [MakeCommitTreeNode] {
    var files: [MakeCommitTreeNode] = []
    var folderOrder: [String] = []
    var folderMap: [String: [(components: [String], change: GitScopedChange)]] = [:]

    for entry in entries {
      if depth == entry.components.count - 1 {
        let name = entry.components[depth]
        files.append(MakeCommitTreeNode(
          id: "\(section.rawValue):\(entry.change.repoRelativePath)",
          name: name,
          isFolder: false,
          depth: depth,
          status: entry.change.status(in: section),
          change: entry.change,
          children: []
        ))
      } else {
        let folderName = entry.components[depth]

        if folderMap[folderName] == nil {
          folderOrder.append(folderName)
        }

        folderMap[folderName, default: []].append(entry)
      }
    }

    var result: [MakeCommitTreeNode] = []

    for folderName in folderOrder.sorted() {
      guard let children = folderMap[folderName] else {
        continue
      }

      let folderPath = pathPrefix.isEmpty ? folderName : "\(pathPrefix)/\(folderName)"
      let childNodes = buildSubtree(
        from: children,
        section: section,
        depth: depth + 1,
        pathPrefix: folderPath
      )

      result.append(MakeCommitTreeNode(
        id: "\(section.rawValue):folder:\(folderPath)",
        name: folderName,
        isFolder: true,
        depth: depth,
        status: nil,
        change: nil,
        children: childNodes
      ))
    }

    result.append(contentsOf: files.sorted(by: { $0.name < $1.name }))
    return result
  }

  private func flattenedTree(from nodes: [MakeCommitTreeNode]) -> [MakeCommitTreeNode] {
    var result: [MakeCommitTreeNode] = []

    for node in nodes {
      result.append(node)

      if node.isFolder, !collapsedFolders.contains(node.id) {
        result.append(contentsOf: flattenedTree(from: node.children))
      }
    }

    return result
  }
}
