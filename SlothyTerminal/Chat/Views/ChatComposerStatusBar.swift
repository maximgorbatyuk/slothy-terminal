import SwiftUI

/// Compact bar below the chat input showing Mode and Model selectors.
struct ChatComposerStatusBar: View {
  let chatState: ChatState
  let agentType: AgentType

  @State private var isModelPickerPresented = false
  @State private var modelSearchText = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 12) {
        modeMenu
        modelMenu
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
      modelPickerPopover
    }
  }

  private var modelPickerPopover: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Select Model")
        .font(.system(size: 12, weight: .semibold))

      TextField("Search models", text: $modelSearchText)
        .textFieldStyle(.roundedBorder)

      Divider()

      ScrollView {
        LazyVStack(alignment: .leading, spacing: 2) {
          modelRow(
            title: "Default",
            isSelected: chatState.selectedModel == nil
          ) {
            chatState.selectedModel = nil
            isModelPickerPresented = false
          }

          if agentType == .opencode {
            ForEach(groupedFilteredModelOptions, id: \.name) { group in
              Text(group.name)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 6)

              ForEach(group.models, id: \.cliModelString) { model in
                modelRow(
                  title: model.displayName,
                  isSelected: chatState.selectedModel == model
                ) {
                  chatState.selectedModel = model
                  isModelPickerPresented = false
                }
              }
            }
          } else {
            ForEach(filteredModelOptions, id: \.cliModelString) { model in
              modelRow(
                title: model.displayName,
                isSelected: chatState.selectedModel == model
              ) {
                chatState.selectedModel = model
                isModelPickerPresented = false
              }
            }
          }
        }
      }
      .frame(maxHeight: 260)
    }
    .padding(12)
    .frame(width: 360)
    .onAppear {
      modelSearchText = ""
    }
  }

  @ViewBuilder
  private func modelRow(
    title: String,
    isSelected: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button {
      action()
    } label: {
      HStack(spacing: 6) {
        Text(title)
          .font(.system(size: 12))

        Spacer(minLength: 0)

        if isSelected {
          Image(systemName: "checkmark")
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.accentColor)
        }
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 6)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .background(
      RoundedRectangle(cornerRadius: 6)
        .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
    )
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

  private var filteredModelOptions: [ChatModelSelection] {
    let query = modelSearchText.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !query.isEmpty else {
      return modelOptions
    }

    let lowercaseQuery = query.lowercased()
    return modelOptions.filter { model in
      model.displayName.lowercased().contains(lowercaseQuery)
        || model.cliModelString.lowercased().contains(lowercaseQuery)
    }
  }

  private var groupedFilteredModelOptions: [ModelGroup] {
    let grouped = Dictionary(grouping: filteredModelOptions) { model in
      if model.providerID.isEmpty {
        return "other"
      }

      return model.providerID
    }

    return grouped
      .map { key, models in
        ModelGroup(
          name: key,
          models: models.sorted { $0.displayName < $1.displayName }
        )
      }
      .sorted { $0.name < $1.name }
  }

  private struct ModelGroup {
    let name: String
    let models: [ChatModelSelection]
  }

  private var selectedSummary: String {
    let mode = chatState.selectedMode.displayName
    let model = chatState.selectedModel?.cliModelString ?? "Default"
    return "\(mode) · \(model)"
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
