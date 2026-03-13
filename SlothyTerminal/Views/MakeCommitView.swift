import SwiftUI

private struct MakeCommitSelection: Hashable, Identifiable {
  let path: String
  let section: GitChangeSection

  var id: String {
    "\(section.rawValue):\(path)"
  }
}

private struct MakeCommitConfirmation: Identifiable {
  let id = UUID()
  let title: String
  let message: String
}

/// Shell for the Git Make Commit tab.
struct MakeCommitView: View {
  let workingDirectory: URL

  @State private var snapshot = GitWorkingTreeSnapshot(changes: [])
  @State private var selectedChange: MakeCommitSelection?
  @State private var diffDocument = GitDiffDocument()
  @State private var branchName = "Loading..."
  @State private var repositoryName: String
  @State private var commitMessage = ""
  @State private var newBranchName = ""
  @State private var lastOperation: String?
  @State private var isLoadingSnapshot = false
  @State private var isLoadingDiff = false
  @State private var isRunningMutation = false
  @State private var pendingConfirmation: MakeCommitConfirmation?

  init(workingDirectory: URL) {
    self.workingDirectory = workingDirectory
    _repositoryName = State(initialValue: workingDirectory.lastPathComponent)
  }

  var body: some View {
    VStack(spacing: 0) {
      headerBar
      Divider()
      mainContent
      Divider()
      composerFooter
    }
    .background(appBackgroundColor)
    .task(id: workingDirectory) {
      await loadInitialState()
    }
    .task(id: selectedChange) {
      await loadSelectedDiff()
    }
    .confirmationDialog(
      pendingConfirmation?.title ?? "",
      isPresented: Binding(
        get: { pendingConfirmation != nil },
        set: { isPresented in
          if !isPresented {
            pendingConfirmation = nil
          }
        }
      )
    ) {
      Button("Dismiss", role: .cancel) {
        pendingConfirmation = nil
      }
    } message: {
      if let pendingConfirmation {
        Text(pendingConfirmation.message)
      }
    }
  }

  private var headerBar: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(repositoryName)
          .font(.system(size: 14, weight: .semibold))

