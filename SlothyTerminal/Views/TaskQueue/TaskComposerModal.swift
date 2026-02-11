import AppKit
import SwiftUI

/// Modal form for creating a new queued task.
struct TaskComposerModal: View {
  @Environment(AppState.self) private var appState
  @Environment(\.dismiss) private var dismiss

  @State private var title = ""
  @State private var prompt = ""
  @State private var agentType: AgentType = .claude
  @State private var priority: TaskPriority = .normal
  @State private var selectedDirectory: URL?

  private let recentFoldersManager = RecentFoldersManager.shared

  private var currentDirectory: URL {
    selectedDirectory
      ?? appState.activeTab?.workingDirectory
      ?? recentFoldersManager.recentFolders.first
      ?? FileManager.default.homeDirectoryForCurrentUser
  }

  private var displayPath: String {
    let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
    let fullPath = currentDirectory.path

    if fullPath.hasPrefix(homeDir) {
      return "~" + fullPath.dropFirst(homeDir.count)
    }

    return fullPath
  }

  private var canSubmit: Bool {
    !title.trimmingCharacters(in: .whitespaces).isEmpty
      && !prompt.trimmingCharacters(in: .whitespaces).isEmpty
  }

  private var chatAgents: [AgentType] {
    AgentType.allCases.filter(\.supportsChatMode)
  }

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      formContent
      Divider()
      footer
    }
    .frame(width: 450)
    .background(appBackgroundColor)
  }

  // MARK: - Header

  private var header: some View {
    HStack {
      Text("Create Task")
        .font(.headline)

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

  // MARK: - Form

  private var formContent: some View {
    VStack(alignment: .leading, spacing: 16) {
      /// Title field.
      VStack(alignment: .leading, spacing: 6) {
        Text("TITLE")
          .font(.system(size: 10, weight: .semibold))
          .foregroundColor(.secondary)

        TextField("Task title", text: $title)
          .textFieldStyle(.roundedBorder)
          .font(.system(size: 12))
      }

      /// Prompt field.
      VStack(alignment: .leading, spacing: 6) {
        Text("PROMPT")
          .font(.system(size: 10, weight: .semibold))
          .foregroundColor(.secondary)

        TextEditor(text: $prompt)
          .font(.system(size: 12))
          .frame(minHeight: 80, maxHeight: 120)
          .padding(4)
          .background(appCardColor)
          .cornerRadius(6)
          .overlay(
            RoundedRectangle(cornerRadius: 6)
              .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
          )
      }

      /// Agent picker.
      VStack(alignment: .leading, spacing: 6) {
        Text("AGENT")
          .font(.system(size: 10, weight: .semibold))
          .foregroundColor(.secondary)

        Picker("", selection: $agentType) {
          ForEach(chatAgents) { agent in
            Text(agent.rawValue).tag(agent)
          }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
      }

      /// Working directory.
      VStack(alignment: .leading, spacing: 6) {
        Text("WORKING DIRECTORY")
          .font(.system(size: 10, weight: .semibold))
          .foregroundColor(.secondary)

        HStack(spacing: 12) {
          HStack(spacing: 8) {
            Image(systemName: "folder.fill")
              .font(.system(size: 14))
              .foregroundColor(.secondary)

            Text(displayPath)
              .font(.system(size: 12))
              .foregroundColor(.primary)
              .lineLimit(1)
              .truncationMode(.middle)
          }
          .frame(maxWidth: .infinity, alignment: .leading)

          Button {
            openFolderPicker()
          } label: {
            Text("Change...")
              .font(.system(size: 12))
          }
          .buttonStyle(.bordered)
        }
        .padding(12)
        .background(appCardColor)
        .cornerRadius(8)
      }

      /// Priority picker.
      VStack(alignment: .leading, spacing: 6) {
        Text("PRIORITY")
          .font(.system(size: 10, weight: .semibold))
          .foregroundColor(.secondary)

        Picker("", selection: $priority) {
          Text("High").tag(TaskPriority.high)
          Text("Normal").tag(TaskPriority.normal)
          Text("Low").tag(TaskPriority.low)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
      }
    }
    .padding(20)
  }

  // MARK: - Footer

  private var footer: some View {
    HStack {
      Spacer()

      Button("Cancel") {
        dismiss()
      }
      .keyboardShortcut(.escape)

      Button("Add Task") {
        submitTask()
      }
      .buttonStyle(.borderedProminent)
      .disabled(!canSubmit)
      .keyboardShortcut(.return, modifiers: .command)
    }
    .padding(20)
  }

  // MARK: - Actions

  private func submitTask() {
    appState.taskQueueState.enqueueTask(
      title: title.trimmingCharacters(in: .whitespaces),
      prompt: prompt.trimmingCharacters(in: .whitespaces),
      repoPath: currentDirectory.path,
      agentType: agentType,
      priority: priority
    )
    dismiss()
  }

  private func openFolderPicker() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true
    panel.message = "Select a working directory"
    panel.prompt = "Select"
    panel.directoryURL = currentDirectory

    panel.begin { response in
      Task { @MainActor in
        if response == .OK,
           let url = panel.url
        {
          selectedDirectory = url
        }
      }
    }
  }
}
