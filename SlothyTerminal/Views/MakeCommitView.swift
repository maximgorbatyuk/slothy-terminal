import SwiftUI

// MARK: - File Tree Node

/// A node in the hierarchical file tree displayed in the sidebar.
private struct FileTreeNode: Identifiable {
  let id: String
  let name: String
  let isFolder: Bool
  let depth: Int
  let status: GitStatusColumn?
  let change: GitScopedChange?
  let children: [FileTreeNode]
}

// MARK: - Supporting Types

private struct MakeCommitSelection: Hashable, Identifiable {
  let path: String
  let section: GitChangeSection

  var id: String {
    "\(section.rawValue):\(path)"
  }
}

private struct MakeCommitConfirmation: Identifiable {
  enum ActionKind {
    case discardTracked
    case discardStaged
    case deleteUntracked
  }

  let id = UUID()
  let action: ActionKind
  let change: GitScopedChange

  var title: String {
    switch action {
    case .discardTracked:
      return "Discard Changes"

    case .discardStaged:
      return "Discard All Changes"

    case .deleteUntracked:
      return "Delete File"
    }
  }

  var message: String {
    switch action {
    case .discardTracked:
      return "Discard unstaged changes for \(change.displayPath)?"

    case .discardStaged:
      return "Discard staged and working tree changes for \(change.displayPath) and reset it to HEAD?"

    case .deleteUntracked:
      return "Delete the untracked file \(change.displayPath) from disk?"
    }
  }

  var confirmTitle: String {
    switch action {
    case .discardTracked:
      return "Discard Changes"

    case .discardStaged:
      return "Discard All Changes"

    case .deleteUntracked:
      return "Delete File"
    }
  }
}

// MARK: - New Branch Sheet

private struct NewBranchSheet: View {
  @Binding var branchName: String
  let isSubmitting: Bool
  let onCreate: () async -> Bool

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Create and Switch Branch")
        .font(.system(size: 16, weight: .semibold))

      TextField("Branch name", text: $branchName)
        .textFieldStyle(.roundedBorder)

      HStack {
        Spacer()

        Button("Cancel") {
          dismiss()
        }

        Button("Create Branch") {
          Task {
            let didCreate = await onCreate()

            if didCreate {
              dismiss()
            }
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(
          isSubmitting ||
            !GitWorkingTreeService.shared.isValidBranchName(branchName)
        )
      }
    }
    .padding(20)
    .frame(width: 360)
  }
}

// MARK: - MakeCommitView

/// Git commit interface with sidebar file tree, side-by-side diff, and commit composer.
struct MakeCommitView: View {
  let workingDirectory: URL

  @State private var snapshot = GitWorkingTreeSnapshot(changes: [])
  @State private var selectedChange: MakeCommitSelection?
  @State private var diffDocument = GitDiffDocument()
  @State private var branchName = "Loading..."
  @State private var repositoryName: String
  @State private var commitMessage = ""
  @State private var commitDescription = ""
  @State private var newBranchName = ""
  @State private var isAmendingLastCommit = false
  @State private var activeAmendLoadRequestID: String?
  @State private var lastOperation: String?
  @State private var isLoadingSnapshot = false
  @State private var isLoadingDiff = false
  @State private var isLoadingAmendMessage = false
  @State private var isRunningMutation = false
  @State private var isShowingNewBranchSheet = false
  @State private var pendingConfirmation: MakeCommitConfirmation?
  @State private var collapsedFolders: Set<String> = []

  init(workingDirectory: URL) {
    self.workingDirectory = workingDirectory
    _repositoryName = State(initialValue: workingDirectory.lastPathComponent)
  }

