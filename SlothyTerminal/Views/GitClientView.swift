import SwiftUI

/// Content view for Git client tabs.
/// Shows a sub-tab picker (Overview, Changes) when a Git repo exists,
/// or a "no repo" message otherwise.
struct GitClientView: View {
  let workingDirectory: URL

  @State private var isGitRepository: Bool?
  @State private var selectedTab: GitTab = .overview

  var body: some View {
    Group {
      switch isGitRepository {
      case .some(true):
        repoContent

      case .some(false):
        noRepoMessage

      case nil:
        ProgressView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .background(appBackgroundColor)
    .task {
      let exists = await GitStatsService.shared.isGitRepository(in: workingDirectory)
      isGitRepository = exists
    }
  }

  // MARK: - Repo Content

  private var repoContent: some View {
    VStack(spacing: 0) {
      tabStrip
      Divider()

      Group {
        switch selectedTab {
        case .overview:
          GitOverviewContentView(workingDirectory: workingDirectory)

        case .revisionGraph:
          RevisionGraphView(workingDirectory: workingDirectory)

        case .commit:
          GitStubContentView(tab: .commit)

        case .comingSoon1, .comingSoon2:
          GitStubContentView(tab: selectedTab)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  // MARK: - Tab Strip

  private var tabStrip: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 0) {
        ForEach(GitTab.allCases) { tab in
          GitTabButton(
            tab: tab,
            isSelected: selectedTab == tab
          ) {
            selectedTab = tab
          }
        }
      }
      .padding(.horizontal, 12)
    }
    .padding(.vertical, 6)
    .background(appBackgroundColor)
  }

  // MARK: - No Repo

  private var noRepoMessage: some View {
    VStack(spacing: 12) {
      Image(systemName: "folder.badge.questionmark")
        .font(.system(size: 48))
        .foregroundColor(.secondary.opacity(0.6))

      Text("No Git Repository")
        .font(.title2)
        .fontWeight(.semibold)

      Text("The selected directory is not a Git repository.")
        .font(.subheadline)
        .foregroundColor(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 320)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

// MARK: - Overview Content

/// The Overview sub-tab: repo header, summary stats, author stats, activity heatmap.
struct GitOverviewContentView: View {
  let workingDirectory: URL

  @State private var summary: RepositorySummary?
  @State private var authorStats: [AuthorStats] = []
  @State private var dailyActivity: [DailyActivity] = []
  @State private var activityMap: [Date: Int] = [:]
  @State private var activityWeeks: [[Date?]] = []
  @State private var isLoading = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if isLoading && summary == nil {
        ProgressView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if let summary {
        ScrollView {
          VStack(alignment: .leading, spacing: 20) {
            repoHeader(summary: summary)
            summarySection(summary: summary)

            if !authorStats.isEmpty {
              authorStatsSection
            }

            if !dailyActivity.isEmpty {
              activitySection
            }
          }
          .padding(24)
          .frame(maxWidth: 720, alignment: .leading)
          .frame(maxWidth: .infinity)
        }
      }
    }
    .task {
      await loadStats()
    }
  }

  // MARK: - Header

  private func repoHeader(summary: RepositorySummary) -> some View {
    HStack(spacing: 10) {
      Image(systemName: "arrow.triangle.branch")
        .font(.system(size: 14))
        .foregroundColor(.orange.opacity(0.7))

      Text(workingDirectory.lastPathComponent)
        .font(.system(size: 14, weight: .semibold))
        .lineLimit(1)

      if let branch = summary.currentBranch {
        Text(branch)
          .font(.system(size: 10, weight: .medium, design: .monospaced))
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(Color.accentColor.opacity(0.15))
          .cornerRadius(4)
      }

      Spacer()

      Button {
        Task {
          await loadStats()
        }
      } label: {
        Image(systemName: "arrow.clockwise")
          .font(.system(size: 11))
          .foregroundColor(.secondary)
      }
      .buttonStyle(.plain)
      .help("Refresh")
    }
  }

  // MARK: - Summary

  private func summarySection(summary: RepositorySummary) -> some View {
    StatsSection(title: "Overview") {
      StatRow(
        label: "Total commits",
        value: formatNumber(summary.totalCommits),
        isHighlighted: true
      )
      StatRow(
        label: "Authors",
        value: "\(summary.totalAuthors)"
      )

      if let firstDate = summary.firstCommitDate {
        StatRow(label: "Repository age", value: repoAge(since: firstDate))
      }
    }
  }

  // MARK: - Author Stats

  private var authorStatsSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("User Stats")
        .font(.system(size: 10, weight: .semibold))
        .textCase(.uppercase)
        .foregroundColor(.secondary)

      VStack(spacing: 0) {
        ForEach(Array(authorStats.enumerated()), id: \.element.id) { index, author in
          AuthorStatRow(
            rank: index + 1,
            author: author,
            maxCommits: authorStats.first?.commitCount ?? 1
          )

          if index < authorStats.count - 1 {
            Divider()
              .padding(.horizontal, 6)
          }
        }
      }
      .padding(6)
      .background(appCardColor)
      .cornerRadius(8)
    }
  }

  // MARK: - Activity Table

  private var activitySection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Activity")
        .font(.system(size: 10, weight: .semibold))
        .textCase(.uppercase)
        .foregroundColor(.secondary)

      ScrollView(.horizontal, showsIndicators: false) {
        ActivityHeatmapGrid(activityMap: activityMap, weeks: activityWeeks)
      }
      .padding(10)
      .background(appCardColor)
      .cornerRadius(8)
    }
  }

  // MARK: - Data Loading

  private func loadStats() async {
    isLoading = true

    let service = GitStatsService.shared

    async let summaryResult = service.getRepositorySummary(in: workingDirectory)
    async let authorsResult = service.getAuthorStats(in: workingDirectory)
    async let activityResult = service.getDailyActivity(in: workingDirectory)

    summary = await summaryResult
    authorStats = await authorsResult
    dailyActivity = await activityResult

    let grid = ActivityHeatmapGrid.precompute(from: dailyActivity)
    activityMap = grid.activityMap
    activityWeeks = grid.weeks

    isLoading = false
  }

  // MARK: - Formatting

  private static let numberFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.groupingSeparator = ","
    return formatter
  }()

