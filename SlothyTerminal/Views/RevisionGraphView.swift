import SwiftUI

/// Displays a split-pane revision graph: scrollable commit history on top,
/// commit inspector on the bottom.
struct RevisionGraphView: View {
  let workingDirectory: URL

  // MARK: - Graph State

  @State private var allCommits: [GraphCommit] = []
  @State private var assignments: [LaneAssignment] = []
  @State private var isLoading = false
  @State private var hasMore = true
  @State private var loadedCount = 0
  @State private var maxLaneCount = 1

  // MARK: - Selection & Inspector State

  @State private var selectedCommitID: String?
  @State private var inspectorTab: CommitInspectorTab = .changes
  @State private var changedFiles: [CommitFileChange] = []
  @State private var fileTree: [CommitFileTreeNode] = []
  @State private var expandedDirectories: Set<String> = []
  @State private var selectedFilePath: String?
  @State private var diffDocument = GitDiffDocument()
  @State private var commitBody: String?
  @State private var isLoadingChanges = false
  @State private var isLoadingDiff = false

  private let batchSize = 200

  private var selectedCommit: GraphCommit? {
    guard let selectedCommitID else {
      return nil
    }

    return assignments.first { $0.commit.id == selectedCommitID }?.commit
  }

  var body: some View {
    GeometryReader { geometry in
      VStack(spacing: 0) {
        topPane
          .frame(height: geometry.size.height * 0.57)

        Divider()

        bottomPane
      }
    }
    .task {
      await loadInitialBatch()
    }
    .task(id: selectedCommitID) {
      await loadCommitDetails()
    }
    .task(id: selectedFilePath) {
      await loadSelectedFileDiff()
    }
  }

  // MARK: - Top Pane (Revision Graph)

  private var topPane: some View {
    VStack(spacing: 0) {
      graphHeaderBar
      Divider()
      commitList
    }
  }

  private var graphHeaderBar: some View {
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
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
  }

  private var commitList: some View {
    List(selection: $selectedCommitID) {
      ForEach(assignments) { assignment in
        RevisionGraphRow(
          assignment: assignment,
          maxLanes: maxLaneCount
        )
        .tag(assignment.commit.id)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
      }

      if hasMore {
        ProgressView()
          .frame(maxWidth: .infinity)
          .padding(.vertical, 8)
          .onAppear {
            Task {
              await loadMore()
            }
          }
      }
    }
    .listStyle(.plain)
  }

  // MARK: - Bottom Pane (Inspector)

  private var bottomPane: some View {
    VStack(spacing: 0) {
      inspectorTabStrip
      Divider()

      if let commit = selectedCommit {
        commitSummaryBar(commit: commit)
        Divider()
        inspectorContent
      } else {
        emptyInspectorState
      }
    }
    .background(appBackgroundColor)
  }

