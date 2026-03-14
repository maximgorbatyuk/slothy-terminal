import SwiftUI

/// Commit message composer for the Make Commit view.
struct MakeCommitComposerView: View {
  let snapshot: GitWorkingTreeSnapshot
  @Binding var commitMessage: String
  @Binding var isAmendingLastCommit: Bool
  let isBusy: Bool
  let canSubmitCommit: Bool
  let onCommit: () -> Void

  var body: some View {
    VStack(spacing: 8) {
      if snapshot.hasStagedChangesOutsideScope {
        Label(
          "Commit blocked — staged changes exist outside this scoped directory.",
          systemImage: "exclamationmark.triangle.fill"
        )
        .font(.system(size: 10))
        .foregroundStyle(.orange)
      }

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
          onCommit()
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
}
