import SwiftUI

/// Container that wraps the sidebar tab strip and the active sidebar panel.
/// Workspaces are always visible at the top (half the height), with the
/// switchable tab content filling the remaining space below.
struct SidebarContainerView: View {
  @Environment(AppState.self) private var appState
  private var configManager = ConfigManager.shared

  private var selectedTab: SidebarTab {
    configManager.config.sidebarTab
  }

  private var sidebarPosition: SidebarPosition {
    configManager.config.sidebarPosition
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
    HStack(spacing: 0) {
      if sidebarPosition == .left {
        tabStrip
        Divider()
        sidebarContent
      } else {
        sidebarContent
        Divider()
        tabStrip
      }
    }
  }

  private var sidebarContent: some View {
    GeometryReader { geometry in
      VStack(spacing: 0) {
        WorkspacesSidebarView()
          .frame(maxHeight: geometry.size.height / 2)
          .clipped()

        Divider()

        contentPanel
      }
    }
  }
}

/// Vertical icon-only tab strip on the sidebar's leading edge.
struct SidebarTabStrip: View {
  let selectedTab: SidebarTab
  let onSelect: (SidebarTab) -> Void
  let onOpenGitClient: () -> Void

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

      /// Visually separates the panel-selector icons above from the
      /// action button below — the Git Client button opens a tab,
      /// it does not switch the sidebar panel.
      Rectangle()
        .fill(Color.primary.opacity(0.12))
        .frame(width: 18, height: 1)
        .padding(.vertical, 6)

      SidebarActionIcon(
        iconName: "arrow.triangle.branch",
        tooltip: "Git Client",
        action: onOpenGitClient
      )

      Spacer()
    }
    .padding(.vertical, 8)
    .padding(.horizontal, 4)
    .frame(minWidth: 36, idealWidth: 36)
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

/// A single icon button in the sidebar tab strip.
struct SidebarTabIcon: View {
  let tab: SidebarTab
  let isSelected: Bool
  let action: () -> Void

  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      Image(systemName: tab.iconName)
        .appFont(size: 14)
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