  var body: some View {
    VStack(spacing: 0) {
      toolbar
      Divider()

      GeometryReader { geometry in
        HStack(spacing: 0) {
          sidebar
            .frame(width: geometry.size.width * 0.34)

          Divider()

          VStack(spacing: 0) {
            diffViewer

            Divider()

            commitComposer
              .frame(height: max(geometry.size.height * 0.22, 150))
          }
        }
      }
    }
    .background(appBackgroundColor)
    .task(id: workingDirectory) {
      await loadInitialState()
    }
    .task(id: selectedChange) {
      await loadSelectedDiff()
    }
    .onChange(of: isAmendingLastCommit) { _, isEnabled in
      guard isEnabled else {
        activeAmendLoadRequestID = nil
        return
      }

      let requestID = UUID().uuidString
      let initialMessage = commitMessage
      activeAmendLoadRequestID = requestID

      Task {
        await preloadLastCommitMessage(
          requestID: requestID,
          initialMessage: initialMessage
        )
      }
    }
    .sheet(isPresented: $isShowingNewBranchSheet) {
      NewBranchSheet(
        branchName: $newBranchName,
        isSubmitting: isBusy,
        onCreate: {
          await createBranch()
        }
      )
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
      if let pendingConfirmation {
        Button(pendingConfirmation.confirmTitle, role: .destructive) {
          let confirmation = pendingConfirmation
          self.pendingConfirmation = nil

          Task {
            await performConfirmation(confirmation)
          }
        }
      }

      Button("Cancel", role: .cancel) {
        pendingConfirmation = nil
      }
    } message: {
      if let pendingConfirmation {
        Text(pendingConfirmation.message)
      }
    }
  }

  // MARK: - Toolbar

