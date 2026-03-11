import SwiftUI

/// Displays a scrollable commit history with a lane-based graph.
struct RevisionGraphView: View {
  let workingDirectory: URL

  @State private var allCommits: [GraphCommit] = []
  @State private var assignments: [LaneAssignment] = []
  @State private var isLoading = false
  @State private var hasMore = true
  @State private var loadedCount = 0
  @State private var maxLaneCount = 1

  private let batchSize = 200

  private var graphColumnWidth: CGFloat {
    CGFloat(maxLaneCount) * RevisionGraphRow.laneWidth
  }

  var body: some View {
    VStack(spacing: 0) {
      headerBar
      Divider()
      commitList
    }
    .task {
      await loadInitialBatch()
    }
  }

  // MARK: - Header

  private var headerBar: some View {
    HStack {
      Text("\(assignments.count) commits")
        .font(.system(size: 11))
        .foregroundColor(.secondary)

      Spacer()

      Button("Refresh") {
        Task {
          await reload()
        }
      }
      .buttonStyle(.plain)
      .font(.system(size: 11))
      .foregroundColor(.secondary)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
  }

  // MARK: - Commit List

  private var commitList: some View {
    ScrollView {
      LazyVStack(spacing: 0) {
        ForEach(assignments) { assignment in
          RevisionGraphRow(
            assignment: assignment,
            maxLanes: maxLaneCount
          )

          Divider()
            .padding(.leading, graphColumnWidth)
        }

        if hasMore {
          ProgressView()
            .padding()
            .onAppear {
              Task {
                await loadMore()
              }
            }
        }
      }
    }
  }

  // MARK: - Data Loading

  private func loadInitialBatch() async {
    guard !isLoading else {
      return
    }

    isLoading = true

    let commits = await GitStatsService.shared.getCommitGraph(
      in: workingDirectory,
      limit: batchSize,
      skip: 0
    )

    let computed = await computeLanes(for: commits)

    allCommits = commits
    assignments = computed
    maxLaneCount = computed.map(\.activeLanes.count).max() ?? 1
    loadedCount = commits.count
    hasMore = commits.count >= batchSize

    isLoading = false
  }

  private func loadMore() async {
    guard hasMore,
          !isLoading
    else {
      return
    }

    isLoading = true

    let newCommits = await GitStatsService.shared.getCommitGraph(
      in: workingDirectory,
      limit: batchSize,
      skip: loadedCount
    )

    let combined = allCommits + newCommits
    let computed = await computeLanes(for: combined)

    allCommits = combined
    assignments = computed
    maxLaneCount = computed.map(\.activeLanes.count).max() ?? 1
    loadedCount += newCommits.count
    hasMore = newCommits.count >= batchSize

    isLoading = false
  }

  private func reload() async {
    allCommits = []
    assignments = []
    maxLaneCount = 1
    loadedCount = 0
    hasMore = true
    await loadInitialBatch()
  }

  /// Runs lane calculation on a background thread to keep the UI responsive.
  private func computeLanes(for commits: [GraphCommit]) async -> [LaneAssignment] {
    await Task.detached {
      GraphLaneCalculator.assignLanes(commits)
    }.value
  }
}

// MARK: - Row

/// A single row in the revision graph: lane graphics on the left, commit metadata on the right.
struct RevisionGraphRow: View {
  static let laneWidth: CGFloat = 16

  let assignment: LaneAssignment
  let maxLanes: Int

  private let rowHeight: CGFloat = 36

  private static let relativeDateFormatter: RelativeDateTimeFormatter = {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter
  }()

  private static let laneColors: [Color] = [
    .blue, .green, .orange, .purple,
    .pink, .cyan, .yellow, .mint,
  ]

  var body: some View {
    HStack(spacing: 0) {
      graphColumn
      metadataColumn
    }
    .frame(height: rowHeight)
  }

  // MARK: - Graph Column

