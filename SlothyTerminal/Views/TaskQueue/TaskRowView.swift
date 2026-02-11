import AppKit
import SwiftUI

/// Compact row for a single queued task in the sidebar panel.
struct TaskRowView: View {
  let task: QueuedTask
  var liveLogLine: String?
  let onTap: () -> Void
  let onCancel: () -> Void
  let onRetry: () -> Void
  let onRemove: () -> Void

  @State private var isHovered = false

  var body: some View {
    HStack(spacing: 8) {
      statusIcon

      /// Title + subtitle.
      VStack(alignment: .leading, spacing: 2) {
        Text(task.title)
          .font(.system(size: 11, weight: .medium))
          .lineLimit(1)
          .truncationMode(.tail)

        HStack(spacing: 4) {
          Image(systemName: task.agentType.iconName)
            .font(.system(size: 8))

          Text(task.agentType.rawValue)
            .font(.system(size: 9))

          if task.priority != .normal {
            priorityBadge
          }

          Spacer()

          Text(timeLabel)
            .font(.system(size: 9))
        }
        .foregroundColor(.secondary)

        if let liveLogLine,
           task.status == .running
        {
          Text(liveLogLine)
            .font(.system(size: 9, design: .monospaced))
            .foregroundColor(.secondary.opacity(0.7))
            .lineLimit(1)
            .truncationMode(.tail)
        }
      }

      Spacer(minLength: 0)

      /// Hover action button.
      if isHovered {
        hoverAction
      }
    }
    .padding(.vertical, 6)
    .padding(.horizontal, 8)
    .background(isHovered ? appCardColor : Color.clear)
    .cornerRadius(6)
    .contentShape(Rectangle())
    .onHover { hovering in
      isHovered = hovering
    }
    .onTapGesture {
      onTap()
    }
    .contextMenu {
      Button("Copy Title") {
        copyToClipboard(task.title)
      }

      Button("Copy Prompt") {
        copyToClipboard(task.prompt)
      }

      Divider()

      if task.status == .failed {
        Button("Retry") {
          onRetry()
        }
      }

      if task.status == .running || task.status == .pending {
        Button("Cancel") {
          onCancel()
        }
      }

      if task.status == .pending {
        Button("Remove") {
          onRemove()
        }
      }
    }
  }

  // MARK: - Status Icon

  @ViewBuilder
  private var statusIcon: some View {
    switch task.status {
    case .running:
      Image(systemName: "circle.fill")
        .font(.system(size: 8))
        .foregroundColor(.blue)
        .symbolEffect(.pulse)

    case .pending:
      Image(systemName: "clock.fill")
        .font(.system(size: 10))
        .foregroundColor(.secondary)

    case .completed:
      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 10))
        .foregroundColor(.green)

    case .failed:
      Image(systemName: "xmark.circle.fill")
        .font(.system(size: 10))
        .foregroundColor(.red)

    case .cancelled:
      Image(systemName: "minus.circle.fill")
        .font(.system(size: 10))
        .foregroundColor(.secondary)
    }
  }

  // MARK: - Priority Badge

  private var priorityBadge: some View {
    Text(task.priority == .high ? "High" : "Low")
      .font(.system(size: 8, weight: .semibold))
      .foregroundColor(task.priority == .high ? .orange : .secondary)
      .padding(.horizontal, 4)
      .padding(.vertical, 1)
      .background(
        (task.priority == .high ? Color.orange : Color.secondary)
          .opacity(0.15)
      )
      .cornerRadius(3)
  }

  // MARK: - Hover Action

  @ViewBuilder
  private var hoverAction: some View {
    switch task.status {
    case .pending:
      Button {
        onRemove()
      } label: {
        Image(systemName: "xmark")
          .font(.system(size: 9, weight: .semibold))
          .foregroundColor(.secondary)
      }
      .buttonStyle(.plain)
      .help("Remove")

    case .running:
      Button {
        onCancel()
      } label: {
        Image(systemName: "stop.circle")
          .font(.system(size: 12))
          .foregroundColor(.orange)
      }
      .buttonStyle(.plain)
      .help("Cancel")

    case .failed:
      Button {
        onRetry()
      } label: {
        Image(systemName: "arrow.counterclockwise")
          .font(.system(size: 10))
          .foregroundColor(.blue)
      }
      .buttonStyle(.plain)
      .help("Retry")

    default:
      EmptyView()
    }
  }

  // MARK: - Time Label

  private var timeLabel: String {
    let date = task.finishedAt ?? task.startedAt ?? task.createdAt
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: date, relativeTo: Date())
  }

  // MARK: - Helpers

  private func copyToClipboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }
}