  private func formatNumber(_ value: Int) -> String {
    Self.numberFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
  }

  private func repoAge(since date: Date) -> String {
    let components = Calendar.current.dateComponents(
      [.year, .month, .day],
      from: date,
      to: Date()
    )

    if let years = components.year, years > 0 {
      if let months = components.month, months > 0 {
        return "\(years)y \(months)mo"
      }

      return "\(years)y"
    }

    if let months = components.month, months > 0 {
      return "\(months)mo"
    }

    if let days = components.day, days > 0 {
      return "\(days)d"
    }

    return "today"
  }
}

// MARK: - Author Stat Row

/// A single row showing author rank, name, email, commit count, and proportional bar.
struct AuthorStatRow: View {
  let rank: Int
  let author: AuthorStats
  let maxCommits: Int

  private var proportion: CGFloat {
    guard maxCommits > 0 else {
      return 0
    }

    return CGFloat(author.commitCount) / CGFloat(maxCommits)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 6) {
        Text("#\(rank)")
          .font(.system(size: 9, weight: .medium, design: .monospaced))
          .foregroundColor(.secondary)
          .frame(width: 20, alignment: .trailing)

        VStack(alignment: .leading, spacing: 1) {
          Text(author.name)
            .font(.system(size: 11, weight: .medium))
            .lineLimit(1)

          if !author.email.isEmpty {
            Text(author.email)
              .font(.system(size: 9))
              .foregroundColor(.secondary)
              .lineLimit(1)
          }
        }

        Spacer()

        Text("\(author.commitCount)")
          .font(.system(size: 11, design: .monospaced))
          .foregroundColor(.secondary)
      }

      GeometryReader { geo in
        RoundedRectangle(cornerRadius: 2)
          .fill(Color.green.opacity(0.4))
          .frame(width: geo.size.width * proportion, height: 3)
      }
      .frame(height: 3)
    }
    .padding(.vertical, 4)
    .padding(.horizontal, 4)
  }
}

// MARK: - Activity Heatmap Grid

/// Grid rendering daily commit activity as colored cells (rows = weekdays, columns = weeks).
struct ActivityHeatmapGrid: View {
  let activityMap: [Date: Int]
  let weeks: [[Date?]]

  private let cellSize: CGFloat = 12
  private let cellSpacing: CGFloat = 2
  private let dayLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

