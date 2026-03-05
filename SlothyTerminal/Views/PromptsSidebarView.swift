import SwiftUI

/// Sidebar panel displaying saved prompts with Paste and Edit actions.
struct PromptsSidebarView: View {
  @Environment(AppState.self) private var appState
  private var configManager = ConfigManager.shared

  @State private var editingPrompt: SavedPrompt?
  @State private var actionStatus: String?
  @State private var isStatusError: Bool = false
  @State private var statusDismissTask: Task<Void, Never>?

  private var prompts: [SavedPrompt] {
    configManager.config.savedPrompts
  }

  private var tags: [PromptTag] {
    configManager.config.promptTags
  }

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()

      if prompts.isEmpty {
        emptyState
      } else {
        promptList
      }
    }
    .background(appBackgroundColor)
    .sheet(item: $editingPrompt) { prompt in
      PromptEditorSheet(
        prompt: prompt,
        availableTags: tags,
        onSave: { updated in
          savePrompt(updated)
        }
      )
    }
  }

  // MARK: - Header

  private var header: some View {
    VStack(spacing: 0) {
      HStack {
        Text("Prompts")
          .font(.system(size: 10, weight: .semibold))
          .foregroundColor(.secondary)

        Spacer()

        SettingsLink {
          Image(systemName: "gear")
            .font(.system(size: 10))
            .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded {
          appState.pendingSettingsSection = .prompts
        })

        Text("\(prompts.count)")
          .font(.system(size: 9))
          .foregroundColor(.secondary.opacity(0.6))
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 6)

      if let status = actionStatus {
        HStack(spacing: 4) {
          Image(systemName: isStatusError ? "exclamationmark.circle" : "checkmark.circle")
            .font(.system(size: 9))

          Text(status)
            .font(.system(size: 9))
            .lineLimit(1)
        }
        .foregroundColor(isStatusError ? .red : .green)
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
        .transition(.opacity)
      }
    }
  }

  // MARK: - Empty State

  private var emptyState: some View {
    VStack(spacing: 12) {
      Spacer()

      Image(systemName: "text.bubble")
        .font(.system(size: 24))
        .foregroundColor(.secondary)

      Text("No saved prompts")
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(.secondary)

      Text("Create prompts in Settings.")
        .font(.system(size: 10))
        .foregroundColor(.secondary.opacity(0.7))

      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  // MARK: - Prompt List

  private var promptList: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 4) {
        ForEach(prompts) { prompt in
          promptBlock(prompt)
        }
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 6)
    }
  }

  // MARK: - Prompt Block

  private func promptBlock(_ prompt: SavedPrompt) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(prompt.name)
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(.primary)
        .lineLimit(1)

      if !prompt.promptDescription.isEmpty {
        Text(prompt.promptDescription)
          .font(.system(size: 10))
          .foregroundColor(.secondary)
          .lineLimit(2)
      }

      Text(prompt.previewText(maxLength: 60))
        .font(.system(size: 9, design: .monospaced))
        .foregroundColor(.secondary.opacity(0.7))
        .lineLimit(1)

      let promptTags = resolvedTags(for: prompt)
      if !promptTags.isEmpty {
        HStack(spacing: 4) {
          ForEach(promptTags) { tag in
            Text(tag.name)
              .font(.system(size: 8, weight: .medium))
              .foregroundColor(.secondary)
              .padding(.horizontal, 4)
              .padding(.vertical, 1)
              .background(appCardColor)
              .cornerRadius(3)
          }
        }
      }
    }
    .padding(8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(appCardColor)
    .cornerRadius(6)
    .contextMenu {
      Button("Paste to terminal") {
        pastePromptToTerminal(prompt)
      }

      Button("Edit") {
        editingPrompt = prompt
      }
    }
    .onTapGesture(count: 2) {
      pastePromptToTerminal(prompt)
    }
  }

  // MARK: - Tag Resolution

  private func resolvedTags(for prompt: SavedPrompt) -> [PromptTag] {
    prompt.tagIDs.compactMap { tagId in
      tags.find(by: tagId)
    }
  }

  private func pastePromptToTerminal(_ prompt: SavedPrompt) {
    guard let text = validatedPromptText(prompt) else {
      return
    }

    guard activeTerminalIsInjectable() else {
      return
    }

    let request = InjectionRequest(
      payload: .paste(text, mode: .bracketed),
      target: .activeTab,
      origin: .ui
    )

    let result = appState.inject(request)

    guard let result else {
      showStatus("Paste failed", isError: true)
      return
    }

    switch result.status {
    case .completed, .written, .accepted, .queued:
      showStatus("Pasted: \(prompt.name)", isError: false)

    case .failed, .cancelled, .timeout:
      showStatus("Paste \(result.status.rawValue)", isError: true)
    }
  }

  private func validatedPromptText(_ prompt: SavedPrompt) -> String? {
    let text = prompt.promptText.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !text.isEmpty else {
      showStatus("Prompt text is empty", isError: true)
      return nil
    }

    return text
  }

  private func activeTerminalIsInjectable() -> Bool {
    guard let activeTab = appState.activeTab else {
      showStatus("No active tab", isError: true)
      return false
    }

    guard activeTab.mode == .terminal else {
      showStatus("Active tab is not a terminal", isError: true)
      return false
    }

    let injectableIds = Set(appState.listInjectableTabs())

    guard injectableIds.contains(activeTab.id) else {
      showStatus("Terminal surface not ready", isError: true)
      return false
    }

    return true
  }

  // MARK: - Edit / Save

  private func savePrompt(_ updated: SavedPrompt) {
    var savedPrompts = configManager.config.savedPrompts

    if let index = savedPrompts.firstIndex(where: { $0.id == updated.id }) {
      savedPrompts[index] = updated
    }

    configManager.config.savedPrompts = savedPrompts
    showStatus("Prompt updated", isError: false)
  }

  // MARK: - Status Feedback

  private func showStatus(_ message: String, isError: Bool) {
    statusDismissTask?.cancel()

    withAnimation(.easeInOut(duration: 0.2)) {
      actionStatus = message
      isStatusError = isError
    }

    statusDismissTask = Task {
      try? await Task.sleep(nanoseconds: 2_500_000_000)

      guard !Task.isCancelled else {
        return
      }

      withAnimation(.easeInOut(duration: 0.3)) {
        actionStatus = nil
      }
    }
  }
}
