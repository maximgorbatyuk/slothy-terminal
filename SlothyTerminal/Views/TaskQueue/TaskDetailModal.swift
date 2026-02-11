import AppKit
import SwiftUI

/// Modal showing full details for a queued task.
struct TaskDetailModal: View {
  let taskId: UUID

  @Environment(AppState.self) private var appState
  @Environment(\.dismiss) private var dismiss

  @State private var logContent: String?

  private var task: QueuedTask? {
    appState.taskQueueState.tasks.first { $0.id == taskId }
  }

  var body: some View {
    if let task {
      VStack(spacing: 0) {
        header(task)
        Divider()
        content(task)
        Divider()
        actionBar(task)
      }
      .frame(width: 500)
      .frame(maxHeight: 600)
      .background(appBackgroundColor)
      .task {
        await loadLog(task)
      }
    } else {
      VStack(spacing: 12) {
        Text("Task not found")
          .font(.system(size: 14))
          .foregroundColor(.secondary)

        Button("Dismiss") {
          dismiss()
        }
      }
      .frame(width: 400, height: 200)
      .background(appBackgroundColor)
    }
  }

  // MARK: - Header

  private func header(_ task: QueuedTask) -> some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(task.title)
          .font(.system(size: 14, weight: .semibold))
          .lineLimit(2)