        if let scopePath = snapshot.scopePath {
          Text(scopePath)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
        }
      }

      Text(branchName)
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.accentColor.opacity(0.12))
        .clipShape(.rect(cornerRadius: 6))

      if let lastOperation {
        Text(lastOperation)
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      Spacer()

      Button {
        Task {
          await refreshSnapshot(
            statusMessage: "Working tree loaded."
          )
        }
      } label: {
        Label("Refresh", systemImage: "arrow.clockwise")
      }
      .disabled(isLoadingSnapshot || isRunningMutation)

      Button {
        pendingConfirmation = MakeCommitConfirmation(
          title: "New Branch",
          message: "Branch creation UI will be wired in the next step."
        )
      } label: {
        Label("New Branch", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
      }
      .disabled(isLoadingSnapshot || isRunningMutation)

      Button {
        pendingConfirmation = MakeCommitConfirmation(
          title: "Push",
          message: "Push behavior will be wired in the next step."
        )
      } label: {
        Label("Push", systemImage: "arrow.up.circle")
      }
      .disabled(isLoadingSnapshot || isRunningMutation)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
  }

  private var mainContent: some View {
    HStack(spacing: 16) {
      changeListColumn
      .frame(minWidth: 280, maxWidth: 320, maxHeight: .infinity, alignment: .top)

      diffPanel
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .padding(16)
  }

  private var changeListColumn: some View {
    VStack(spacing: 12) {
      changeSection(
        title: "Staged",
        section: .staged,
        changes: snapshot.stagedChanges,
        iconName: "tray.full"
      )

      changeSection(
        title: "Unstaged",
        section: .unstaged,
        changes: snapshot.unstagedChanges,
        iconName: "tray"
      )
    }
  }

  private func changeSection(
    title: String,
    section: GitChangeSection,
    changes: [GitScopedChange],
    iconName: String
  ) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Label(title, systemImage: iconName)
          .font(.system(size: 12, weight: .semibold))

        Spacer()

        Text("\(changes.count)")
          .font(.system(size: 11, weight: .medium, design: .monospaced))
          .foregroundStyle(.secondary)
      }

      Divider()

      if isLoadingSnapshot {
        ProgressView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if changes.isEmpty {
        emptySectionState(section: section)
      } else {
        ScrollView {
          LazyVStack(spacing: 8) {
            ForEach(changes) { change in
              changeRow(
                for: change,
                section: section
              )
            }
          }
          .padding(.vertical, 2)
        }
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(appCardColor)
    .clipShape(.rect(cornerRadius: 10))
  }

  private func emptySectionState(section: GitChangeSection) -> some View {
    VStack(spacing: 8) {
      Image(systemName: "checkmark.circle")
        .font(.system(size: 24))
        .foregroundStyle(.green.opacity(0.7))

      Text("No \(section.rawValue) changes in scope")
        .font(.system(size: 12, weight: .medium))
        .multilineTextAlignment(.center)

      Text("This section updates after staging and unstaging actions.")
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func changeRow(
    for change: GitScopedChange,
    section: GitChangeSection
  ) -> some View {
    let isSelected = selectedChange == MakeCommitSelection(
      path: change.repoRelativePath,
      section: section
    )

    return HStack(spacing: 10) {
      Button {
        select(
          change: change,
          section: section
        )
      } label: {
        HStack(spacing: 10) {
          Text(change.status(in: section).badge)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(statusColor(change.status(in: section)))
            .frame(width: 14)

          VStack(alignment: .leading, spacing: 2) {
            Text(change.filename)
              .font(.system(size: 12, weight: .medium))
              .lineLimit(1)
              .truncationMode(.middle)

            if let secondaryDisplayPath = change.secondaryDisplayPath {
              Text(secondaryDisplayPath)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            }
          }

          Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
          isSelected
            ? Color.accentColor.opacity(0.12)
            : Color.primary.opacity(0.04)
        )
        .clipShape(.rect(cornerRadius: 8))
      }
      .buttonStyle(.plain)

      Button(section == .staged ? "Unstage" : "Stage") {
        Task {
          await toggleStage(
            for: change,
            section: section
          )
        }
      }
      .buttonStyle(.bordered)
      .controlSize(.small)
      .disabled(isLoadingSnapshot || isRunningMutation)
    }
  }

  private var diffPanel: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Label("Diff Preview", systemImage: "rectangle.split.2x1")
          .font(.system(size: 13, weight: .semibold))

        Spacer()

        if let selectedChange {
          Text(selectedChange.section == .staged ? "Staged" : "Unstaged")
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.06))
            .clipShape(.rect(cornerRadius: 6))
        }
      }

      Divider()

      if isLoadingDiff {
        ProgressView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if selectedChange == nil {
        diffEmptyState(
          iconName: "rectangle.split.2x1",
          message: "Select a staged or unstaged entry to inspect its diff."
        )
      } else if diffDocument.isBinary {
        diffEmptyState(
          iconName: "doc.richtext",
          message: "Binary changes cannot be rendered as text in this preview."
        )
      } else if diffDocument.isEmpty {
        diffEmptyState(
          iconName: "text.alignleft",
          message: "No textual diff is available for the selected change."
        )
      } else {
        ScrollView([.vertical, .horizontal]) {
          LazyVStack(spacing: 0) {
            ForEach(diffDocument.rows) { row in
              diffRow(row)
            }
          }
        }
      }
    }
    .padding(14)
    .background(appCardColor)
    .clipShape(.rect(cornerRadius: 10))
  }

  private func diffEmptyState(
    iconName: String,
    message: String
  ) -> some View {
    VStack(spacing: 12) {
      Image(systemName: iconName)
        .font(.system(size: 28))
        .foregroundStyle(.secondary.opacity(0.7))

      Text(message)
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 360)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func diffRow(_ row: GitDiffRow) -> some View {
    HStack(spacing: 0) {
      diffCell(
        lineNumber: row.oldLineNumber,
        text: row.leftText,
        backgroundColor: leftBackgroundColor(for: row.kind)
      )

      Divider()

      diffCell(
        lineNumber: row.newLineNumber,
        text: row.rightText,
        backgroundColor: rightBackgroundColor(for: row.kind)
      )
    }
  }

  private func diffCell(
    lineNumber: Int?,
    text: String,
    backgroundColor: Color
  ) -> some View {
    HStack(alignment: .top, spacing: 8) {
      Text(lineNumber.map(String.init) ?? "")
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(.secondary)
        .frame(width: 36, alignment: .trailing)

      Text(verbatim: text.isEmpty ? " " : text)
        .font(.system(size: 11, design: .monospaced))
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(backgroundColor)
  }

  private var composerFooter: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("Commit Message")
          .font(.system(size: 12, weight: .semibold))

        Spacer()

        TextField("New branch name", text: $newBranchName)
          .textFieldStyle(.roundedBorder)
          .frame(width: 220)
          .disabled(isLoadingSnapshot || isRunningMutation)
      }

      TextEditor(text: $commitMessage)
        .font(.system(size: 12))
        .frame(minHeight: 84)
        .scrollContentBackground(.hidden)
        .padding(6)
        .background(appCardColor)
        .clipShape(.rect(cornerRadius: 10))

      HStack {
        Text("Commit and amend actions will be wired in the next task.")
          .font(.system(size: 11))
          .foregroundStyle(.secondary)

        Spacer()

        Button("Commit") {}
          .disabled(true)
      }
    }
    .padding(16)
  }

  @MainActor
  private func loadInitialState() async {
    selectedChange = nil
    diffDocument = GitDiffDocument()
    await refreshSnapshot(
      statusMessage: "Working tree loaded."
    )
  }

  @MainActor
  private func refreshSnapshot(
    preferredPath: String? = nil,
    preferredSection: GitChangeSection? = nil,
    statusMessage: String? = nil
  ) async {
    isLoadingSnapshot = true

    defer {
      isLoadingSnapshot = false
    }

    guard let repositoryRoot = await GitService.shared.getRepositoryRoot(for: workingDirectory) else {
      snapshot = GitWorkingTreeSnapshot(changes: [])
      branchName = "Unavailable"
      lastOperation = "Failed to locate the repository root."
      return
    }

    repositoryName = repositoryRoot.lastPathComponent
    branchName = await GitService.shared.getCurrentBranch(in: repositoryRoot) ?? "Detached HEAD"

    let refreshedSnapshot = await GitWorkingTreeService.shared.loadSnapshot(
      in: workingDirectory
    )
    snapshot = refreshedSnapshot
    updateSelection(
      with: refreshedSnapshot,
      preferredPath: preferredPath,
      preferredSection: preferredSection
    )

    if let statusMessage {
      lastOperation = statusMessage
    }
  }

  @MainActor
  private func loadSelectedDiff() async {
    guard let selectedChange else {
      isLoadingDiff = false
      diffDocument = GitDiffDocument()
      return
    }

    isLoadingDiff = true
    let selection = selectedChange
    let loadedDiff = await GitWorkingTreeService.shared.loadDiff(
      for: selection.section,
      path: selection.path,
      in: workingDirectory
    )
    guard selection == self.selectedChange else {
      isLoadingDiff = false
      return
    }

    diffDocument = loadedDiff
    isLoadingDiff = false
  }

  private func select(
    change: GitScopedChange,
    section: GitChangeSection
  ) {
    selectedChange = MakeCommitSelection(
      path: change.repoRelativePath,
      section: section
    )
  }

  @MainActor
  private func toggleStage(
    for change: GitScopedChange,
    section: GitChangeSection
  ) async {
    isRunningMutation = true

    defer {
      isRunningMutation = false
    }

    let result: GitProcessResult
    switch section {
    case .staged:
      result = await GitWorkingTreeService.shared.unstageFile(
        path: change.repoRelativePath,
        in: workingDirectory
      )

    case .unstaged:
      result = await GitWorkingTreeService.shared.stageFile(
        path: change.repoRelativePath,
        in: workingDirectory
      )
    }

    guard result.isSuccess else {
      lastOperation = result.stderr.isEmpty ? "Git command failed." : result.stderr
      return
    }

    await refreshSnapshot(
      preferredPath: change.repoRelativePath,
      preferredSection: section,
      statusMessage: section == .staged
        ? "Unstaged \(change.displayPath)."
        : "Staged \(change.displayPath)."
    )
  }

  private func updateSelection(
    with snapshot: GitWorkingTreeSnapshot,
    preferredPath: String?,
    preferredSection: GitChangeSection?
  ) {
    if let preferredPath, let preferredSection {
      let preferredSelection = MakeCommitSelection(
        path: preferredPath,
        section: preferredSection
      )
      selectedChange = resolvedSelection(
        from: preferredSelection,
        in: snapshot
      )
      return
    }

    selectedChange = resolvedSelection(
      from: selectedChange,
      in: snapshot
    )
  }

  private func resolvedSelection(
    from selection: MakeCommitSelection?,
    in snapshot: GitWorkingTreeSnapshot
  ) -> MakeCommitSelection? {
    guard let selection else {
      return nil
    }

    if containsChange(
      path: selection.path,
      section: selection.section,
      in: snapshot
    ) {
      return selection
    }

    let alternateSection: GitChangeSection = selection.section == .staged ? .unstaged : .staged
    if containsChange(
      path: selection.path,
      section: alternateSection,
      in: snapshot
    ) {
      return MakeCommitSelection(
        path: selection.path,
        section: alternateSection
      )
    }

    return nil
  }

  private func containsChange(
    path: String,
    section: GitChangeSection,
    in snapshot: GitWorkingTreeSnapshot
  ) -> Bool {
    snapshot.changes.contains {
      $0.repoRelativePath == path && $0.hasEntry(in: section)
    }
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

  private func leftBackgroundColor(for kind: GitDiffRowKind) -> Color {
    switch kind {
    case .context:
      return .clear

    case .deletion, .modification:
      return .red.opacity(0.08)

    case .addition:
      return .clear
    }
  }

  private func rightBackgroundColor(for kind: GitDiffRowKind) -> Color {
    switch kind {
    case .context:
      return .clear

    case .addition, .modification:
      return .green.opacity(0.08)

    case .deletion:
      return .clear
    }
  }
}
