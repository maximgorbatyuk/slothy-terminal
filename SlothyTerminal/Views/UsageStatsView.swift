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
        /// Provider subtabs.
        Picker("Provider", selection: $selectedProvider) {
          ForEach(UsageProvider.sidebarProviders, id: \.self) { provider in
            Text(provider.displayName).tag(provider)
          }
        }
        .pickerStyle(.segmented)
        .labelsHidden()

        /// Content for the selected provider.
        usageContent(provider: selectedProvider)
      }
    }
    .task {
      await loadAllUsage()
    }
  }

  @ViewBuilder
  private func usageContent(provider: UsageProvider) -> some View {
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
    .padding(10)
    .background(appCardColor)
    .cornerRadius(8)
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

      Text("Updated \(snapshot.fetchedAt.formatted(.relative(presentation: .named)))")
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

  private func loadAllUsage() async {
    let prefs = ConfigManager.shared.config.usagePreferences

    guard prefs.isEnabled else {
      return
    }

    usageService.resolveAuthSources()
    await usageService.fetchAll()
  }

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
