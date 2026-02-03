import AppKit
import Combine
import SwiftUI

/// The sidebar showing usage statistics for the active tab.
struct SidebarView: View {
  @Environment(AppState.self) private var appState

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {

      if let tab = appState.activeTab {
        if tab.agentType.showsUsageStats {
          ScrollView {
            AgentStatsView(tab: tab)
          }
        } else {
          TerminalSidebarView(tab: tab)
        }
      } else {
        EmptySidebarView()
      }

      Spacer()
    }
    .padding()
    .background(appBackgroundColor)
  }
}

/// Empty state when no tab is active.
struct EmptySidebarView: View {
  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: "chart.bar")
        .font(.system(size: 32))
        .foregroundColor(.secondary)

      Text("No active session")
        .font(.system(size: 12))
        .foregroundColor(.secondary)

      Text("Create a tab to view usage statistics")
        .font(.system(size: 11))
        .foregroundColor(.secondary)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding()
  }
}

/// Sidebar view for plain terminal tabs (no stats).
struct TerminalSidebarView: View {
  let tab: Tab

  var body: some View {
    VStack(spacing: 16) {
      /// Working directory.
      WorkingDirectoryCard(path: tab.workingDirectory)

      /// Open in external app button.
      OpenInAppButton(directory: tab.workingDirectory)

      Spacer()

      /// Info text.
      VStack(spacing: 8) {
        Image(systemName: "info.circle")
          .font(.system(size: 24))
          .foregroundColor(.secondary)

        Text("Plain terminal session")
          .font(.system(size: 11))
          .foregroundColor(.secondary)

        Text("Usage statistics are available for AI agent tabs")
          .font(.system(size: 10))
          .foregroundColor(.secondary)
          .multilineTextAlignment(.center)
      }
      .padding()

      Spacer()
    }
  }
}

/// Displays statistics for an agent session.
struct AgentStatsView: View {
  let tab: Tab
  @State private var currentTime = Date()

  /// Timer to update duration every second.
  private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      /// Working directory.
      WorkingDirectoryCard(path: tab.workingDirectory)

      /// Open in external app button.
      OpenInAppButton(directory: tab.workingDirectory)

      /// Session info section.
      StatsSection(title: "Session Info") {
        StatRow(label: "Duration", value: formattedDuration)
        StatRow(label: "Commands", value: "\(tab.usageStats.commandCount)")
      }
    }
    .onReceive(timer) { _ in
      currentTime = Date()
    }
  }

  /// Formatted duration that updates with the timer.
  private var formattedDuration: String {
    let totalSeconds = Int(currentTime.timeIntervalSince(tab.usageStats.startTime))
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60

    if hours > 0 {
      return String(format: "%dh %02dm %02ds", hours, minutes, seconds)
    } else {
      return String(format: "%dm %02ds", minutes, seconds)
    }
  }
}

/// Card showing the current working directory.
struct WorkingDirectoryCard: View {
  let path: URL

  private var displayPath: String {
    let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
    let fullPath = path.path

    if fullPath.hasPrefix(homeDir) {
      return "~" + fullPath.dropFirst(homeDir.count)
    }
    return fullPath
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 4) {
        Image(systemName: "folder.fill")
          .font(.system(size: 10))
          .foregroundColor(.secondary)

        Text("Working Directory")
          .font(.system(size: 10, weight: .medium))
          .foregroundColor(.secondary)
      }

      Text(displayPath)
        .font(.system(size: 11))
        .lineLimit(2)
        .truncationMode(.middle)
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(appCardColor)
    .cornerRadius(8)
  }
}

/// Button that shows a dropdown menu of installed developer apps.
struct OpenInAppButton: View {
  let directory: URL

  private var installedApps: [ExternalApp] {
    ExternalAppManager.shared.installedApps
  }