  private var toolbar: some View {
    HStack(spacing: 10) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 12))
        .foregroundStyle(.secondary)

      Text(repositoryName)
        .font(.system(size: 12, weight: .medium))
        .lineLimit(1)

      Text(branchName)
        .font(.system(size: 10, weight: .medium, design: .monospaced))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.accentColor.opacity(0.12))
        .clipShape(.rect(cornerRadius: 4))

      Spacer()

      if let selectedChange {
        HStack(spacing: 4) {
          Image(systemName: "doc.text")
            .font(.system(size: 10))
            .foregroundStyle(.secondary)

          Text(selectedChange.path)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
        }
      }

      Spacer()

      if let lastOperation {
        Text(lastOperation)
          .font(.system(size: 10))
          .foregroundStyle(.tertiary)
          .lineLimit(1)
      }

      Button {
        Task {
          await refreshSnapshot(statusMessage: "Working tree loaded.")
        }
      } label: {
        Image(systemName: "arrow.clockwise")
          .font(.system(size: 11))
      }
      .buttonStyle(.plain)
      .foregroundStyle(.secondary)
      .disabled(isBusy)
      .help("Refresh")

      Button {
        isShowingNewBranchSheet = true
      } label: {
        Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
          .font(.system(size: 11))
      }
      .buttonStyle(.plain)
      .foregroundStyle(.secondary)
      .disabled(isBusy)
      .help("New Branch")

      Button {
        Task {
          await pushCurrentBranch()
        }
      } label: {
        Image(systemName: "arrow.up.circle")
          .font(.system(size: 11))
      }
      .buttonStyle(.plain)
      .foregroundStyle(.secondary)
      .disabled(isBusy)
      .help("Push")
    }
    .padding(.horizontal, 12)
    .frame(height: 40)
    .background(sectionHeaderColor)
  }

  // MARK: - Sidebar

  private var sidebar: some View {
    VStack(spacing: 0) {
      sidebarSection(
        title: "Unstaged",
        actionLabel: "Stage",
        changes: snapshot.unstagedChanges,
        section: .unstaged
      ) {
        Task {
          await stageSelected()
        }
      }

      Divider()

      sidebarSection(
        title: "Staged",
        actionLabel: "Unstage",
        changes: snapshot.stagedChanges,
        section: .staged
      ) {
        Task {
          await unstageSelected()
        }
      }
    }
    .background(appCardColor)
  }

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
      .background(sectionHeaderColor)

      if isLoadingSnapshot {
        ProgressView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if changes.isEmpty {
        Color.clear
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollView {
          LazyVStack(spacing: 0) {
            let tree = Self.buildTree(from: changes, section: section)
            let flat = flattenedTree(from: tree)

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

  private func folderRow(_ node: FileTreeNode) -> some View {
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
    _ node: FileTreeNode,
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
        Task {
          await toggleStage(for: change, section: section)
        }
      }

      Button("Discard All Changes\u{2026}", role: .destructive) {
        pendingConfirmation = MakeCommitConfirmation(
          action: .discardStaged,
          change: change
        )
      }

    case .unstaged:
      Button("Stage") {
        Task {
          await toggleStage(for: change, section: section)
        }
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

  // MARK: - Diff Viewer

  private var diffViewer: some View {
    VStack(spacing: 0) {
      if let selectedChange {
        HStack(spacing: 6) {
          Image(systemName: "doc.text")
            .font(.system(size: 10))
            .foregroundStyle(.secondary)

          Text(selectedChange.path)
            .font(.system(size: 11, weight: .medium))
            .lineLimit(1)
            .truncationMode(.middle)

          Spacer()

          Text(selectedChange.section == .staged ? "Staged" : "Unstaged")
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(sectionHeaderColor)

        Divider()
      }

      if isLoadingDiff {
        ProgressView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if selectedChange == nil {
        diffEmptyState(
          iconName: "rectangle.split.2x1",
          message: "Select a file to view its diff."
        )
      } else if diffDocument.isBinary {
        diffEmptyState(
          iconName: "doc.richtext",
          message: "Binary file — cannot display diff."
        )
      } else if diffDocument.isEmpty {
        diffEmptyState(
          iconName: "text.alignleft",
          message: "No textual diff available."
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
    .background(appBackgroundColor)
  }

  private func diffEmptyState(
    iconName: String,
    message: String
  ) -> some View {
    VStack(spacing: 8) {
      Image(systemName: iconName)
        .font(.system(size: 24))
        .foregroundStyle(.secondary.opacity(0.5))

      Text(message)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func diffRow(_ row: GitDiffRow) -> some View {
    HStack(spacing: 0) {
      diffCell(
        lineNumber: row.oldLineNumber,
        text: row.leftText,
        background: leftDiffColor(for: row.kind)
      )

      Rectangle()
        .fill(Color.primary.opacity(0.06))
        .frame(width: 1)

      diffCell(
        lineNumber: row.newLineNumber,
        text: row.rightText,
        background: rightDiffColor(for: row.kind)
      )
    }
  }

  private func diffCell(
    lineNumber: Int?,
    text: String,
    background: Color
  ) -> some View {
    HStack(alignment: .top, spacing: 0) {
      Text(lineNumber.map(String.init) ?? "")
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(.secondary.opacity(0.5))
        .frame(width: 40, alignment: .trailing)
        .padding(.trailing, 8)

      Rectangle()
        .fill(Color.primary.opacity(0.06))
        .frame(width: 1)

      Text(verbatim: text.isEmpty ? " " : text)
        .font(.system(size: 12, design: .monospaced))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 8)
        .textSelection(.enabled)
    }
    .padding(.vertical, 1)
    .background(background)
  }

  // MARK: - Commit Composer

  private var commitComposer: some View {
    VStack(spacing: 8) {
      if snapshot.hasStagedChangesOutsideScope {
        Label(
          "Commit blocked — staged changes exist outside this scoped directory.",
          systemImage: "exclamationmark.triangle.fill"
        )
        .font(.system(size: 10))
        .foregroundStyle(.orange)
      }

      VStack(spacing: 0) {
        HStack(spacing: 6) {
          Image(systemName: "plus")
            .font(.system(size: 10))
            .foregroundStyle(.secondary)

          TextField(
            "Summary",
            text: Binding(
              get: { commitMessage },
              set: { commitMessage = MakeCommitComposerState.singleLineMessageInput($0) }
            )
          )
          .textFieldStyle(.plain)
          .font(.system(size: 12))
          .disabled(isBusy)

          Text("\(commitMessage.count)")
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(commitMessage.count > 72 ? .orange : .secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)

        Divider()
          .padding(.horizontal, 8)

        ZStack(alignment: .topLeading) {
          if commitDescription.isEmpty {
            Text("Description")
              .font(.system(size: 12))
              .foregroundStyle(.secondary.opacity(0.5))
              .padding(.horizontal, 5)
              .padding(.vertical, 8)
              .allowsHitTesting(false)
          }

          TextEditor(text: $commitDescription)
            .font(.system(size: 12))
            .scrollContentBackground(.hidden)
            .frame(minHeight: 28)
            .disabled(isBusy)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
      }
      .background(appCardColor)
      .clipShape(.rect(cornerRadius: 6))
      .overlay(
        RoundedRectangle(cornerRadius: 6)
          .stroke(Color.primary.opacity(0.1), lineWidth: 1)
      )

      HStack {
        Toggle("Amend", isOn: $isAmendingLastCommit)
          .toggleStyle(.checkbox)
          .font(.system(size: 11))
          .disabled(isBusy)

        Spacer()

        Button(isAmendingLastCommit ? "Amend Last Commit" : "Commit") {
          Task {
            await commitChanges()
          }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .disabled(!canSubmitCommit)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(appBackgroundColor)
  }

  // MARK: - Computed Properties

  private var isBusy: Bool {
    isLoadingSnapshot || isLoadingAmendMessage || isRunningMutation
  }

  private var canSubmitCommit: Bool {
    snapshot.canCommit(message: commitMessage) && !isBusy
  }

  private var fullCommitMessage: String {
    let summary = MakeCommitComposerState.normalizedCommitMessage(commitMessage)
    let desc = commitDescription.trimmingCharacters(in: .whitespacesAndNewlines)

    if desc.isEmpty {
      return summary
    }

    return "\(summary)\n\n\(desc)"
  }

  // MARK: - Actions

  @MainActor
  private func loadInitialState() async {
    selectedChange = nil
    diffDocument = GitDiffDocument()
    await refreshSnapshot(statusMessage: "Working tree loaded.")
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

    guard let change = snapshot.changes.first(where: { $0.repoRelativePath == selection.path }) else {
      diffDocument = GitDiffDocument()
      isLoadingDiff = false
      return
    }

    let loadedDiff = await GitWorkingTreeService.shared.loadDiff(
      for: change,
      section: selection.section,
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
  private func stageSelected() async {
    guard let selectedChange,
          selectedChange.section == .unstaged,
          let change = snapshot.changes.first(where: {
            $0.repoRelativePath == selectedChange.path
          })
    else {
      return
    }

    await toggleStage(for: change, section: .unstaged)
  }

  @MainActor
  private func unstageSelected() async {
    guard let selectedChange,
          selectedChange.section == .staged,
          let change = snapshot.changes.first(where: {
            $0.repoRelativePath == selectedChange.path
          })
    else {
      return
    }

    await toggleStage(for: change, section: .staged)
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

  @MainActor
  private func preloadLastCommitMessage(
    requestID: String,
    initialMessage: String
  ) async {
    isLoadingAmendMessage = true

    defer {
      isLoadingAmendMessage = false
    }

    guard let message = await GitWorkingTreeService.shared.getLastCommitMessage(
      in: workingDirectory
    ) else {
      guard requestID == activeAmendLoadRequestID, isAmendingLastCommit else {
        return
      }

      activeAmendLoadRequestID = nil
      isAmendingLastCommit = false
      lastOperation = "Unable to load the last commit message."
      return
    }

    let shouldApplyMessage = MakeCommitComposerState.shouldApplyLoadedAmendMessage(
      requestID: requestID,
      activeRequestID: activeAmendLoadRequestID,
      isAmending: isAmendingLastCommit,
      initialMessage: initialMessage,
      currentMessage: commitMessage
    )

    if requestID == activeAmendLoadRequestID {
      activeAmendLoadRequestID = nil
    }

    guard shouldApplyMessage else {
      return
    }

    let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
    commitMessage = MakeCommitComposerState.normalizedCommitMessage(trimmed)

    if let newlineRange = trimmed.range(of: "\n") {
      commitDescription = String(trimmed[newlineRange.upperBound...])
        .trimmingCharacters(in: .whitespacesAndNewlines)
    } else {
      commitDescription = ""
    }

    lastOperation = "Loaded the last commit message."
  }

  @MainActor
  private func commitChanges() async {
    guard snapshot.canCommit(message: commitMessage), !isBusy else {
      return
    }

    isRunningMutation = true

    defer {
      isRunningMutation = false
    }

    let wasAmending = isAmendingLastCommit
    let message = fullCommitMessage
    let result = await GitWorkingTreeService.shared.commit(
      message: message,
      amend: wasAmending,
      in: workingDirectory
    )

    guard result.isSuccess else {
      lastOperation = result.stderr.isEmpty ? "Git command failed." : result.stderr
      return
    }

    if !wasAmending {
      commitMessage = ""
      commitDescription = ""
    }

    isAmendingLastCommit = false
    await refreshSnapshot(
      statusMessage: wasAmending
        ? "Amended the last commit."
        : "Created a new commit."
    )
  }

  @MainActor
  private func pushCurrentBranch() async {
    isRunningMutation = true

    defer {
      isRunningMutation = false
    }

    let result = await GitWorkingTreeService.shared.push(
      in: workingDirectory
    )

    guard result.isSuccess else {
      lastOperation = result.stderr.isEmpty ? "Git command failed." : result.stderr
      return
    }

    await refreshSnapshot(statusMessage: "Pushed the current branch.")
  }

  @MainActor
  private func createBranch() async -> Bool {
    guard GitWorkingTreeService.shared.isValidBranchName(newBranchName) else {
      lastOperation = "Branch name must not be blank."
      return false
    }

    isRunningMutation = true

    defer {
      isRunningMutation = false
    }

    let trimmedBranchName = newBranchName.trimmingCharacters(in: .whitespacesAndNewlines)
    let result = await GitWorkingTreeService.shared.createAndSwitchBranch(
      named: trimmedBranchName,
      in: workingDirectory
    )

    guard result.isSuccess else {
      lastOperation = result.stderr.isEmpty ? "Git command failed." : result.stderr
      return false
    }

    newBranchName = ""
    await refreshSnapshot(
      statusMessage: "Created and switched to \(trimmedBranchName)."
    )
    return true
  }

  @MainActor
  private func performConfirmation(_ confirmation: MakeCommitConfirmation) async {
    isRunningMutation = true

    defer {
      isRunningMutation = false
    }

    let result: GitProcessResult
    let preferredSection: GitChangeSection
    let successMessage: String

    switch confirmation.action {
    case .discardTracked:
      preferredSection = .unstaged
      successMessage = "Discarded changes for \(confirmation.change.displayPath)."
      result = await GitWorkingTreeService.shared.discardTrackedChanges(
        path: confirmation.change.repoRelativePath,
        in: workingDirectory
      )

    case .discardStaged:
      preferredSection = .staged
      successMessage = "Discarded all changes for \(confirmation.change.displayPath)."
      result = await GitWorkingTreeService.shared.discardStagedChanges(
        path: confirmation.change.repoRelativePath,
        in: workingDirectory
      )

    case .deleteUntracked:
      preferredSection = .unstaged
      successMessage = "Deleted \(confirmation.change.displayPath)."
      result = await GitWorkingTreeService.shared.deleteUntrackedFile(
        path: confirmation.change.repoRelativePath,
        in: workingDirectory
      )
    }

    guard result.isSuccess else {
      lastOperation = result.stderr.isEmpty ? "Git command failed." : result.stderr
      return
    }

    await refreshSnapshot(
      preferredPath: confirmation.change.repoRelativePath,
      preferredSection: preferredSection,
      statusMessage: successMessage
    )
  }

  // MARK: - Selection Helpers

  private func hasSelectedChangeIn(_ section: GitChangeSection) -> Bool {
    guard let selectedChange else {
      return false
    }

    return selectedChange.section == section
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

  // MARK: - Colors

  private var sectionHeaderColor: Color {
    Color(nsColor: NSColor(name: nil) { appearance in
      if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
        return NSColor(red: 45/255, green: 49/255, blue: 57/255, alpha: 1)
      } else {
        return NSColor(red: 238/255, green: 238/255, blue: 240/255, alpha: 1)
      }
    })
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

  private func leftDiffColor(for kind: GitDiffRowKind) -> Color {
    switch kind {
    case .context:
      return .clear

    case .deletion, .modification:
      return .red.opacity(0.08)

    case .addition:
      return .clear
    }
  }

  private func rightDiffColor(for kind: GitDiffRowKind) -> Color {
    switch kind {
    case .context:
      return .clear

    case .addition, .modification:
      return .green.opacity(0.08)

    case .deletion:
      return .clear
    }
  }

  // MARK: - Tree Builder

  private static func buildTree(
    from changes: [GitScopedChange],
    section: GitChangeSection
  ) -> [FileTreeNode] {
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
  ) -> [FileTreeNode] {
    var files: [FileTreeNode] = []
    var folderOrder: [String] = []
    var folderMap: [String: [(components: [String], change: GitScopedChange)]] = [:]

    for entry in entries {
      if depth == entry.components.count - 1 {
        let name = entry.components[depth]
        files.append(FileTreeNode(
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

    var result: [FileTreeNode] = []

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

      result.append(FileTreeNode(
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

  private func flattenedTree(from nodes: [FileTreeNode]) -> [FileTreeNode] {
    var result: [FileTreeNode] = []

    for node in nodes {
      result.append(node)

      if node.isFolder, !collapsedFolders.contains(node.id) {
        result.append(contentsOf: flattenedTree(from: node.children))
      }
    }

    return result
  }
}
