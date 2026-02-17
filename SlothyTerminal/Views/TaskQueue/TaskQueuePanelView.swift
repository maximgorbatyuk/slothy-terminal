import SwiftUI

/// Main sidebar panel for the task queue, replacing the placeholder.
struct TaskQueuePanelView: View {
  @Environment(AppState.self) private var appState

  @State private var isHistoryExpanded = true

  private var tasks: [QueuedTask] {
    appState.taskQueueState.tasks
  }

  private var runningTasks: [QueuedTask] {
    tasks.filter { $0.status == .running }
  }

  private var pendingTasks: [QueuedTask] {
    tasks.filter { $0.status == .pending }
  }

  private var historyTasks: [QueuedTask] {
    tasks.filter { $0.isTerminal }
  }

  private var approvalPendingTask: QueuedTask? {
    tasks.first { $0.approvalState == .waiting }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      header
      queueSummary

      if let awaitingTask = approvalPendingTask {
        approvalBanner(awaitingTask)
      }

      if tasks.isEmpty {
        emptyState
      } else {
        taskList
      }
    }
    .padding()
    .background(appBackgroundColor)
  }

  // MARK: - Header

  private var header: some View {
    HStack {
      HStack(spacing: 4) {
        Image(systemName: "checklist")
          .font(.system(size: 10))

        Text("Task Queue")
          .font(.system(size: 10, weight: .semibold))
      }
      .foregroundColor(.secondary)

      Spacer()

      Button {
        appState.showAddTaskModal()
      } label: {
        Image(systemName: "plus")
          .font(.system(size: 10, weight: .semibold))
          .foregroundColor(.secondary)
      }
      .buttonStyle(.plain)
      .help("Add Task")
    }
  }

  // MARK: - Queue Summary

  private var queueSummary: some View {
    HStack(spacing: 8) {
      /// Running indicator.
      HStack(spacing: 4) {
        Circle()
          .fill(runningTasks.isEmpty ? Color.secondary.opacity(0.3) : Color.green)
          .frame(width: 6, height: 6)

        Text(runningTasks.isEmpty ? "Idle" : "Running")
          .font(.system(size: 9))
          .foregroundColor(.secondary)
      }

      Spacer()

      /// Counts.
      if !tasks.isEmpty {
        Text("\(pendingTasks.count) pending")
          .font(.system(size: 9))
          .foregroundColor(.secondary)
      }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(appCardColor)
    .cornerRadius(6)
  }

  // MARK: - Empty State

  private var emptyState: some View {
    VStack(spacing: 8) {
      Image(systemName: "tray")
        .font(.system(size: 24))
        .foregroundColor(.secondary.opacity(0.6))

      Text("No tasks queued")
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(.secondary)

      Text("Add a task to get started")
        .font(.system(size: 10))
        .foregroundColor(.secondary.opacity(0.7))
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  // MARK: - Task List

  private var taskList: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 0) {
        if !runningTasks.isEmpty {
          sectionHeader("RUNNING")

          ForEach(runningTasks) { task in
            taskRow(task)
          }
        }

        if !pendingTasks.isEmpty {
          sectionHeader("PENDING")

          ForEach(pendingTasks) { task in
            taskRow(task)
          }
        }

        if !historyTasks.isEmpty {
          historySectionHeader

          if isHistoryExpanded {
            ForEach(historyTasks) { task in
              taskRow(task)
            }
          }
        }
      }
      .padding(4)
    }
    .background(appCardColor)
    .cornerRadius(8)
  }

  // MARK: - Section Header

  private func sectionHeader(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 9, weight: .semibold))
      .foregroundColor(.secondary)
      .padding(.horizontal, 8)
      .padding(.top, 8)
      .padding(.bottom, 2)
  }

  private var historySectionHeader: some View {
    Button {
      withAnimation(.easeInOut(duration: 0.2)) {
        isHistoryExpanded.toggle()
      }
    } label: {
      HStack(spacing: 4) {
        Text("HISTORY")
          .font(.system(size: 9, weight: .semibold))
          .foregroundColor(.secondary)

        Image(systemName: isHistoryExpanded ? "chevron.down" : "chevron.right")
          .font(.system(size: 8))
          .foregroundColor(.secondary)

        Spacer()

        Text("\(historyTasks.count)")
          .font(.system(size: 9))
          .foregroundColor(.secondary.opacity(0.7))
      }
      .padding(.horizontal, 8)
      .padding(.top, 8)
      .padding(.bottom, 2)
    }
    .buttonStyle(.plain)
  }

  // MARK: - Task Row

  private func taskRow(_ task: QueuedTask) -> some View {
    TaskRowView(
      task: task,
      liveLogLine: task.status == .running ? appState.taskQueueState.lastLiveLogLine : nil,
      onTap: {
        appState.showTaskDetail(id: task.id)
      },
      onCancel: {
        if task.status == .running {
          appState.taskOrchestrator?.cancelRunningTask()
        } else {
          appState.taskQueueState.cancelTask(id: task.id)
        }
      },
      onRetry: {
        appState.taskQueueState.retryTask(id: task.id)
      },
      onRemove: {
        appState.taskQueueState.removeTask(id: task.id)
      }
    )
  }

  // MARK: - Approval Banner

  private func approvalBanner(_ task: QueuedTask) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 4) {
        Image(systemName: "shield.lefthalf.filled")
          .font(.system(size: 10))
          .foregroundColor(.orange)

        Text("Approval Required")
          .font(.system(size: 10, weight: .semibold))
          .foregroundColor(.orange)
      }

      Text(task.title)
        .font(.system(size: 10))
        .foregroundColor(.secondary)
        .lineLimit(1)

      HStack(spacing: 8) {
        Button("Review") {
          appState.showTaskDetail(id: task.id)
        }
        .font(.system(size: 10))

        Spacer()

        Button("Reject") {
          appState.taskQueueState.rejectTask(id: task.id)
        }
        .font(.system(size: 10))
        .foregroundColor(.red)

        Button("Approve") {
          appState.taskQueueState.approveTask(id: task.id)
        }
        .font(.system(size: 10))
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
      }
    }
    .padding(8)
    .background(Color.orange.opacity(0.08))
    .cornerRadius(6)
  }
}