  private static let monthFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM"
    return formatter
  }()

  private static let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    return formatter
  }()

  /// Creates the activity map and week grid from raw daily activity data.
  /// Call once when data changes, not on every body evaluation.
  static func precompute(
    from dailyActivity: [DailyActivity]
  ) -> (activityMap: [Date: Int], weeks: [[Date?]]) {
    let map = Dictionary(uniqueKeysWithValues: dailyActivity.map { ($0.date, $0.commitCount) })
    return (map, buildWeeks())
  }

  /// Generates the full grid of weeks (columns) x weekdays (rows).
  private static func buildWeeks() -> [[Date?]] {
    let calendar = Calendar(identifier: .iso8601)
    let today = calendar.startOfDay(for: Date())

    guard let startDate = calendar.date(byAdding: .weekOfYear, value: -11, to: today) else {
      return []
    }

    // Align to Monday of that week.
    let weekday = calendar.component(.weekday, from: startDate)
    let mondayOffset = (weekday == 1) ? -6 : (2 - weekday)

    guard let firstMonday = calendar.date(byAdding: .day, value: mondayOffset, to: startDate) else {
      return []
    }

    var result: [[Date?]] = []
    var currentDate = firstMonday

    while currentDate <= today {
      var week: [Date?] = []
      for _ in 0..<7 {
        if currentDate <= today {
          week.append(currentDate)
        } else {
          week.append(nil)
        }

        guard let next = calendar.date(byAdding: .day, value: 1, to: currentDate) else {
          break
        }

        currentDate = next
      }

      result.append(week)
    }

    return result
  }

  var body: some View {
    HStack(alignment: .top, spacing: cellSpacing) {
      // Day labels column.
      VStack(spacing: cellSpacing) {
        // Empty spacer for header row alignment.
        Text("")
          .font(.system(size: 8))
          .frame(width: 22, height: cellSize)

        ForEach(0..<7, id: \.self) { dayIndex in
          Text(dayLabels[dayIndex])
            .font(.system(size: 8))
            .foregroundColor(.secondary)
            .frame(width: 22, height: cellSize, alignment: .trailing)
        }
      }

      // Week columns.
      ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
        VStack(spacing: cellSpacing) {
          // Week header (month label for first week of each month).
          Text(weekHeader(for: week))
            .font(.system(size: 8))
            .foregroundColor(.secondary)
            .frame(height: cellSize)

          ForEach(0..<7, id: \.self) { dayIndex in
            if dayIndex < week.count, let date = week[dayIndex] {
              let count = activityMap[date] ?? 0
              activityCell(count: count)
                .help("\(Self.dateFormatter.string(from: date)): \(count) commit\(count == 1 ? "" : "s")")
            } else {
              Color.clear
                .frame(width: cellSize, height: cellSize)
            }
          }
        }
      }
    }
  }

  private func activityCell(count: Int) -> some View {
    RoundedRectangle(cornerRadius: 2)
      .fill(cellColor(for: count))
      .frame(width: cellSize, height: cellSize)
  }

  private func cellColor(for count: Int) -> Color {
    switch count {
    case 0:
      return Color.secondary.opacity(0.1)

    case 1...2:
      return Color.green.opacity(0.3)

    case 3...5:
      return Color.green.opacity(0.55)

    case 6...9:
      return Color.green.opacity(0.75)

    default:
      return Color.green.opacity(1.0)
    }
  }

  private func weekHeader(for week: [Date?]) -> String {
    guard let wrappedFirst = week.first,
          let firstDay = wrappedFirst
    else {
      return ""
    }

    let calendar = Calendar.current
    let day = calendar.component(.day, from: firstDay)

    // Show month abbreviation if this week contains the 1st-7th of a month.
    if day <= 7 {
      return Self.monthFormatter.string(from: firstDay)
    }

    return ""
  }
}

// MARK: - Git Tab Button

/// A single button in the Git sub-tab strip.
struct GitTabButton: View {
  let tab: GitTab
  let isSelected: Bool
  let action: () -> Void

  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 4) {
        Image(systemName: tab.iconName)
          .font(.system(size: 10))

        Text(tab.displayName)
          .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
      }
      .foregroundColor(isSelected ? .primary : .secondary)
      .padding(.horizontal, 10)
      .padding(.vertical, 5)
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
  }
}

// MARK: - Stub Content

/// Placeholder view for Git sub-tabs that are not yet implemented.
struct GitStubContentView: View {
  let tab: GitTab

  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: tab.iconName)
        .font(.system(size: 36))
        .foregroundColor(.secondary.opacity(0.5))

      Text(tab.displayName)
        .font(.system(size: 16, weight: .semibold))

      Text("This feature is not yet available.")
        .font(.system(size: 12))
        .foregroundColor(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