  var body: some View {
    if !installedApps.isEmpty {
      Menu {
        ForEach(installedApps) { app in
          Button {
            ExternalAppManager.shared.openDirectory(directory, in: app)
          } label: {
            if let appIcon = app.appIcon {
              Label {
                Text(app.name)
              } icon: {
                Image(nsImage: appIcon)
              }
            } else {
              Label(app.name, systemImage: app.icon)
            }
          }
        }
      } label: {
        HStack {
          Image(systemName: "arrow.up.forward.app")
          Text("Open in...")
          Spacer()
          Image(systemName: "chevron.down")
        }
        .font(.system(size: 11))
        .padding(10)
        .background(appCardColor)
        .cornerRadius(8)
      }
      .menuStyle(.borderlessButton)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

/// A section of statistics with a title.
struct StatsSection<Content: View>: View {
  let title: String
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.system(size: 10, weight: .semibold))
        .textCase(.uppercase)
        .foregroundColor(.secondary)

      VStack(spacing: 6) {
        content
      }
      .padding(10)
      .background(appCardColor)
      .cornerRadius(8)
    }
  }
}

/// Style for stat row values.
enum StatRowStyle {
  case normal
  case cost
  case warning
}

/// A single row displaying a stat label and value.
struct StatRow: View {
  let label: String
  let value: String
  var isHighlighted: Bool = false
  var style: StatRowStyle = .normal

  private var valueColor: Color {
    switch style {
    case .normal:
      return isHighlighted ? .primary : .secondary
    case .cost:
      return .orange
    case .warning:
      return .red
    }
  }

  var body: some View {
    HStack {
      Text(label)
        .font(.system(size: 11))
        .foregroundColor(.secondary)

      Spacer()

      Text(value)
        .font(.system(size: 11, weight: isHighlighted ? .semibold : .regular))
        .foregroundColor(valueColor)
        .monospacedDigit()
    }
  }
}

/// Progress bar showing context window usage.
struct ContextWindowProgress: View {
  let used: Int
  let limit: Int

  private var percentage: Double {
    guard limit > 0 else {
      return 0
    }

    return Double(used) / Double(limit)
  }

  private var percentageText: String {
    String(format: "%.1f%%", percentage * 100)
  }

  private var usageText: String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.groupingSeparator = ","

    let usedStr = formatter.string(from: NSNumber(value: used)) ?? "\(used)"
    let limitStr = formatter.string(from: NSNumber(value: limit)) ?? "\(limit)"

    return "\(usedStr) / \(limitStr)"
  }

  private var progressColor: Color {
    if percentage > 0.9 {
      return .red
    } else if percentage > 0.7 {
      return .orange
    } else {
      return .green
    }
  }

  private var statusIcon: String {
    if percentage > 0.9 {
      return "exclamationmark.triangle.fill"
    } else if percentage > 0.7 {
      return "exclamationmark.circle.fill"
    } else {
      return "checkmark.circle.fill"
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Context Window")
          .font(.system(size: 10, weight: .semibold))
          .textCase(.uppercase)
          .foregroundColor(.secondary)

        Spacer()

        Image(systemName: statusIcon)
          .font(.system(size: 10))
          .foregroundColor(progressColor)
      }

      VStack(spacing: 8) {
        /// Progress bar.
        GeometryReader { geometry in
          ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4)
              .fill(appBackgroundColor)
              .frame(height: 8)

            RoundedRectangle(cornerRadius: 4)
              .fill(progressColor)
              .frame(width: geometry.size.width * min(percentage, 1.0), height: 8)
          }
        }
        .frame(height: 8)

        /// Usage details.
        HStack {
          Text(usageText)
            .font(.system(size: 10))
            .foregroundColor(.secondary)
            .monospacedDigit()

          Spacer()

          Text(percentageText)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(progressColor)
            .monospacedDigit()
        }
      }
      .padding(10)
      .background(appCardColor)
      .cornerRadius(8)
    }
  }
}

#Preview("With Active Tab") {
  let appState = AppState()
  let tab = Tab(agentType: .claude, workingDirectory: URL(fileURLWithPath: "/Users/demo/projects"))
  tab.usageStats.tokensIn = 12847
  tab.usageStats.tokensOut = 8234
  tab.usageStats.messageCount = 24
  tab.usageStats.estimatedCost = 0.0847
  appState.tabs.append(tab)
  appState.activeTabID = tab.id

  return SidebarView()
    .environment(appState)
    .frame(width: 260, height: 600)
}

#Preview("Empty State") {
  SidebarView()
    .environment(AppState())
    .frame(width: 260, height: 600)
}
