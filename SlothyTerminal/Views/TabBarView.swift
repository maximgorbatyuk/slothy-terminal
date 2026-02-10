import SwiftUI

/// App theme color — adaptive for light/dark appearance.
var appBackgroundColor: Color {
  Color(nsColor: NSColor(name: nil) { appearance in
    if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
      return NSColor(red: 40/255, green: 44/255, blue: 52/255, alpha: 1)
    } else {
      return NSColor(red: 246/255, green: 246/255, blue: 248/255, alpha: 1)
    }
  })
}

/// Slightly lighter variant for cards/controls — adaptive for light/dark appearance.
var appCardColor: Color {
  Color(nsColor: NSColor(name: nil) { appearance in
    if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
      return NSColor(red: 50/255, green: 54/255, blue: 62/255, alpha: 1)
    } else {
      return NSColor(red: 255/255, green: 255/255, blue: 255/255, alpha: 1)
    }
  })
}

/// The tab bar displaying all open terminal tabs.
struct TabBarView: View {
  @Environment(AppState.self) private var appState

  var body: some View {
    VStack(spacing: 0) {
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

      /// Divider line between tab bar and content.
      Divider()
    }
    .background(appBackgroundColor)
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
      /// Agent icon — chat mode uses a chat bubble icon.
      Image(systemName: tab.mode == .chat ? "bubble.left.and.bubble.right" : tab.agentType.iconName)
        .foregroundColor(isActive ? tab.agentType.accentColor : .gray)
        .font(.system(size: 12))

      /// Tab title.
      Text(tab.tabName)
        .font(.system(size: 12))
        .foregroundColor(isActive ? .primary : .gray)
        .lineLimit(1)

      /// Close button.
      Button {
        appState.closeTab(id: tab.id)
      } label: {
        Image(systemName: "xmark")
          .font(.system(size: 9, weight: .medium))
          .foregroundColor(.gray)
      }
      .buttonStyle(.plain)
      .opacity(isActive ? 1 : 0.5)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(isActive ? appCardColor : Color.clear)
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
