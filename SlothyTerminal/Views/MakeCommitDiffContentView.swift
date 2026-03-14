import SwiftUI

/// Side-by-side diff viewer for the Make Commit view.
struct MakeCommitDiffContentView: View {
  let selectedChange: MakeCommitSelection?
  let diffDocument: GitDiffDocument
  let isLoadingDiff: Bool

  var body: some View {
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
        .background(makeCommitSectionHeaderColor)

        Divider()
      }

      if isLoadingDiff {
        ProgressView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if selectedChange == nil {
        emptyState(
          iconName: "rectangle.split.2x1",
          message: "Select a file to view its diff."
        )
      } else if diffDocument.isBinary {
        emptyState(
          iconName: "doc.richtext",
          message: "Binary file — cannot display diff."
        )
      } else if diffDocument.isEmpty {
        emptyState(
          iconName: "text.alignleft",
          message: "No textual diff available."
        )
      } else {
        GeometryReader { diffGeometry in
          ScrollView([.vertical, .horizontal]) {
            LazyVStack(spacing: 0) {
              ForEach(diffDocument.rows) { row in
                diffRow(row)
              }
            }
            .frame(minWidth: diffGeometry.size.width)
          }
        }
      }
    }
    .background(appBackgroundColor)
  }

  // MARK: - Rows

  private func emptyState(
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

  // MARK: - Colors

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
}
