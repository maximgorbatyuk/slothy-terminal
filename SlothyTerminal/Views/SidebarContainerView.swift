import SwiftUI

/// Container that wraps the sidebar tab strip and the active sidebar panel.
struct SidebarContainerView: View {
  private var configManager = ConfigManager.shared

  private var selectedTab: SidebarTab {
    configManager.config.sidebarTab
  }

  private var sidebarPosition: SidebarPosition {
    configManager.config.sidebarPosition
  }

  private var tabStrip: some View {
    SidebarTabStrip(selectedTab: selectedTab) { tab in
      configManager.config.sidebarTab = tab
    }
  }

  private var contentPanel: some View {
    Group {
      switch selectedTab {
      case .explorer:
        SidebarView()

      case .gitChanges:
        GitChangesView()

      case .automation:
        AutomationPlaceholderView()
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  var body: some View {
    HStack(spacing: 0) {
      if sidebarPosition == .left {
        tabStrip
        Divider()
        contentPanel
      } else {
        contentPanel
        Divider()
        tabStrip
      }
    }
  }
}

/// Vertical icon-only tab strip on the sidebar's leading edge.
struct SidebarTabStrip: View {
  let selectedTab: SidebarTab
  let onSelect: (SidebarTab) -> Void

  var body: some View {
    VStack(spacing: 2) {
      ForEach(SidebarTab.allCases) { tab in
        SidebarTabIcon(
          tab: tab,
          isSelected: tab == selectedTab
        ) {
          onSelect(tab)
        }
      }

      Spacer()
    }
    .padding(.vertical, 8)
    .padding(.horizontal, 4)
    .frame(width: 36)
    .background(appBackgroundColor)
  }
}

/// A single icon button in the sidebar tab strip.
struct SidebarTabIcon: View {
  let tab: SidebarTab
  let isSelected: Bool
  let action: () -> Void

  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      Image(systemName: tab.iconName)
        .font(.system(size: 14))
        .foregroundColor(isSelected ? .primary : .secondary)
        .frame(width: 28, height: 28)
        .background(
          isSelected
            ? appCardColor
            : isHovered ? Color.primary.opacity(0.05) : Color.clear
        )
        .cornerRadius(6)
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      isHovered = hovering
    }
    .help(tab.tooltip)
  }
}
