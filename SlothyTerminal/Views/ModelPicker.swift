import SwiftUI

/// Searchable popover for selecting a model, with optional provider grouping.
struct ModelPicker: View {
  let models: [ChatModelSelection]
  @Binding var selectedModel: ChatModelSelection?
  @Binding var isPresented: Bool
  var grouped: Bool = true

  @State private var searchText = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Select Model")
        .font(.system(size: 12, weight: .semibold))

      TextField("Search models", text: $searchText)
        .textFieldStyle(.roundedBorder)

      Divider()

      ScrollView {
        LazyVStack(alignment: .leading, spacing: 2) {
          modelRow(
            title: "Default",
            isSelected: selectedModel == nil
          ) {
            selectedModel = nil
            isPresented = false
          }

          if filteredModels.isEmpty && !searchText.isEmpty {
            Text("No matching models")
              .font(.system(size: 12))
              .foregroundColor(.secondary)
              .padding(.horizontal, 8)
              .padding(.vertical, 6)
          } else if grouped {
            groupedModelList
          } else {
            flatModelList
          }
        }
      }
      .frame(maxHeight: 260)
    }
    .padding(12)
    .frame(width: 360)
    .onAppear {
      searchText = ""
    }
  }

  // MARK: - Grouped List

  private var groupedModelList: some View {
    ForEach(groupedFilteredModels, id: \.name) { group in
      Text(group.name)
        .font(.system(size: 10, weight: .semibold))
        .foregroundColor(.secondary)
        .padding(.horizontal, 8)
        .padding(.top, 6)

      ForEach(group.models, id: \.cliModelString) { model in
        modelRow(
          title: model.modelID,
          isSelected: selectedModel == model
        ) {
          selectedModel = model
          isPresented = false
        }
      }
    }
  }

  // MARK: - Flat List

  private var flatModelList: some View {
    ForEach(filteredModels, id: \.cliModelString) { model in
      modelRow(
        title: model.displayName,
        isSelected: selectedModel == model
      ) {
        selectedModel = model
        isPresented = false
      }
    }
  }

  // MARK: - Model Row

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

  // MARK: - Filtering & Grouping

  private var filteredModels: [ChatModelSelection] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !query.isEmpty else {
      return models
    }

    let lowercaseQuery = query.lowercased()
    return models.filter { model in
      model.displayName.lowercased().contains(lowercaseQuery)
        || model.cliModelString.lowercased().contains(lowercaseQuery)
    }
  }

  private var groupedFilteredModels: [ModelGroup] {
    let grouped = Dictionary(grouping: filteredModels) { model in
      if model.providerID.isEmpty {
        return "other"
      }

      return model.providerID
    }

    return grouped
      .map { key, models in
        ModelGroup(
          name: key,
          models: models.sorted { $0.modelID < $1.modelID }
        )
      }
      .sorted { $0.name < $1.name }
  }

  private struct ModelGroup {
    let name: String
    let models: [ChatModelSelection]
  }
}