  private var graphColumn: some View {
    Canvas { context, size in
      let midY = size.height / 2

      // Draw lane states.
      for (i, state) in assignment.activeLanes.enumerated() {
        let centerX = CGFloat(i) * Self.laneWidth + Self.laneWidth / 2

        switch state {
        case .empty:
          break

        case .passThrough(let color):
          // Vertical line top to bottom.
          drawVerticalLine(context: context, x: centerX, height: size.height, color: color)

        case .commitDot(let color):
          // Vertical line + commit dot.
          drawVerticalLine(context: context, x: centerX, height: size.height, color: color)
          drawCommitDot(context: context, x: centerX, y: midY, color: color)

        case .mergeIn(let color):
          // Vertical line + diagonal to commit lane.
          drawVerticalLine(context: context, x: centerX, height: size.height, color: color)
          let commitX = CGFloat(assignment.laneIndex) * Self.laneWidth + Self.laneWidth / 2
          drawDiagonalLine(context: context, fromX: centerX, toX: commitX, midY: midY, color: color)
        }
      }

      // Draw merge source diagonals.
      for mergeLane in assignment.mergeSourceLanes {
        guard mergeLane < assignment.activeLanes.count else {
          continue
        }

        // Only draw diagonal if not already handled by .mergeIn state.
        if case .mergeIn = assignment.activeLanes[mergeLane] {
          continue
        }

        let sourceX = CGFloat(mergeLane) * Self.laneWidth + Self.laneWidth / 2
        let commitX = CGFloat(assignment.laneIndex) * Self.laneWidth + Self.laneWidth / 2
        let color = laneColorIndex(for: mergeLane)
        drawDiagonalLine(context: context, fromX: sourceX, toX: commitX, midY: midY, color: color)
      }
    }
    .frame(width: CGFloat(maxLanes) * Self.laneWidth, height: rowHeight)
  }

  private func laneColorIndex(for lane: Int) -> Int {
    guard lane < assignment.activeLanes.count else {
      return 0
    }

    switch assignment.activeLanes[lane] {
    case .passThrough(let color), .commitDot(let color), .mergeIn(let color):
      return color

    case .empty:
      return 0
    }
  }

  private func drawVerticalLine(
    context: GraphicsContext,
    x: CGFloat,
    height: CGFloat,
    color: Int
  ) {
    var path = Path()
    path.move(to: CGPoint(x: x, y: 0))
    path.addLine(to: CGPoint(x: x, y: height))
    context.stroke(path, with: .color(Self.laneColors[color % 8]), lineWidth: 2)
  }

  private func drawCommitDot(
    context: GraphicsContext,
    x: CGFloat,
    y: CGFloat,
    color: Int
  ) {
    let radius: CGFloat = 4
    let center = CGPoint(x: x, y: y)

    // Background-colored border for contrast in both light and dark modes.
    let borderCircle = Path(ellipseIn: CGRect(
      x: center.x - radius - 1.5,
      y: center.y - radius - 1.5,
      width: (radius + 1.5) * 2,
      height: (radius + 1.5) * 2
    ))
    context.fill(borderCircle, with: .color(appBackgroundColor))

    // Filled dot.
    let dot = Path(ellipseIn: CGRect(
      x: center.x - radius,
      y: center.y - radius,
      width: radius * 2,
      height: radius * 2
    ))
    context.fill(dot, with: .color(Self.laneColors[color % 8]))
  }

  private func drawDiagonalLine(
    context: GraphicsContext,
    fromX: CGFloat,
    toX: CGFloat,
    midY: CGFloat,
    color: Int
  ) {
    var path = Path()
    path.move(to: CGPoint(x: fromX, y: 0))
    path.addLine(to: CGPoint(x: toX, y: midY))
    context.stroke(path, with: .color(Self.laneColors[color % 8]), lineWidth: 2)
  }

  // MARK: - Metadata Column

  private var metadataColumn: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 4) {
        if !assignment.commit.decorations.isEmpty {
          decorationBadges
        }

        Text(assignment.commit.subject)
          .font(.system(size: 11))
          .lineLimit(1)
          .truncationMode(.middle)

        Spacer()

        Text(assignment.commit.shortHash)
          .font(.system(size: 10, design: .monospaced))
          .foregroundColor(.secondary)
      }

      HStack {
        Text(assignment.commit.authorName)
          .font(.system(size: 10))
          .foregroundColor(.secondary)
          .lineLimit(1)

        Spacer()

        Text(Self.relativeDateFormatter.localizedString(
          for: assignment.commit.authorDate,
          relativeTo: Date()
        ))
        .font(.system(size: 10))
        .foregroundColor(.secondary)
      }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
  }

  // MARK: - Decorations

  private var decorationBadges: some View {
    HStack(spacing: 3) {
      ForEach(assignment.commit.decorations, id: \.self) { decoration in
        Text(decoration)
          .font(.system(size: 9, weight: .semibold))
          .padding(.horizontal, 4)
          .padding(.vertical, 1)
          .background(decorationColor(for: decoration).opacity(0.2))
          .foregroundColor(decorationColor(for: decoration))
          .cornerRadius(3)
      }
    }
  }

  private func decorationColor(for decoration: String) -> Color {
    if decoration.hasPrefix("tag:") {
      return .orange
    }

    if decoration.contains("HEAD") {
      return .green
    }

    return .blue
  }
}
