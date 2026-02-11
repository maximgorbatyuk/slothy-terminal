import AppKit
import SwiftUI

/// Panel showing git modified/untracked files for the active tab's directory.
struct GitChangesView: View {
  @Environment(AppState.self) private var appState

  @State private var files: [GitModifiedFile] = []
  @State private var isLoading = false

  private var activeDirectory: URL? {
    appState.activeTab?.workingDirectory
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      /// Header with refresh button.
      HStack {
        HStack(spacing: 4) {
          Image(systemName: "arrow.triangle.branch")
            .font(.system(size: 10))

          Text("Modified Files")
            .font(.system(size: 10, weight: .semibold))
        }
        .foregroundColor(.secondary)

        Spacer()

        Button {
          refreshFiles()
        } label: {
          Image(systemName: "arrow.clockwise")
            .font(.system(size: 10))
            .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .help("Refresh")
      }

      /// File list.
      if isLoading {
        ProgressView()
          .scaleEffect(0.7)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if files.isEmpty {
        VStack(spacing: 8) {
          Image(systemName: "checkmark.circle")
            .font(.system(size: 24))
            .foregroundColor(.green.opacity(0.6))

          Text("No modified files")
            .font(.system(size: 11))
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(files) { file in
              GitModifiedFileRow(file: file)
            }
          }
          .padding(6)
        }
        .background(appCardColor)
        .cornerRadius(8)
      }
    }
    .padding()
    .background(appBackgroundColor)
    .task(id: activeDirectory) {
      refreshFiles()
    }
  }

  private func refreshFiles() {
    guard let directory = activeDirectory else {
      files = []
      return
    }

    isLoading = true
    files = GitService.shared.getModifiedFiles(in: directory)
    isLoading = false
  }
}

/// A row showing a single git-modified file.
struct GitModifiedFileRow: View {
  let file: GitModifiedFile

  @State private var isHovered = false
  @State private var showCopiedTooltip = false

  var body: some View {
    HStack(spacing: 6) {
      /// Status badge.
      Text(file.status.badge)
        .font(.system(size: 9, weight: .bold, design: .monospaced))
        .foregroundColor(file.status.color)
        .frame(width: 14, alignment: .center)

      /// Filename + path.
      VStack(alignment: .leading, spacing: 1) {
        Text(file.filename)
          .font(.system(size: 11))
          .lineLimit(1)
          .truncationMode(.middle)

        if file.filename != file.path {
          Text(file.path)
            .font(.system(size: 9))
            .foregroundColor(.secondary)
            .lineLimit(1)
            .truncationMode(.head)
        }
      }

      Spacer()
    }
    .padding(.vertical, 4)
    .padding(.horizontal, 6)
    .background(isHovered ? Color.primary.opacity(0.05) : Color.clear)
    .cornerRadius(4)
    .contentShape(Rectangle())
    .onHover { hovering in
      isHovered = hovering
    }
    .onTapGesture(count: 2) {
      copyToClipboard(file.path)
    }
    .contextMenu {
      Button("Copy Relative Path") {
        copyToClipboard(file.path)
      }

      Button("Copy Filename") {
        copyToClipboard(file.filename)
      }
    }
    .overlay(alignment: .trailing) {
      if showCopiedTooltip {
        Text("Copied!")
          .font(.system(size: 9))
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(Color.green.opacity(0.9))
          .foregroundColor(.white)
          .cornerRadius(4)
          .transition(.opacity)
      }
    }
  }

  private func copyToClipboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)

    withAnimation {
      showCopiedTooltip = true
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
      withAnimation {
        showCopiedTooltip = false
      }
    }
  }
}
