import SwiftUI

/// The sidebar showing usage statistics for the active tab.
struct SidebarView: View {
  @Environment(AppState.self) private var appState

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      /// Header.
      HStack {
        Text("Usage Statistics")
          .font(.system(size: 11, weight: .semibold))
          .textCase(.uppercase)
          .foregroundColor(.secondary)

        Spacer()

        Button {
          appState.toggleSidebar()
        } label: {
          Image(systemName: "chevron.right")
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
      }

      Divider()

      if let tab = appState.activeTab {
        AgentStatsView(tab: tab)
      } else {
        Text("No active tab")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Spacer()
    }
    .padding()
    .background(Color(.controlBackgroundColor))
  }
}

/// Displays statistics for an agent session.
struct AgentStatsView: View {
  let tab: Tab

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      /// Agent badge.
      HStack(spacing: 8) {
        Circle()
          .fill(tab.ptyController?.isRunning == true ? Color.green : Color.gray)
          .frame(width: 8, height: 8)

        Image(systemName: tab.agentType.iconName)
          .foregroundColor(tab.agentType.accentColor)

        Text("\(tab.agentType.rawValue) Active")
          .font(.system(size: 12, weight: .medium))
      }

      /// Working directory.
      WorkingDirectoryCard(path: tab.workingDirectory)

      /// Token usage section.
      StatsSection(title: "Token Usage") {
        StatRow(label: "Input Tokens", value: "\(tab.usageStats.tokensIn)")
        StatRow(label: "Output Tokens", value: "\(tab.usageStats.tokensOut)")
        StatRow(label: "Total", value: "\(tab.usageStats.totalTokens)", isHighlighted: true)
      }

      /// Session info section.
      StatsSection(title: "Session Info") {
        StatRow(label: "Messages", value: "\(tab.usageStats.messageCount)")
        StatRow(label: "Duration", value: tab.usageStats.formattedDuration)
        if let cost = tab.usageStats.estimatedCost {
          StatRow(label: "Est. Cost", value: String(format: "$%.4f", cost))
        }
      }

      /// Context window progress.
      ContextWindowProgress(
        used: tab.usageStats.totalTokens,
        limit: 200_000
      )
    }
  }
}

/// Card showing the current working directory.
struct WorkingDirectoryCard: View {
  let path: URL

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Working Directory")
        .font(.system(size: 10, weight: .medium))
        .foregroundColor(.secondary)

      Text(path.path)
        .font(.system(size: 11))
        .lineLimit(2)
        .truncationMode(.middle)
    }
    .padding(8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(.textBackgroundColor))
    .cornerRadius(6)
  }
}

/// A section of statistics with a title.
struct StatsSection<Content: View>: View {
  let title: String
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.system(size: 10, weight: .semibold))
        .textCase(.uppercase)
        .foregroundColor(.secondary)

      content
    }
  }
}

/// A single row displaying a stat label and value.
struct StatRow: View {
  let label: String
  let value: String
  var isHighlighted: Bool = false

  var body: some View {
    HStack {
      Text(label)
        .font(.system(size: 11))
        .foregroundColor(.secondary)

      Spacer()

      Text(value)
        .font(.system(size: 11, weight: isHighlighted ? .semibold : .regular))
        .monospacedDigit()
    }
  }
}

/// Progress bar showing context window usage.
struct ContextWindowProgress: View {
  let used: Int
  let limit: Int

  private var percentage: Double {
    Double(used) / Double(limit)
  }

  private var percentageText: String {
    String(format: "%.1f%%", percentage * 100)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Context Window")
        .font(.system(size: 10, weight: .semibold))
        .textCase(.uppercase)
        .foregroundColor(.secondary)

      GeometryReader { geometry in
        ZStack(alignment: .leading) {
          RoundedRectangle(cornerRadius: 4)
            .fill(Color(.separatorColor))
            .frame(height: 8)

          RoundedRectangle(cornerRadius: 4)
            .fill(progressColor)
            .frame(width: geometry.size.width * min(percentage, 1.0), height: 8)
        }
      }
      .frame(height: 8)

      Text(percentageText)
        .font(.system(size: 10))
        .foregroundColor(.secondary)
    }
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
}

#Preview {
  SidebarView()
    .environment(AppState())
    .frame(width: 260)
}