        statusBadge(task)
      }

      Spacer()

      Button {
        dismiss()
      } label: {
        Image(systemName: "xmark.circle.fill")
          .font(.system(size: 20))
          .foregroundColor(.secondary)
      }
      .buttonStyle(.plain)
      .keyboardShortcut(.escape)
    }
    .padding(20)
  }

  // MARK: - Status Badge

  private func statusBadge(_ task: QueuedTask) -> some View {
    HStack(spacing: 4) {
      Circle()
        .fill(statusColor(task.status))
        .frame(width: 6, height: 6)

      Text(task.status.rawValue.capitalized)
        .font(.system(size: 10, weight: .medium))
        .foregroundColor(statusColor(task.status))
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 3)
    .background(statusColor(task.status).opacity(0.12))
    .cornerRadius(4)
  }

  private func statusColor(_ status: TaskStatus) -> Color {
    switch status {
    case .running:
      return .blue

    case .pending:
      return .secondary

    case .completed:
      return .green

    case .failed:
      return .red

    case .cancelled:
      return .secondary
    }
  }

  // MARK: - Content

  private func content(_ task: QueuedTask) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        metadataSection(task)
        promptSection(task)

        if let summary = task.resultSummary,
           !summary.isEmpty
        {
          resultSection(summary)
        }

        if let riskyOps = task.detectedRiskyOperations,
           !riskyOps.isEmpty
        {
          riskyOperationsSection(riskyOps)
        }

        if let error = task.lastError,
           !error.isEmpty
        {
          errorSection(error)
        }

        if task.status == .running {
          liveLogSection
        }

        if let log = logContent {
          logSection(log)
        }
      }
      .padding(20)
    }
  }

  // MARK: - Metadata Section

  private func metadataSection(_ task: QueuedTask) -> some View {
    StatsSection(title: "Details") {
      StatRow(label: "Agent", value: task.agentType.rawValue)

      if let model = task.model {
        StatRow(label: "Model", value: model.displayName)
      }

      if let mode = task.mode {
        StatRow(label: "Mode", value: mode.displayName)
      }

      StatRow(label: "Priority", value: task.priority.rawValue.capitalized)
      StatRow(label: "Created", value: formatDate(task.createdAt))

      if let started = task.startedAt {
        StatRow(label: "Started", value: formatDate(started))
      }

      if let finished = task.finishedAt {
        StatRow(label: "Finished", value: formatDate(finished))
      }

      StatRow(
        label: "Retries",
        value: "\(task.retryCount) / \(task.maxRetries)"
      )

      if let exitReason = task.exitReason {
        StatRow(
          label: "Exit Reason",
          value: exitReason.rawValue.capitalized,
          style: exitReason == .completed ? .normal : .warning
        )
      }

      if let failureKind = task.failureKind {
        StatRow(label: "Failure Kind", value: failureKind.rawValue.capitalized)
      }

      if let sessionId = task.sessionId {
        StatRow(label: "Session ID", value: sessionId)
      }

      if task.approvalState != .none {
        StatRow(label: "Approval", value: task.approvalState.rawValue.capitalized)
      }
    }
  }

  // MARK: - Prompt Section

  private func promptSection(_ task: QueuedTask) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("PROMPT")
          .font(.system(size: 10, weight: .semibold))
          .foregroundColor(.secondary)

        Spacer()

        Button {
          copyToClipboard(task.prompt)
        } label: {
          Image(systemName: "doc.on.doc")
            .font(.system(size: 9))
            .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .help("Copy Prompt")
      }

      Text(task.prompt)
        .font(.system(size: 11))
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(appCardColor)
        .cornerRadius(8)
    }
  }

  // MARK: - Result Section

  private func resultSection(_ summary: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("RESULT")
        .font(.system(size: 10, weight: .semibold))
        .foregroundColor(.secondary)

      Text(summary)
        .font(.system(size: 11))
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.green.opacity(0.08))
        .cornerRadius(8)
    }
  }

  // MARK: - Error Section

  private func errorSection(_ error: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("ERROR")
        .font(.system(size: 10, weight: .semibold))
        .foregroundColor(.red)

      Text(error)
        .font(.system(size: 11))
        .foregroundColor(.orange)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(8)
    }
  }

  // MARK: - Log Section

  private func logSection(_ log: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("LOG")
          .font(.system(size: 10, weight: .semibold))
          .foregroundColor(.secondary)

        Spacer()

        Button {
          copyToClipboard(log)
        } label: {
          HStack(spacing: 4) {
            Image(systemName: "doc.on.doc")
              .font(.system(size: 9))

            Text("Copy Log")
              .font(.system(size: 9))
          }
          .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .help("Copy Log")
      }

      ScrollView {
        Text(log)
          .font(.system(size: 10, design: .monospaced))
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(maxHeight: 150)
      .padding(10)
      .background(appCardColor)
      .cornerRadius(8)
    }
  }

  // MARK: - Risky Operations Section

  private func riskyOperationsSection(_ operations: [String]) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 4) {
        Image(systemName: "shield.lefthalf.filled")
          .font(.system(size: 10))
          .foregroundColor(.orange)

        Text("RISKY OPERATIONS DETECTED")
          .font(.system(size: 10, weight: .semibold))
          .foregroundColor(.orange)
      }

      VStack(alignment: .leading, spacing: 4) {
        ForEach(operations, id: \.self) { op in
          HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
              .font(.system(size: 9))
              .foregroundColor(.orange)

            Text(op)
              .font(.system(size: 11))
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(10)
      .background(Color.orange.opacity(0.08))
      .cornerRadius(8)
    }
  }

  // MARK: - Live Log Section

  private var liveLogSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 4) {
        Circle()
          .fill(Color.green)
          .frame(width: 6, height: 6)

        Text("LIVE LOG")
          .font(.system(size: 10, weight: .semibold))
          .foregroundColor(.secondary)
      }

      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 1) {
            ForEach(appState.taskQueueState.liveLogEntries) { entry in
              Text(entry.text)
                .font(.system(size: 10, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
          .padding(6)
        }
        .frame(maxHeight: 150)
        .background(appCardColor)
        .cornerRadius(8)
        .onChange(of: appState.taskQueueState.liveLogEntries.count) {
          if let lastEntry = appState.taskQueueState.liveLogEntries.last {
            proxy.scrollTo(lastEntry.id, anchor: .bottom)
          }
        }
      }
    }
  }

  // MARK: - Action Bar

  private func actionBar(_ task: QueuedTask) -> some View {
    HStack {
      if task.status == .pending {
        Button("Remove") {
          appState.taskQueueState.removeTask(id: task.id)
          dismiss()
        }
        .foregroundColor(.red)
      }

      if task.approvalState == .waiting {
        Button("Reject") {
          appState.taskQueueState.rejectTask(id: task.id)
          dismiss()
        }
        .foregroundColor(.red)
      }

      Spacer()

      if task.status == .running {
        Button("Cancel") {
          appState.taskOrchestrator?.cancelRunningTask()
        }
        .foregroundColor(.orange)
      }

      if task.approvalState == .waiting {
        Button("Approve") {
          appState.taskQueueState.approveTask(id: task.id)
          dismiss()
        }
        .buttonStyle(.borderedProminent)
      }

      if task.status == .failed,
         task.isRetryable
      {
        Button("Retry") {
          appState.taskQueueState.retryTask(id: task.id)
          dismiss()
        }
        .buttonStyle(.borderedProminent)
      }
    }
    .padding(20)
  }

  // MARK: - Helpers

  private func formatDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .medium
    return formatter.string(from: date)
  }

  private func loadLog(_ task: QueuedTask) async {
    guard let logPath = task.logArtifactPath else {
      return
    }

    let url = URL(fileURLWithPath: logPath)

    do {
      logContent = try String(contentsOf: url, encoding: .utf8)
    } catch {
      logContent = nil
    }
  }

  private func copyToClipboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }
}
