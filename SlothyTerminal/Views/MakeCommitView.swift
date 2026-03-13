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
  @State private var branchName = "Loading..."
  @State private var repositoryName: String
  @State private var commitMessage = ""
  @State private var newBranchName = ""
  @State private var lastOperation: String?
  @State private var isLoading = false
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
          await loadInitialState()
        }
      } label: {
        Label("Refresh", systemImage: "arrow.clockwise")
      }
      .disabled(isLoading)

      Button {
        pendingConfirmation = MakeCommitConfirmation(
          title: "New Branch",
          message: "Branch creation UI will be wired in the next step."
        )
      } label: {
        Label("New Branch", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
      }
      .disabled(isLoading)

      Button {
        pendingConfirmation = MakeCommitConfirmation(
          title: "Push",
          message: "Push behavior will be wired in the next step."
        )
      } label: {
        Label("Push", systemImage: "arrow.up.circle")
      }
      .disabled(isLoading)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
  }

  private var mainContent: some View {
    HStack(spacing: 16) {
      VStack(spacing: 12) {
        statusCard(
          title: "Staged",
          count: stagedCount,
          iconName: "tray.full"
        )

        statusCard(
          title: "Unstaged",
          count: unstagedCount,
          iconName: "tray"
        )
      }
      .frame(minWidth: 280, maxWidth: 320, maxHeight: .infinity, alignment: .top)

      diffPlaceholder
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .padding(16)
  }

  private func statusCard(
    title: String,
    count: Int,
    iconName: String
  ) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Label(title, systemImage: iconName)
          .font(.system(size: 12, weight: .semibold))

        Spacer()

        Text("\(count)")
          .font(.system(size: 11, weight: .medium, design: .monospaced))
          .foregroundStyle(.secondary)
      }

      Divider()

      if isLoading {
        ProgressView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        VStack(spacing: 8) {
          Image(systemName: count == 0 ? "checkmark.circle" : "list.bullet.rectangle")
            .font(.system(size: 24))
            .foregroundStyle(count == 0 ? .green.opacity(0.7) : .secondary)

          Text(count == 0 ? "No changes in this section" : "Interactive file rows arrive in the next task")
            .font(.system(size: 12, weight: .medium))
            .multilineTextAlignment(.center)

          Text("The shell is already loading the scoped repository state.")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(appCardColor)
    .clipShape(.rect(cornerRadius: 10))
  }

  private var diffPlaceholder: some View {
    VStack(spacing: 12) {
      Image(systemName: "rectangle.split.2x1")
        .font(.system(size: 30))
        .foregroundStyle(.secondary.opacity(0.7))

      Text("Diff Preview")
        .font(.system(size: 14, weight: .semibold))

      Text(selectedChange == nil
        ? "Select a staged or unstaged entry to inspect its diff."
        : "Diff loading will be wired in the next task.")
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 340)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(appCardColor)
    .clipShape(.rect(cornerRadius: 10))
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
          .disabled(isLoading)
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

  private var stagedCount: Int {
    snapshot.changes.filter(\.hasStagedEntry).count
  }

  private var unstagedCount: Int {
    snapshot.changes.filter(\.hasUnstagedEntry).count
  }

  @MainActor
  private func loadInitialState() async {
    isLoading = true
    lastOperation = nil
    selectedChange = nil

    defer {
      isLoading = false
    }

    if let repositoryRoot = await GitService.shared.getRepositoryRoot(for: workingDirectory) {
      repositoryName = repositoryRoot.lastPathComponent
      branchName = await GitService.shared.getCurrentBranch(in: repositoryRoot) ?? "Detached HEAD"

      let scopePath = scopePath(repositoryRoot: repositoryRoot)
      let statusOutput = await GitProcessRunner.run(
        ["status", "--porcelain=v1", "--untracked-files=all"],
        in: repositoryRoot
      ) ?? ""

      snapshot = GitWorkingTreeService.shared.parseStatusOutput(
        statusOutput,
        scopePath: scopePath
      )
      lastOperation = "Working tree loaded."
      return
    }

    snapshot = GitWorkingTreeSnapshot(changes: [])
    branchName = "Unavailable"
    lastOperation = "Failed to locate the repository root."
  }

  private func scopePath(repositoryRoot: URL) -> String? {
    let repositoryPath = repositoryRoot.standardizedFileURL.path
    let directoryPath = workingDirectory.standardizedFileURL.path

    guard directoryPath != repositoryPath else {
      return nil
    }

    let prefix = "\(repositoryPath)/"
    guard directoryPath.hasPrefix(prefix) else {
      return nil
    }

    return String(directoryPath.dropFirst(prefix.count))
  }
}
