import SwiftUI

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
  @State private var isAmendingLastCommit = false
  @State private var activeAmendLoadRequestID: String?
  @State private var lastOperation: String?
  @State private var isLoadingSnapshot = false
  @State private var isLoadingDiff = false
  @State private var isLoadingAmendMessage = false
  @State private var isRunningMutation = false
  @State private var isShowingNewBranchSheet = false
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
      .disabled(isBusy)

      Button {
        isShowingNewBranchSheet = true
      } label: {
        Label("New Branch", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
      }
      .disabled(isBusy)

      Button {
        Task {
          await pushCurrentBranch()
        }
      } label: {
        Label("Push", systemImage: "arrow.up.circle")
      }
      .disabled(isBusy)
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
      .disabled(isBusy)
    }
    .contextMenu {
      switch section {
      case .staged:
        Button("Discard All Changes…", role: .destructive) {
          pendingConfirmation = MakeCommitConfirmation(
            action: .discardStaged,
            change: change
          )
        }

      case .unstaged:
        if change.isUntracked {
          Button("Delete File…", role: .destructive) {
            pendingConfirmation = MakeCommitConfirmation(
              action: .deleteUntracked,
              change: change
            )
          }
        } else {
          Button("Discard Changes…", role: .destructive) {
            pendingConfirmation = MakeCommitConfirmation(
              action: .discardTracked,
              change: change
            )
          }
        }
      }
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
      }

      if snapshot.hasStagedChangesOutsideScope {
        Label(
          "Commit is blocked because staged changes exist outside this scoped directory.",
          systemImage: "exclamationmark.triangle.fill"
        )
        .font(.system(size: 11))
        .foregroundStyle(.orange)
      }

      TextField(
        "Summarize the staged changes",
        text: Binding(
          get: { commitMessage },
          set: { commitMessage = MakeCommitComposerState.singleLineMessageInput($0) }
        )
      )
        .textFieldStyle(.plain)
        .font(.system(size: 12))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(appCardColor)
        .clipShape(.rect(cornerRadius: 10))
        .disabled(isBusy)

      HStack {
        Toggle("Amend last commit", isOn: $isAmendingLastCommit)
          .font(.system(size: 11))
          .disabled(isBusy)

        Spacer()

        Button(isAmendingLastCommit ? "Amend Commit" : "Commit") {
          Task {
            await commitChanges()
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(!canSubmitCommit)
      }
    }
    .padding(16)
  }

  private var isBusy: Bool {
    isLoadingSnapshot || isLoadingAmendMessage || isRunningMutation
  }

  private var canSubmitCommit: Bool {
    snapshot.canCommit(message: commitMessage) && !isBusy
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

    commitMessage = MakeCommitComposerState.normalizedCommitMessage(message)
    lastOperation = "Loaded the last commit message."
  }

  @MainActor
  private func commitChanges() async {
    let normalizedMessage = MakeCommitComposerState.normalizedCommitMessage(commitMessage)

    guard snapshot.canCommit(message: normalizedMessage), !isBusy else {
      return
    }

    isRunningMutation = true

    defer {
      isRunningMutation = false
    }

    let wasAmending = isAmendingLastCommit
    let result = await GitWorkingTreeService.shared.commit(
      message: normalizedMessage,
      amend: wasAmending,
      in: workingDirectory
    )

    guard result.isSuccess else {
      lastOperation = result.stderr.isEmpty ? "Git command failed." : result.stderr
      return
    }

    if !wasAmending {
      commitMessage = ""
    } else {
      commitMessage = normalizedMessage
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

    await refreshSnapshot(
      statusMessage: "Pushed the current branch."
    )
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
