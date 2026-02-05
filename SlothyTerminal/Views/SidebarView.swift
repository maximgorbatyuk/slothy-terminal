import AppKit
import Combine
import SwiftUI

/// The sidebar showing usage statistics for the active tab.
struct SidebarView: View {
  @Environment(AppState.self) private var appState

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {

      if let tab = appState.activeTab {
        if tab.mode == .chat, let chatState = tab.chatState {
          ScrollView {
            ChatSidebarView(tab: tab, chatState: chatState)
          }
        } else if tab.agentType.showsUsageStats {
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

/// Sidebar view for plain terminal tabs.
struct TerminalSidebarView: View {
  let tab: Tab
  @State private var currentTime = Date()

  /// Timer to update duration every second.
  private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

  var body: some View {
    VStack(spacing: 16) {
      /// Working directory.
      WorkingDirectoryCard(path: tab.workingDirectory)

      /// Open in external app button.
      OpenInAppButton(directory: tab.workingDirectory)

      /// Directory tree.
      DirectoryTreeView(rootDirectory: tab.workingDirectory)

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

      /// Directory tree.
      DirectoryTreeView(rootDirectory: tab.workingDirectory)

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

/// Collapsible directory tree showing files and folders.
struct DirectoryTreeView: View {
  let rootDirectory: URL
  @State private var isExpanded: Bool = true
  @State private var items: [FileItem] = []

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      /// Header with expand/collapse toggle.
      Button {
        isExpanded.toggle()
      } label: {
        HStack {
          Image(systemName: "folder.fill")
            .font(.system(size: 10))

          Text("Files")
            .font(.system(size: 10, weight: .semibold))

          Spacer()

          Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
            .font(.system(size: 10))
        }
        .foregroundColor(.secondary)
      }
      .buttonStyle(.plain)

      if isExpanded {
        /// Hint text.
        Text("Double-click to copy path. Right-click for more options.")
          .font(.system(size: 9))
          .foregroundColor(.secondary)
          .opacity(0.7)

        /// Tree content in a card.
        ScrollView {
          VStack(alignment: .leading, spacing: 0) {
            if items.isEmpty {
              Text("No files")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .padding(.vertical, 8)
            } else {
              ForEach(Array(items.indices), id: \.self) { index in
                FileItemRow(item: $items[index], depth: 0, rootDirectory: rootDirectory)
              }
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 300)
        .padding(10)
        .background(appCardColor)
        .cornerRadius(8)
      }
    }
    .onAppear {
      loadItems()
    }
    .onChange(of: rootDirectory) {
      loadItems()
    }
  }

  private func loadItems() {
    items = DirectoryTreeManager.shared.scanDirectory(rootDirectory)
  }
}

/// A single row in the directory tree representing a file or folder.
struct FileItemRow: View {
  @Binding var item: FileItem
  let depth: Int
  let rootDirectory: URL
  @State private var showCopiedTooltip: Bool = false

  /// Relative path from the root directory.
  private var relativePath: String {
    let fullPath = item.url.path
    let rootPath = rootDirectory.path

    if fullPath.hasPrefix(rootPath) {
      let relative = String(fullPath.dropFirst(rootPath.count))
      if relative.hasPrefix("/") {
        return String(relative.dropFirst())
      }
      return relative.isEmpty ? item.name : relative
    }

    return item.name
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 4) {
        /// Indentation based on depth.
        if depth > 0 {
          Spacer()
            .frame(width: CGFloat(depth) * 12)
        }

        /// Expand/collapse chevron for directories.
        if item.isDirectory {
          Image(systemName: item.isExpanded ? "chevron.down" : "chevron.right")
            .font(.system(size: 8))
            .foregroundColor(.secondary)
            .frame(width: 10)
        } else {
          Spacer()
            .frame(width: 10)
        }

        /// File/folder icon.
        Image(nsImage: item.icon)
          .resizable()
          .frame(width: 14, height: 14)

        /// Name.
        Text(item.name)
          .font(.system(size: 11))
          .lineLimit(1)
          .truncationMode(.middle)

        Spacer()
      }
      .padding(.vertical, 3)
      .contentShape(Rectangle())
      .onTapGesture(count: 1) {
        if item.isDirectory {
          toggleExpand()
        }
      }
      .onTapGesture(count: 2) {
        copyToClipboard(relativePath)
      }
      .contextMenu {
        Button("Copy Relative Path") {
          copyToClipboard(relativePath)
        }

        Button("Copy Filename") {
          copyToClipboard(item.name)
        }

        Button("Copy Full Path") {
          copyToClipboard(item.url.path)
        }
      }
      .overlay(alignment: .trailing) {
        if showCopiedTooltip {
          Text("Copied!")
            .font(.system(size: 9))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.green.opacity(0.9))
            .foregroundColor(.white)
            .cornerRadius(4)
            .transition(.opacity)
        }
      }

      /// Render children if expanded.
      if item.isDirectory && item.isExpanded, let children = item.children {
        ForEach(Array(children.indices), id: \.self) { index in
          FileItemRow(
            item: Binding(
              get: { item.children![index] },
              set: { item.children![index] = $0 }
            ),
            depth: depth + 1,
            rootDirectory: rootDirectory
          )
        }
      }
    }
  }

  private func toggleExpand() {
    item.isExpanded.toggle()

    if item.isExpanded && item.children == nil {
      item.children = DirectoryTreeManager.shared.loadChildren(for: item)
    }
  }

  private func copyToClipboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)

    withAnimation {
      showCopiedTooltip = true
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
      withAnimation {
        showCopiedTooltip = false
      }
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

/// Sidebar view for chat-mode tabs.
struct ChatSidebarView: View {
  let tab: Tab
  let chatState: ChatState
  @State private var currentTime = Date()

  private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      /// Working directory.
      WorkingDirectoryCard(path: tab.workingDirectory)

      /// Open in external app button.
      OpenInAppButton(directory: tab.workingDirectory)

      /// Directory tree.
      DirectoryTreeView(rootDirectory: tab.workingDirectory)

      /// Chat stats section.
      StatsSection(title: "Chat Info") {
        StatRow(label: "Messages", value: "\(chatState.conversation.messages.count)")
        StatRow(label: "Duration", value: formattedDuration)
      }

      /// Token usage section.
      StatsSection(title: "Token Usage") {
        StatRow(
          label: "Input",
          value: formatNumber(chatState.conversation.totalInputTokens),
          isHighlighted: chatState.conversation.totalInputTokens > 0
        )
        StatRow(
          label: "Output",
          value: formatNumber(chatState.conversation.totalOutputTokens),
          isHighlighted: chatState.conversation.totalOutputTokens > 0
        )
      }
    }
    .onReceive(timer) { _ in
      currentTime = Date()
    }
  }

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

  private func formatNumber(_ value: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.groupingSeparator = ","
    return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
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
