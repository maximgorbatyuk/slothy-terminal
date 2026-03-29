import SwiftUI

/// Compact usage bars for the status bar.
/// Shows a small progress bar per provider; hover reveals a detail popover.
struct StatusBarUsageBars: View {
  private var usageService: UsageService { UsageService.shared }

  @State private var isPopoverPresented = false
  @State private var hoverTask: Task<Void, Never>?

  /// Providers that have a non-idle status.
  private var activeProviders: [UsageProvider] {
    UsageProvider.statusBarProviders.filter { provider in
      switch usageService.status(for: provider) {
      case .idle:
        return false

      default:
        return true
      }
    }
  }

  var body: some View {
    if !activeProviders.isEmpty {
      HStack(spacing: 8) {
        ForEach(activeProviders, id: \.self) { provider in
          providerBar(provider)
        }
      }
      .onHover { hovering in
        handleHover(hovering)
      }
      .popover(isPresented: $isPopoverPresented) {
        UsagePopoverView()
          .onHover { hovering in
            handleHover(hovering)
          }
      }
    }
  }

  @ViewBuilder
  private func providerBar(_ provider: UsageProvider) -> some View {
    let status = usageService.status(for: provider)

    HStack(spacing: 4) {
      Image(systemName: provider.iconName)
        .font(.system(size: 9))
        .foregroundColor(.secondary)

      switch status {
      case .loading:
        ProgressView()
          .controlSize(.mini)
          .scaleEffect(0.6)
          .frame(width: 40)

      case .loaded:
        if let snapshot = usageService.snapshot(for: provider),
           let percent = snapshot.percentUsed
        {
          usageBarCapsule(percent: percent)

          Text("\(Int(min(percent, 9.99) * 100))%")
            .font(.system(size: 9).monospacedDigit())
            .foregroundColor(.secondary)
        } else {
          Text("--")
            .font(.system(size: 9))
            .foregroundColor(.secondary)
        }

      case .failed:
        Image(systemName: "exclamationmark.triangle.fill")
          .font(.system(size: 8))
          .foregroundColor(.orange)

      case .unavailable:
        Image(systemName: "minus.circle")
          .font(.system(size: 8))
          .foregroundColor(.secondary.opacity(0.5))

      case .idle:
        EmptyView()
      }
    }
  }

  private func usageBarCapsule(percent: Double) -> some View {
    ZStack(alignment: .leading) {
      Capsule()
        .fill(Color.secondary.opacity(0.2))
        .frame(width: 40, height: 4)

      Capsule()
        .fill(barColor(percent: percent))
        .frame(width: 40 * min(percent, 1.0), height: 4)
    }
  }

  private func barColor(percent: Double) -> Color {
    if percent > 0.9 {
      return .red
    } else if percent > 0.7 {
      return .orange
    }

    return .green
  }

  private func handleHover(_ hovering: Bool) {
    hoverTask?.cancel()

    if hovering {
      hoverTask = Task {
        try? await Task.sleep(nanoseconds: 300_000_000)

        guard !Task.isCancelled else {
          return
        }

        isPopoverPresented = true
      }
    } else {
      hoverTask = Task {
        try? await Task.sleep(nanoseconds: 300_000_000)

        guard !Task.isCancelled else {
          return
        }

        isPopoverPresented = false
      }
    }
  }
}

// MARK: - Usage Popover

/// Full usage detail popover shown on hover.
struct UsagePopoverView: View {
  @State private var selectedProvider: UsageProvider = .claude

  private var usageService: UsageService { UsageService.shared }

  var body: some View {
    VStack(spacing: 0) {
      /// Provider tabs.
      Picker("Provider", selection: $selectedProvider) {
        ForEach(UsageProvider.statusBarProviders, id: \.self) { provider in
          Text(provider.displayName).tag(provider)
        }
      }
      .pickerStyle(.segmented)
      .padding(.horizontal, 12)
      .padding(.top, 12)
      .padding(.bottom, 8)

      Divider()

      /// Content area.
      ScrollView {
        popoverContent(provider: selectedProvider)
          .padding(12)
      }
      .frame(maxHeight: 320)
    }
    .frame(width: 320)
  }

  @ViewBuilder
  private func popoverContent(provider: UsageProvider) -> some View {
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
    .frame(maxWidth: .infinity, alignment: .top)
  }

  // MARK: - Snapshot View

  @ViewBuilder
  private func snapshotView(
    _ snapshot: UsageSnapshot,
    provider: UsageProvider
  ) -> some View {
    /// Source badge row.
    HStack {
      Text(snapshot.provider.displayName)
        .font(.system(size: 11, weight: .medium))
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
              .frame(height: 6)

            RoundedRectangle(cornerRadius: 2)
              .fill(usageBarColor(percent: percent))
              .frame(
                width: geometry.size.width * min(percent, 1.0),
                height: 6
              )
          }
        }
        .frame(height: 6)

        HStack {
          Text(snapshot.used)
            .font(.system(size: 11))
            .foregroundColor(.primary)

          Spacer()

          if let limit = snapshot.limit {
            Text("/ \(limit)")
              .font(.system(size: 11))
              .foregroundColor(.secondary)
          }
        }
      }
    } else {
      /// No percentage -- show raw used value.
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

    Divider()
      .padding(.vertical, 4)

    /// Footer: timestamp + refresh.
    HStack {
      Text("Updated \(snapshot.fetchedAt.formatted(.dateTime.hour().minute().second()))")
        .font(.system(size: 9))
        .foregroundColor(.secondary.opacity(0.7))

      Spacer()

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
  }

  // MARK: - Status Views

  @ViewBuilder
  private func loadingView() -> some View {
    HStack(spacing: 8) {
      ProgressView()
        .controlSize(.small)

      Text("Loading usage...")
        .font(.system(size: 11))
        .foregroundColor(.secondary)
    }
    .padding(.vertical, 20)
  }

  @ViewBuilder
  private func errorView(_ message: String, provider: UsageProvider) -> some View {
    VStack(spacing: 8) {
      HStack(spacing: 6) {
        Image(systemName: "exclamationmark.triangle")
          .font(.system(size: 11))
          .foregroundColor(.orange)

        Text(message)
          .font(.system(size: 11))
          .foregroundColor(.secondary)
          .lineLimit(3)
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
    .padding(.vertical, 12)
  }

  @ViewBuilder
  private func unavailableView(_ reason: String) -> some View {
    HStack(spacing: 6) {
      Image(systemName: "info.circle")
        .font(.system(size: 11))
        .foregroundColor(.secondary)

      Text(reason)
        .font(.system(size: 11))
        .foregroundColor(.secondary)
        .lineLimit(2)
    }
    .padding(.vertical, 20)
  }

  @ViewBuilder
  private func noDataView() -> some View {
    HStack(spacing: 6) {
      Image(systemName: "chart.bar")
        .font(.system(size: 11))
        .foregroundColor(.secondary)

      Text("No usage data")
        .font(.system(size: 11))
        .foregroundColor(.secondary)
    }
    .padding(.vertical, 20)
  }

  @ViewBuilder
  private func disabledView() -> some View {
    VStack(spacing: 4) {
      HStack(spacing: 6) {
        Image(systemName: "chart.bar")
          .font(.system(size: 11))
          .foregroundColor(.secondary)

        Text("Usage stats disabled")
          .font(.system(size: 11))
          .foregroundColor(.secondary)
      }

      Text("Enable in Settings > Usage")
        .font(.system(size: 10))
        .foregroundColor(.secondary.opacity(0.7))
    }
    .padding(.vertical, 20)
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
