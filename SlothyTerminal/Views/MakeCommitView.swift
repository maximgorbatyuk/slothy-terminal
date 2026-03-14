import SwiftUI

// MARK: - Shared Color

/// Section header background for the Make Commit UI — adaptive for light/dark.
var makeCommitSectionHeaderColor: Color {
  Color(nsColor: NSColor(name: nil) { appearance in
    if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
      return NSColor(red: 45/255, green: 49/255, blue: 57/255, alpha: 1)
    } else {
      return NSColor(red: 238/255, green: 238/255, blue: 240/255, alpha: 1)
    }
  })
}

// MARK: - Supporting Types

struct MakeCommitSelection: Hashable, Identifiable {
  let path: String
  let section: GitChangeSection

  var id: String {
    "\(section.rawValue):\(path)"
  }
}

struct MakeCommitConfirmation: Identifiable {
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
  @State private var newBranchName = ""
  @State private var isAmendingLastCommit = false
  @State private var savedAmendHash: String?
  @State private var lastOperation: String?
  @State private var isLoadingSnapshot = false
  @State private var isLoadingDiff = false
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
          MakeCommitSidebarView(
            snapshot: snapshot,
            selectedChange: $selectedChange,
            collapsedFolders: $collapsedFolders,
            pendingConfirmation: $pendingConfirmation,
            isBusy: isBusy,
            isLoadingSnapshot: isLoadingSnapshot,
            onStageSelected: {
              Task { await stageSelected() }
            },
            onUnstageSelected: {
              Task { await unstageSelected() }
            },
            onToggleStage: { change, section in
              Task { await toggleStage(for: change, section: section) }
            }
          )
          .frame(width: geometry.size.width * 0.34)

          Divider()

          VStack(spacing: 0) {
            MakeCommitDiffContentView(
              selectedChange: selectedChange,
              diffDocument: diffDocument,
              isLoadingDiff: isLoadingDiff
            )

            Divider()

            MakeCommitComposerView(
              snapshot: snapshot,
              commitMessage: $commitMessage,
              isAmendingLastCommit: $isAmendingLastCommit,
              isBusy: isBusy,
              canSubmitCommit: canSubmitCommit,
              onCommit: {
                Task { await commitChanges() }
              }
            )
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
      Task {
        if isEnabled {
          await enterAmendMode()
        } else {
          await exitAmendMode()
        }
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
    .background(makeCommitSectionHeaderColor)
  }

  // MARK: - Computed Properties

  private var isBusy: Bool {
    isLoadingSnapshot || isRunningMutation
  }

  private var canSubmitCommit: Bool {
    snapshot.canCommit(message: commitMessage) && !isBusy
  }

  private var fullCommitMessage: String {
    MakeCommitComposerState.normalizedCommitMessage(commitMessage)
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
  private func enterAmendMode() async {
    guard !isRunningMutation else {
      return
    }

    isRunningMutation = true

    defer {
      isRunningMutation = false
    }

    guard let headHash = await GitWorkingTreeService.shared.getHeadHash(
      in: workingDirectory
    ) else {
      lastOperation = "Unable to read current HEAD."
      isAmendingLastCommit = false
      return
    }

    let message = await GitWorkingTreeService.shared.getLastCommitMessage(
      in: workingDirectory
    )

    let result = await GitWorkingTreeService.shared.softReset(
      to: "HEAD~1",
      in: workingDirectory
    )

    guard result.isSuccess else {
      lastOperation = result.stderr.isEmpty ? "Soft reset failed." : result.stderr
      isAmendingLastCommit = false
      return
    }

    savedAmendHash = headHash

    if let message {
      let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
      commitMessage = MakeCommitComposerState.normalizedCommitMessage(trimmed)
    }

    await refreshSnapshot(statusMessage: "Amend mode — last commit changes are now staged.")
  }

  @MainActor
  private func exitAmendMode() async {
    guard let savedHash = savedAmendHash else {
      return
    }

    guard !isRunningMutation else {
      return
    }

    isRunningMutation = true

    defer {
      isRunningMutation = false
    }

    let result = await GitWorkingTreeService.shared.softReset(
      to: savedHash,
      in: workingDirectory
    )
    savedAmendHash = nil

    guard result.isSuccess else {
      lastOperation = result.stderr.isEmpty ? "Restore failed." : result.stderr
      return
    }

    await refreshSnapshot(statusMessage: "Exited amend mode.")
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
      amend: false,
      in: workingDirectory
    )

    guard result.isSuccess else {
      lastOperation = result.stderr.isEmpty ? "Git command failed." : result.stderr
      return
    }

    /// Clear amend hash before toggling `isAmendingLastCommit` so that
    /// the onChange handler's `exitAmendMode` does not restore the old commit.
    savedAmendHash = nil

    if !wasAmending {
      commitMessage = ""
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
}
