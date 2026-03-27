import SwiftUI

/// Compact usage stats block for the sidebar.
/// Always visible with Claude/Codex subtabs for switching providers.
struct UsageStatsView: View {
  @State private var isExpanded = true
  @State private var selectedProvider: UsageProvider = .claude

  private var usageService: UsageService { UsageService.shared }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      /// Collapsible header.
      Button {
        isExpanded.toggle()
      } label: {
        HStack {
          Image(systemName: "chart.bar.fill")
            .font(.system(size: 10))

          Text("Usage")
            .font(.system(size: 10, weight: .semibold))

          Spacer()

          Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
            .font(.system(size: 10))
        }
        .foregroundColor(.secondary)
      }
      .buttonStyle(.plain)

      if isExpanded {
        HStack(spacing: 0) {
          /// Vertical provider tab strip.
          VStack(spacing: 4) {
            ForEach(UsageProvider.sidebarProviders, id: \.self) { provider in
              Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                  selectedProvider = provider
                }
              } label: {
                Image(systemName: provider.iconName)
                  .font(.system(size: 11))
                  .foregroundColor(selectedProvider == provider ? .white : .primary.opacity(0.5))
                  .frame(width: 26, height: 26)
                  .background(
                    RoundedRectangle(cornerRadius: 6)
                      .fill(selectedProvider == provider ? Color.accentColor : Color.clear)
                  )
              }
              .buttonStyle(.plain)
              .help(provider.displayName)
            }

            Spacer()
          }
          .padding(.top, 4)
          .frame(width: 30)

          /// Thin divider between tabs and content.
          Divider()
            .padding(.vertical, 4)

