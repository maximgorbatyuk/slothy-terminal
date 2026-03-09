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

  /// Reserved width for the new-tab button (icon + horizontal padding).
  private let newTabButtonWidth: CGFloat = 36

  var body: some View {
    VStack(spacing: 0) {
      GeometryReader { geo in
        HStack(spacing: 0) {
          let tabCount = appState.visibleTabs.count
          let tabWidth = tabCount > 0
            ? max(0, geo.size.width - newTabButtonWidth) / CGFloat(tabCount)
            : 0

          /// Tab items.
          ForEach(appState.visibleTabs) { tab in
            TabItemView(tab: tab, width: tabWidth)
          }

          /// New tab button.
          NewTabButton()
            .frame(width: newTabButtonWidth)
        }
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
  let width: CGFloat
  @Environment(AppState.self) private var appState

  private var isActive: Bool {
    appState.activeTabID == tab.id
  }

  private var tabIconName: String {
    if tab.mode == .chat {
      return "bubble.left.and.bubble.right"
    }

    return tab.agentType.iconName
  }

  var body: some View {
    HStack(spacing: 6) {
      tabLeadingIcon

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
    .frame(width: width)
    .background(isActive ? appCardColor : Color.clear)
    .cornerRadius(6)
    .contentShape(Rectangle())
    .onTapGesture {
      appState.switchToTab(id: tab.id)
    }
  }

  @ViewBuilder
  private var tabLeadingIcon: some View {
    ZStack(alignment: .topTrailing) {
      Group {
        if tab.isExecuting {
          ExecutingIndicator(color: isActive ? tab.agentType.accentColor : .gray)
        } else {
          Image(systemName: tabIconName)
            .foregroundColor(isActive ? tab.agentType.accentColor : .gray)
            .font(.system(size: 12))
        }
      }
      .frame(width: 12, height: 12)

      if tab.hasBackgroundActivity && !isActive && !tab.isExecuting {
        BackgroundActivityIndicator()
          .offset(x: 4, y: -4)
      }
    }
    .frame(width: 14, height: 14)
  }
}

/// Button to create a new tab.
struct NewTabButton: View {
  @Environment(AppState.self) private var appState

  var body: some View {
    Button {
      appState.showStartupPage()
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

/// Small dot shown when an inactive terminal tab has unseen output.
struct BackgroundActivityIndicator: View {
  @State private var isPulsing = false

  var body: some View {
    Circle()
      .fill(Color(nsColor: .systemOrange))
      .overlay {
        Circle()
          .stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1)
      }
      .frame(width: 7, height: 7)
      .scaleEffect(isPulsing ? 0.82 : 1.0)
      .opacity(isPulsing ? 0.75 : 1.0)
      .animation(
        .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
        value: isPulsing
      )
      .onAppear {
        isPulsing = true
      }
      .help("New terminal activity")
  }
}

/// Pulsing circle indicator shown on tabs during active execution.
struct ExecutingIndicator: View {
  let color: Color
  @State private var isPulsing = false

  var body: some View {
    Circle()
      .fill(color)
      .frame(width: 8, height: 8)
      .scaleEffect(isPulsing ? 0.6 : 1.0)
      .opacity(isPulsing ? 0.4 : 1.0)
      .frame(width: 12, height: 12)
      .animation(
        .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
        value: isPulsing
      )
      .onAppear {
        isPulsing = true
      }
  }
}

#Preview {
  TabBarView()
    .environment(AppState())
}