  private var inspectorTabStrip: some View {
    HStack(spacing: 0) {
      ForEach(CommitInspectorTab.allCases) { tab in
        InspectorTabButton(
          title: tab.displayName,
          isSelected: inspectorTab == tab
        ) {
          inspectorTab = tab
        }
      }

      Spacer()

      Button {
        Task {
          await reload()
        }
      } label: {
        Image(systemName: "arrow.clockwise")
          .font(.system(size: 10))
          .foregroundColor(.secondary)
      }
      .buttonStyle(.plain)
      .padding(.trailing, 10)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
  }

  private func commitSummaryBar(commit: GraphCommit) -> some View {
    HStack(spacing: 8) {
      Circle()
        .fill(Color.accentColor.opacity(0.25))
        .frame(width: 22, height: 22)
        .overlay(
          Text(String(commit.authorName.prefix(1)).uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.accentColor)
        )

      Text(commit.authorName)
        .font(.system(size: 11, weight: .medium))
        .lineLimit(1)

      Text(commit.shortHash)
        .font(.system(size: 11, design: .monospaced))
        .foregroundColor(.secondary)

      Text(Self.absoluteDateFormatter.string(from: commit.authorDate))
        .font(.system(size: 11))
        .foregroundColor(.secondary)

      Text(commit.subject)
        .font(.system(size: 11))
        .foregroundColor(.secondary)
        .lineLimit(1)
        .truncationMode(.tail)

      Spacer()
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
  }

  private var inspectorContent: some View {
    GeometryReader { geo in
      HStack(spacing: 0) {
        leftPane
          .frame(width: geo.size.width * 0.30)

        Divider()

        rightPane
      }
    }
  }

  private var emptyInspectorState: some View {
    VStack(spacing: 8) {
      Image(systemName: "cursorarrow.click.2")
        .font(.system(size: 24))
        .foregroundColor(.secondary.opacity(0.5))

      Text("Select a commit to inspect")
        .font(.system(size: 12))
        .foregroundColor(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  // MARK: - Left Pane

  private var leftPane: some View {
    VStack(spacing: 0) {
      switch inspectorTab {
      case .commit:
        commitDetailsPane

      case .changes, .fileTree:
        changesPane
      }
    }
  }

  private var commitDetailsPane: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        if let commit = selectedCommit {
          Group {
            labeledField("Author", value: commit.authorName)
            labeledField("Email", value: commit.authorEmail)
            labeledField("Hash", value: commit.id)
            labeledField("Date", value: Self.absoluteDateFormatter.string(from: commit.authorDate))

            if !commit.parentHashes.isEmpty {
              labeledField("Parents", value: commit.parentHashes.map { String($0.prefix(8)) }.joined(separator: ", "))
            }

            if !commit.decorations.isEmpty {
              labeledField("Refs", value: commit.decorations.joined(separator: ", "))
            }
          }

          if let body = commitBody, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Divider()

            Text(body.trimmingCharacters(in: .whitespacesAndNewlines))
              .font(.system(size: 11, design: .monospaced))
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
      }
      .padding(10)
    }
  }

  private func labeledField(_ label: String, value: String) -> some View {
    HStack(alignment: .top, spacing: 6) {
      Text(label)
        .font(.system(size: 10, weight: .medium))
        .foregroundColor(.secondary)
        .frame(width: 50, alignment: .trailing)

      Text(value)
        .font(.system(size: 11))
        .textSelection(.enabled)
        .lineLimit(2)
    }
  }

  private var changesPane: some View {
    VStack(spacing: 0) {
      changesToolbar

      Divider()

      if isLoadingChanges {
        ProgressView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if changedFiles.isEmpty {
        Text("No changes")
          .font(.system(size: 11))
          .foregroundColor(.secondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollView {
          VStack(alignment: .leading, spacing: 0) {
            ForEach(flattenedFileTree, id: \.node.id) { item in
              fileTreeRowView(node: item.node, depth: item.depth)
            }
          }
          .padding(.vertical, 2)
        }
      }
    }
  }

  /// Flattens the hierarchical file tree into a list respecting expansion state.
  private var flattenedFileTree: [(node: CommitFileTreeNode, depth: Int)] {
    var result: [(node: CommitFileTreeNode, depth: Int)] = []

    func flatten(_ nodes: [CommitFileTreeNode], depth: Int) {
      for node in nodes {
        result.append((node: node, depth: depth))

        if node.isDirectory, expandedDirectories.contains(node.path) {
          flatten(node.children, depth: depth + 1)
        }
      }
    }

    flatten(fileTree, depth: 0)
    return result
  }

  private var changesToolbar: some View {
    HStack(spacing: 6) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 10))
        .foregroundColor(.secondary)

      Text("\(changedFiles.count) files")
        .font(.system(size: 10))
        .foregroundColor(.secondary)

      Spacer()

      Button {
        if expandedDirectories.isEmpty {
          expandedDirectories = CommitFileTreeNode.allDirectoryPaths(in: fileTree)
        } else {
          expandedDirectories.removeAll()
        }
      } label: {
        Image(systemName: expandedDirectories.isEmpty ? "chevron.down.square" : "chevron.right.square")
          .font(.system(size: 10))
          .foregroundColor(.secondary)
      }
      .buttonStyle(.plain)
      .help(expandedDirectories.isEmpty ? "Expand all" : "Collapse all")
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 5)
  }

  @ViewBuilder
  private func fileTreeRowView(node: CommitFileTreeNode, depth: Int) -> some View {
    if node.isDirectory {
      Button {
        toggleDirectory(node.path)
      } label: {
        HStack(spacing: 4) {
          Image(systemName: expandedDirectories.contains(node.path) ? "chevron.down" : "chevron.right")
            .font(.system(size: 8))
            .foregroundColor(.secondary)
            .frame(width: 10)

          Image(systemName: "folder.fill")
            .font(.system(size: 10))
            .foregroundColor(.secondary)

          Text(node.name)
            .font(.system(size: 11))
            .lineLimit(1)

          Spacer()
        }
        .padding(.leading, CGFloat(depth) * 14 + 4)
        .padding(.vertical, 4)
        .padding(.trailing, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
    } else if let change = node.fileChange {
      Button {
        selectedFilePath = change.path
      } label: {
        HStack(spacing: 4) {
          Color.clear
            .frame(width: 10)

          Image(systemName: fileIconName(for: change))
            .font(.system(size: 10))
            .foregroundColor(.secondary)

          Text(node.name)
            .font(.system(size: 11))
            .lineLimit(1)

          Spacer()

          Text(change.status.badge)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundColor(fileStatusColor(change.status))
        }
        .padding(.leading, CGFloat(depth) * 14 + 4)
        .padding(.vertical, 4)
        .padding(.trailing, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
          selectedFilePath == change.path
            ? Color.accentColor.opacity(0.15)
            : Color.clear
        )
        .cornerRadius(3)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
    }
  }

  private func toggleDirectory(_ path: String) {
    if expandedDirectories.contains(path) {
      expandedDirectories.remove(path)
    } else {
      expandedDirectories.insert(path)
    }
  }

  // MARK: - Right Pane (Diff Viewer)

  private var rightPane: some View {
    VStack(spacing: 0) {
      diffHeader

      Divider()

      if isLoadingDiff {
        ProgressView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if selectedFilePath == nil {
        VStack(spacing: 6) {
          Text("Select a file to view diff")
            .font(.system(size: 11))
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if diffDocument.isBinary {
        Text("Binary file")
          .font(.system(size: 11))
          .foregroundColor(.secondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if diffDocument.isEmpty {
        Text("No diff available")
          .font(.system(size: 11))
          .foregroundColor(.secondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        GeometryReader { diffGeometry in
          ScrollView([.vertical, .horizontal]) {
            LazyVStack(spacing: 0) {
              ForEach(diffDocument.rows) { row in
                commitDiffRow(row)
              }
            }
            .frame(minWidth: diffGeometry.size.width)
          }
        }
      }
    }
  }

  private var diffHeader: some View {
    HStack(spacing: 6) {
      Image(systemName: "doc.text")
        .font(.system(size: 10))
        .foregroundColor(.secondary)

      Text(selectedFilePath ?? "No file selected")
        .font(.system(size: 11, design: .monospaced))
        .foregroundColor(selectedFilePath != nil ? .primary : .secondary)
        .lineLimit(1)
        .truncationMode(.middle)

      Spacer()
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 5)
    .background(appCardColor)
  }

  private func commitDiffRow(_ row: GitDiffRow) -> some View {
    HStack(spacing: 0) {
      commitDiffCell(
        lineNumber: row.oldLineNumber,
        text: row.leftText,
        backgroundColor: leftDiffBackground(for: row.kind)
      )

      Divider()

      commitDiffCell(
        lineNumber: row.newLineNumber,
        text: row.rightText,
        backgroundColor: rightDiffBackground(for: row.kind)
      )
    }
  }

  private func commitDiffCell(
    lineNumber: Int?,
    text: String,
    backgroundColor: Color
  ) -> some View {
    HStack(alignment: .top, spacing: 6) {
      Text(lineNumber.map(String.init) ?? "")
        .font(.system(size: 10, design: .monospaced))
        .foregroundColor(.secondary)
        .frame(width: 32, alignment: .trailing)

      Text(verbatim: text.isEmpty ? " " : text)
        .font(.system(size: 11, design: .monospaced))
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }
    .padding(.horizontal, 6)
    .padding(.vertical, 3)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(backgroundColor)
  }

  private func leftDiffBackground(for kind: GitDiffRowKind) -> Color {
    switch kind {
    case .context, .addition:
      return .clear

    case .deletion, .modification:
      return .red.opacity(0.08)
    }
  }

  private func rightDiffBackground(for kind: GitDiffRowKind) -> Color {
    switch kind {
    case .context, .deletion:
      return .clear

    case .addition, .modification:
      return .green.opacity(0.08)
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
    guard hasMore, !isLoading else {
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
    selectedCommitID = nil
    await loadInitialBatch()
  }

  @MainActor
  private func loadCommitDetails() async {
    guard let commit = selectedCommit else {
      changedFiles = []
      fileTree = []
      commitBody = nil
      selectedFilePath = nil
      diffDocument = GitDiffDocument()
      return
    }

    selectedFilePath = nil
    diffDocument = GitDiffDocument()
    isLoadingChanges = true

    defer {
      isLoadingChanges = false
    }

    let firstParent = commit.parentHashes.first

    async let filesResult = GitStatsService.shared.getCommitChangedFiles(
      hash: commit.id,
      firstParentHash: firstParent,
      in: workingDirectory
    )
    async let bodyResult = GitStatsService.shared.getCommitBody(
      hash: commit.id,
      in: workingDirectory
    )

    let files = await filesResult
    let body = await bodyResult

    // Guard against stale load — user may have selected a different commit.
    guard selectedCommitID == commit.id else {
      return
    }

    changedFiles = files
    commitBody = body
    fileTree = CommitFileTreeNode.buildTree(from: files)
    expandedDirectories = CommitFileTreeNode.allDirectoryPaths(in: fileTree)
  }

  @MainActor
  private func loadSelectedFileDiff() async {
    guard
      let path = selectedFilePath,
      let commit = selectedCommit
    else {
      diffDocument = GitDiffDocument()
      isLoadingDiff = false
      return
    }

    isLoadingDiff = true

    defer {
      isLoadingDiff = false
    }

    let doc = await GitStatsService.shared.getCommitFileDiff(
      hash: commit.id,
      firstParentHash: commit.parentHashes.first,
      path: path,
      in: workingDirectory
    )

    // Guard against stale load — user may have selected a different file.
    guard selectedFilePath == path else {
      return
    }

    diffDocument = doc
  }

  /// Runs lane calculation on a background thread.
  private func computeLanes(for commits: [GraphCommit]) async -> [LaneAssignment] {
    await Task.detached {
      GraphLaneCalculator.assignLanes(commits)
    }.value
  }

  // MARK: - Helpers

  private func fileStatusColor(_ status: CommitFileStatus) -> Color {
    switch status {
    case .added:
      return .green

    case .modified:
      return .orange

    case .deleted:
      return .red

    case .renamed:
      return .blue

    case .copied:
      return .cyan

    case .typeChange:
      return .purple
    }
  }

  private func fileIconName(for change: CommitFileChange) -> String {
    switch change.status {
    case .added:
      return "doc.badge.plus"

    case .deleted:
      return "doc.badge.minus"

    default:
      return "doc.text"
    }
  }

  private static let absoluteDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter
  }()
}

// MARK: - Revision Graph Row

/// A single row in the revision graph: lane graphics on the left, columnar metadata on the right.
struct RevisionGraphRow: View {
  static let laneWidth: CGFloat = 16

  let assignment: LaneAssignment
  let maxLanes: Int

  private let rowHeight: CGFloat = 34

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

      // Subject + decorations
      HStack(spacing: 4) {
        if !assignment.commit.decorations.isEmpty {
          decorationBadges
        }

        Text(assignment.commit.subject)
          .font(.system(size: 12))
          .lineLimit(1)
          .truncationMode(.tail)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.leading, 6)

      // Author
      Text(assignment.commit.authorName)
        .font(.system(size: 11))
        .foregroundColor(.secondary)
        .lineLimit(1)
        .frame(width: 120, alignment: .leading)

      // Short hash
      Text(assignment.commit.shortHash)
        .font(.system(size: 11, design: .monospaced))
        .foregroundColor(.secondary)
        .frame(width: 70, alignment: .leading)

      // Date
      Text(Self.relativeDateFormatter.localizedString(
        for: assignment.commit.authorDate,
        relativeTo: Date()
      ))
      .font(.system(size: 11))
      .foregroundColor(.secondary)
      .frame(width: 80, alignment: .trailing)
      .padding(.trailing, 8)
    }
    .frame(height: rowHeight)
    .contentShape(Rectangle())
  }

  // MARK: - Graph Column

  private var graphColumn: some View {
    Canvas { context, size in
      let midY = size.height / 2

      for (i, state) in assignment.activeLanes.enumerated() {
        let centerX = CGFloat(i) * Self.laneWidth + Self.laneWidth / 2

        switch state {
        case .empty:
          break

        case .passThrough(let color):
          drawVerticalLine(context: context, x: centerX, height: size.height, color: color)

        case .commitDot(let color):
          drawVerticalLine(context: context, x: centerX, height: size.height, color: color)
          drawCommitDot(context: context, x: centerX, y: midY, color: color)

        case .mergeIn(let color):
          drawVerticalLine(context: context, x: centerX, height: size.height, color: color)
          let commitX = CGFloat(assignment.laneIndex) * Self.laneWidth + Self.laneWidth / 2
          drawDiagonalLine(context: context, fromX: centerX, toX: commitX, midY: midY, color: color)
        }
      }

      for mergeLane in assignment.mergeSourceLanes {
        guard mergeLane < assignment.activeLanes.count else {
          continue
        }

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

    let borderCircle = Path(ellipseIn: CGRect(
      x: center.x - radius - 1.5,
      y: center.y - radius - 1.5,
      width: (radius + 1.5) * 2,
      height: (radius + 1.5) * 2
    ))
    context.fill(borderCircle, with: .color(appBackgroundColor))

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

// MARK: - Inspector Tab Button

/// Compact tab button for the commit inspector tab strip.
private struct InspectorTabButton: View {
  let title: String
  let isSelected: Bool
  let action: () -> Void

  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
        .foregroundColor(isSelected ? .primary : .secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
          isSelected
            ? Color.accentColor.opacity(0.12)
            : isHovered ? Color.primary.opacity(0.05) : Color.clear
        )
        .cornerRadius(4)
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      isHovered = hovering
    }
  }
}