          /// Scrollable content.
          GeometryReader { geometry in
            ScrollView {
              usageContent(provider: selectedProvider, minHeight: geometry.size.height)
            }
          }
          .frame(maxWidth: .infinity)
        }
        .frame(height: usageContentHeight)
        .background(appCardColor)
        .cornerRadius(8)
      }
    }
    .task {
      usageService.ensureStarted()
    }
  }

  /// Fixed height for the usage content area, slightly taller than 1/4 of the sidebar.
  private var usageContentHeight: CGFloat {
    let sidebarHeight = NSApp.keyWindow?.contentView?.frame.height ?? 600
    return UsageStatsLayout.contentHeight(forSidebarHeight: sidebarHeight)
  }

  @ViewBuilder
  private func usageContent(provider: UsageProvider, minHeight: CGFloat) -> some View {
    let status = usageService.status(for: provider)

    VStack(spacing: 6) {
      switch status {
      case .idle:
        disabledView()

      case .loading:
        loadingView()

      case .loaded:
        if let snapshot = usageService.snapshot(for: provider) {
          snapshotView(snapshot, provider: provider)
        } else {
          noDataView()
        }

      case .failed(let message):
        errorView(message, provider: provider)

      case .unavailable(let reason):
        unavailableView(reason)
      }
    }
    .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .top)
    .padding(10)
  }

  @ViewBuilder
  private func snapshotView(
    _ snapshot: UsageSnapshot,
    provider: UsageProvider
  ) -> some View {
    /// Source badge row.
    HStack {
      Text(snapshot.provider.displayName)
        .font(.system(size: 10, weight: .medium))
        .foregroundColor(.primary)

      Spacer()

      Text(snapshot.sourceLabel)
        .font(.system(size: 9, weight: .medium))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(sourceBadgeColor(for: snapshot.sourceKind))
        .foregroundColor(.white)
        .cornerRadius(4)
    }

    /// Account.
    if let account = snapshot.account {
      StatRow(label: "Account", value: account)
    }

    /// Quota window.
    if let window = snapshot.quotaWindow {
      StatRow(label: window.name, value: window.resetLabel ?? "")
    }

    /// Usage bar when percentage is available.
    if let percent = snapshot.percentUsed {
      VStack(spacing: 4) {
        GeometryReader { geometry in
          ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
              .fill(Color.secondary.opacity(0.2))
              .frame(height: 4)

            RoundedRectangle(cornerRadius: 2)
              .fill(usageBarColor(percent: percent))
              .frame(
                width: geometry.size.width * min(percent, 1.0),
                height: 4
              )
          }
        }
        .frame(height: 4)

        HStack {
          Text(snapshot.used)
            .font(.system(size: 10))
            .foregroundColor(.primary)

          Spacer()

          if let limit = snapshot.limit {
            Text("/ \(limit)")
              .font(.system(size: 10))
              .foregroundColor(.secondary)
          }
        }
      }
    } else {
      /// No percentage — show raw used value.
      StatRow(label: "Used", value: snapshot.used, isHighlighted: true)
    }

    /// Remaining.
    if let remaining = snapshot.remaining {
      StatRow(label: "Remaining", value: remaining)
    }

    /// Additional metrics.
    ForEach(snapshot.metrics) { metric in
      StatRow(
        label: metric.label,
        value: metric.value,
        isHighlighted: metric.style == .highlighted,
        style: statRowStyle(for: metric.style)
      )
    }

    /// Last updated timestamp.
    HStack {
      Spacer()

      Text("Updated \(snapshot.fetchedAt.formatted(.dateTime.hour().minute().second()))")
        .font(.system(size: 9))
        .foregroundColor(.secondary.opacity(0.7))
    }

    /// Refresh button.
    Button {
      Task {
        await usageService.fetch(provider: provider)
      }
    } label: {
      HStack(spacing: 4) {
        Image(systemName: "arrow.clockwise")
          .font(.system(size: 9))

        Text("Refresh")
          .font(.system(size: 10))
      }
      .foregroundColor(.secondary)
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder
  private func loadingView() -> some View {
    HStack(spacing: 8) {
      ProgressView()
        .controlSize(.small)

      Text("Loading usage...")
        .font(.system(size: 11))
        .foregroundColor(.secondary)
    }
  }

  @ViewBuilder
  private func errorView(_ message: String, provider: UsageProvider) -> some View {
    VStack(spacing: 6) {
      HStack(spacing: 6) {
        Image(systemName: "exclamationmark.triangle")
          .font(.system(size: 10))
          .foregroundColor(.orange)

        Text(message)
          .font(.system(size: 11))
          .foregroundColor(.secondary)
          .lineLimit(2)
      }

      Button {
        Task {
          await usageService.fetch(provider: provider)
        }
      } label: {
        Text("Retry")
          .font(.system(size: 10))
      }
      .buttonStyle(.bordered)
      .controlSize(.small)
    }
  }

  @ViewBuilder
  private func unavailableView(_ reason: String) -> some View {
    HStack(spacing: 6) {
      Image(systemName: "info.circle")
        .font(.system(size: 10))
        .foregroundColor(.secondary)

      Text(reason)
        .font(.system(size: 11))
        .foregroundColor(.secondary)
        .lineLimit(2)
    }
  }

  @ViewBuilder
  private func noDataView() -> some View {
    HStack(spacing: 6) {
      Image(systemName: "chart.bar")
        .font(.system(size: 10))
        .foregroundColor(.secondary)

      Text("No usage data")
        .font(.system(size: 11))
        .foregroundColor(.secondary)
    }
  }

  @ViewBuilder
  private func disabledView() -> some View {
    VStack(spacing: 4) {
      HStack(spacing: 6) {
        Image(systemName: "chart.bar")
          .font(.system(size: 10))
          .foregroundColor(.secondary)

        Text("Usage stats disabled")
          .font(.system(size: 11))
          .foregroundColor(.secondary)
      }

      Text("Enable in Settings > Usage")
        .font(.system(size: 10))
        .foregroundColor(.secondary.opacity(0.7))
    }
  }

  // MARK: - Helpers

  private func sourceBadgeColor(for kind: UsageSourceKind) -> Color {
    switch kind {
    case .apiKey:
      return .green

    case .cliOAuth:
      return .blue

    case .browser:
      return .orange

    case .experimental:
      return .red
    }
  }

  private func usageBarColor(percent: Double) -> Color {
    if percent > 0.9 {
      return .red
    } else if percent > 0.7 {
      return .orange
    }

    return .green
  }

  private func statRowStyle(for style: UsageMetricStyle) -> StatRowStyle {
    switch style {
    case .normal, .highlighted:
      return .normal

    case .warning:
      return .warning

    case .cost:
      return .cost
    }
  }
}
