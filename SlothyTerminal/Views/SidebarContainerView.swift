import SwiftUI

/// Container that stacks the workspaces panel, the sidebar tab selector, and
/// the active sidebar panel. Workspaces are always visible at the top (half the
/// height); the selector row sits at the midpoint, directly above the
/// switchable tab content that fills the remaining space below.
struct SidebarContainerView: View {
  @Environment(AppState.self) private var appState
  private var configManager = ConfigManager.shared

  private var selectedTab: SidebarTab {
    configManager.config.sidebarTab
  }

  private var tabStrip: some View {
    SidebarTabStrip(
      selectedTab: selectedTab,
      onSelect: { tab in
        configManager.config.sidebarTab = tab
      },
      onOpenGitClient: {
        appState.openGitClientTab()
      }
    )
  }

  private var contentPanel: some View {
    Group {
      switch selectedTab {
      case .explorer:
        SidebarView()

      case .prompts:
        PromptsSidebarView()

      case .automation:
        AutomationSidebarView()
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  var body: some View {
    GeometryReader { geometry in
      VStack(spacing: 0) {
        WorkspacesSidebarView()
          .frame(maxHeight: geometry.size.height / 2)
          .clipped()

        Divider()

        tabStrip

        Divider()

        contentPanel
      }
    }
  }
}

/// Horizontal tab selector shown between the workspaces panel and the active
/// sidebar panel. Holds the panel-selector buttons on the leading edge and the
/// Git Client action on the trailing edge — the latter opens a tab, it does not
/// switch the sidebar panel.
struct SidebarTabStrip: View {
  let selectedTab: SidebarTab
  let onSelect: (SidebarTab) -> Void
  let onOpenGitClient: () -> Void

  var body: some View {
    HStack(spacing: 4) {
      ForEach(SidebarTab.allCases) { tab in
        SidebarTabButton(
          tab: tab,
          isSelected: tab == selectedTab
        ) {
          onSelect(tab)
        }
      }

      Spacer()

      SidebarActionIcon(
        iconName: "arrow.triangle.branch",
        tooltip: "Git Client",
        action: onOpenGitClient
      )
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    .background(appBackgroundColor)
  }
}

/// A non-toggle action button shown in the sidebar tab strip.
struct SidebarActionIcon: View {
  let iconName: String
  let tooltip: String
  let action: () -> Void

  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      Image(systemName: iconName)
        .appFont(size: 14)
        .foregroundColor(.secondary)
        .frame(width: 28, height: 28)
        .background(
          isHovered ? Color.primary.opacity(0.05) : Color.clear
        )
        .cornerRadius(6)
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      isHovered = hovering
    }
    .help(tooltip)
  }
}

/// A labeled panel-selector button in the horizontal sidebar tab strip.
struct SidebarTabButton: View {
  let tab: SidebarTab
  let isSelected: Bool
  let action: () -> Void

  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 5) {
        Image(systemName: tab.iconName)
          .appFont(size: 12)

        Text(tab.title)
          .appFont(size: 12)
      }
      .foregroundColor(isSelected ? .primary : .secondary)
      .padding(.horizontal, 8)
      .frame(height: 26)
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
