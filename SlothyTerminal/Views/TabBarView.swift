import SwiftUI

/// The tab bar displaying all open terminal tabs.
struct TabBarView: View {
  @Environment(AppState.self) private var appState

  var body: some View {
    HStack(spacing: 0) {
      /// Tab items.
      ForEach(appState.tabs) { tab in
        TabItemView(tab: tab)
      }

      /// New tab button.
      NewTabButton()

      Spacer()
    }
    .frame(height: 36)
    .background(Color(.windowBackgroundColor))
  }
}

/// A single tab item in the tab bar.
struct TabItemView: View {
  let tab: Tab
  @Environment(AppState.self) private var appState

  private var isActive: Bool {
    appState.activeTabID == tab.id
  }

  var body: some View {
    HStack(spacing: 6) {
      /// Agent icon.
      Image(systemName: tab.agentType.iconName)
        .foregroundColor(tab.agentType.accentColor)
        .font(.system(size: 12))

      /// Tab title.
      Text(tab.title)
        .font(.system(size: 12))
        .lineLimit(1)

      /// Close button.
      Button {
        appState.closeTab(id: tab.id)
      } label: {
        Image(systemName: "xmark")
          .font(.system(size: 9, weight: .medium))
          .foregroundColor(.secondary)
      }
      .buttonStyle(.plain)
      .opacity(isActive ? 1 : 0.5)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(isActive ? Color(.controlBackgroundColor) : Color.clear)
    .cornerRadius(6)
    .contentShape(Rectangle())
    .onTapGesture {
      appState.switchToTab(id: tab.id)
    }
  }
}

/// Button to create a new tab.
struct NewTabButton: View {
  @Environment(AppState.self) private var appState

  var body: some View {
    Button {
      appState.showNewTabModal()
    } label: {
      Image(systemName: "plus")
        .font(.system(size: 12, weight: .medium))
        .foregroundColor(.secondary)
    }
    .buttonStyle(.plain)
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
  }
}

#Preview {
  TabBarView()
    .environment(AppState())
}
