import SwiftUI

/// Compact bar below the chat input showing Mode and Model selectors.
struct ChatComposerStatusBar: View {
  let chatState: ChatState
  let agentType: AgentType

  @State private var isModelPickerPresented = false

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 12) {
        modeMenu
        modelMenu

        if agentType == .opencode {
          askModeToggle
        }

        Spacer()
      }

      HStack(spacing: 12) {
        Text("Selected: \(selectedSummary)")
          .font(.system(size: 10))
          .foregroundColor(.secondary)

        Text("Resolved: \(resolvedSummary)")
          .font(.system(size: 10))
          .foregroundColor(.secondary.opacity(0.8))

        Spacer()
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 4)
    .task {
      chatState.refreshModelCatalogIfNeeded(for: agentType)
    }
  }

  // MARK: - Mode selector

  private var modeMenu: some View {
    Menu {
      ForEach(ChatMode.allCases, id: \.self) { mode in
        Button {
          chatState.selectedMode = mode
        } label: {
          HStack {
            Text(mode.displayName)

            if chatState.selectedMode == mode {
              Image(systemName: "checkmark")
            }
          }
        }
      }
    } label: {
      HStack(spacing: 4) {
        Image(systemName: chatState.selectedMode == .plan ? "doc.text" : "hammer")
          .font(.system(size: 9))

        Text(chatState.selectedMode.displayName)
          .font(.system(size: 10))
      }
      .foregroundColor(.secondary)
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(Color.secondary.opacity(0.08))
      .cornerRadius(4)
    }
    .menuStyle(.borderlessButton)
    .fixedSize()
  }

  // MARK: - Model selector

  private var modelMenu: some View {
    Button {
      isModelPickerPresented = true
    } label: {
      HStack(spacing: 4) {
        Image(systemName: "cpu")
          .font(.system(size: 9))

        Text(chatState.selectedModel?.displayName ?? "Default")
          .font(.system(size: 10))
      }
      .foregroundColor(.secondary)
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(Color.secondary.opacity(0.08))
      .cornerRadius(4)
    }
    .buttonStyle(.plain)
    .fixedSize()
    .popover(isPresented: $isModelPickerPresented, arrowEdge: .top) {
      ModelPicker(
        models: modelOptions,
        selectedModel: Binding(
          get: { chatState.selectedModel },
          set: { chatState.selectedModel = $0 }
        ),
        isPresented: $isModelPickerPresented,
        grouped: agentType == .opencode
      )
    }
  }

  // MARK: - Ask mode

  private var askModeToggle: some View {
    Button {
      chatState.isOpenCodeAskModeEnabled.toggle()
    } label: {
      HStack(spacing: 4) {
        Image(systemName: chatState.isOpenCodeAskModeEnabled ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right")
          .font(.system(size: 9))

        Text(chatState.isOpenCodeAskModeEnabled ? "Ask: On" : "Ask: Off")
          .font(.system(size: 10))
      }
      .foregroundColor(chatState.isOpenCodeAskModeEnabled ? .blue : .secondary)
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(Color.secondary.opacity(0.08))
      .cornerRadius(4)
    }
    .buttonStyle(.plain)
    .fixedSize()
    .help("When enabled, OpenCode asks clarifying questions before implementing when requirements are unclear")
  }

  // MARK: - Model options per agent

  private var modelOptions: [ChatModelSelection] {
    switch agentType {
    case .claude:
      return [
        ChatModelSelection(
          providerID: "anthropic",
          modelID: "claude-sonnet-4-5-20250929",
          displayName: "claude-sonnet-4-5"
        ),
        ChatModelSelection(
          providerID: "anthropic",
          modelID: "claude-opus-4-6",
          displayName: "claude-opus-4-6"
        ),
      ]

    case .opencode:
      if !chatState.openCodeModelOptions.isEmpty {
        return chatState.openCodeModelOptions
      }

      /// Fallback list until dynamic catalog is loaded.
      return [
        ChatModelSelection(
          providerID: "anthropic",
          modelID: "claude-sonnet-4-5-20250929",
          displayName: "anthropic/claude-sonnet-4-5-20250929"
        ),
        ChatModelSelection(
          providerID: "openai",
          modelID: "gpt-5.3-codex",
          displayName: "openai/gpt-5.3-codex"
        ),
        ChatModelSelection(
          providerID: "zai",
          modelID: "glm-4.7",
          displayName: "zai/glm-4.7"
        ),
      ]

    case .terminal:
      return []
    }
  }

  private var selectedSummary: String {
    let mode = chatState.selectedMode.displayName
    let model = chatState.selectedModel?.cliModelString ?? "Default"
    let askMode = (agentType == .opencode && chatState.isOpenCodeAskModeEnabled) ? " · Ask mode" : ""
    return "\(mode) · \(model)\(askMode)"
  }

  private var resolvedSummary: String {
    guard let resolved = chatState.resolvedMetadata else {
      return "Resolving..."
    }

    let mode = resolved.resolvedMode?.displayName ?? chatState.selectedMode.displayName

    let model: String
    if let provider = resolved.resolvedProviderID,
       !provider.isEmpty,
       let modelID = resolved.resolvedModelID,
       !modelID.isEmpty
    {
      model = "\(provider)/\(modelID)"
    } else if let modelID = resolved.resolvedModelID,
              !modelID.isEmpty
    {
      model = modelID
    } else {
      model = chatState.selectedModel?.cliModelString ?? "Default"
    }

    return "\(mode) · \(model)"
  }
}
