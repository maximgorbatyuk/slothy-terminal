import SwiftUI

/// Compact usage bars for the status bar.
/// Shows a small progress bar per provider; click reveals a detail popover.
struct StatusBarUsageBars: View {
  private var usageService: UsageService { UsageService.shared }

  @State private var isPopoverPresented = false
  @State private var isHovered = false
  /// Provider to surface in the popover when it opens. Kept here (rather
  /// than inside `UsagePopoverView`) so per-bar taps can pre-select the
  /// matching tab before the popover appears.
  @State private var selectedProvider: UsageProvider = .claude

  /// Providers that have a non-idle, non-unavailable status.
  /// Hiding `.unavailable` keeps the menubar clean for users who haven't
  /// connected a given provider (e.g., no Cursor JWT saved).
  private var activeProviders: [UsageProvider] {
    UsageProvider.statusBarProviders.filter { provider in
      switch usageService.status(for: provider) {
      case .idle, .unavailable:
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
            .contentShape(Rectangle())
            .onTapGesture {
              selectedProvider = provider
              isPopoverPresented = true
            }
        }
      }
      .padding(.horizontal, 6)
      .padding(.vertical, 3)
      .background(
        RoundedRectangle(cornerRadius: 4)
          .fill(isHovered ? Color.primary.opacity(0.08) : Color.clear)
      )
      .contentShape(Rectangle())
      .onHover { hovering in
        isHovered = hovering
      }
      .onTapGesture {
        isPopoverPresented.toggle()
      }
      .help("Click to view usage details")
      .popover(isPresented: $isPopoverPresented) {
        UsagePopoverView(
          isPresented: $isPopoverPresented,
          selectedProvider: $selectedProvider
        )
      }
    }
  }

  @ViewBuilder
  private func providerBar(_ provider: UsageProvider) -> some View {
    let status = usageService.status(for: provider)

    HStack(spacing: 4) {
      Text(provider.displayName)
        .appFont(size: 10, weight: .medium)
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
            .appFont(size: 9)
            .monospacedDigit()
            .foregroundColor(.secondary)
        } else {
          Text("--")
            .appFont(size: 9)
            .foregroundColor(.secondary)
        }

      case .failed:
        Image(systemName: "exclamationmark.triangle.fill")
          .appFont(size: 8)
          .foregroundColor(.orange)

      case .tokenExpired:
        Image(systemName: "key.slash")
          .appFont(size: 9)
          .foregroundColor(.orange)

      case .unavailable:
        Image(systemName: "minus.circle")
          .appFont(size: 8)
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
}

// MARK: - Usage Popover

/// Full usage detail popover shown on click.
struct UsagePopoverView: View {
  @Binding var isPresented: Bool
  @Binding var selectedProvider: UsageProvider

  private var usageService: UsageService { UsageService.shared }

  var body: some View {
    VStack(spacing: 0) {
      /// Header: provider tabs + close button.
      HStack(alignment: .center) {
        Picker("Provider", selection: $selectedProvider) {
          ForEach(UsageProvider.statusBarProviders, id: \.self) { provider in
            Text(provider.displayName).tag(provider)
          }
        }
        .pickerStyle(.segmented)

        Button {
          isPresented = false
        } label: {
          Image(systemName: "xmark")
            .appFont(size: 9, weight: .medium)
            .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
      }
      .padding(.horizontal, 12)
      .padding(.top, 12)
      .padding(.bottom, 8)

      Divider()

      /// Content area. Right padding is wider so the AppKit overlay
      /// scrollbar doesn't clip trailing numeric values.
      ScrollView {
        popoverContent(provider: selectedProvider)
          .padding(.leading, 12)
          .padding(.trailing, 12)
          .padding(.vertical, 12)
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

      case .tokenExpired:
        tokenExpiredView(provider: provider)

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
        .appFont(size: 11, weight: .medium)
        .foregroundColor(.primary)

      Spacer()

      Text(snapshot.sourceLabel)
        .appFont(size: 9, weight: .medium)
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
            .appFont(size: 11)
            .foregroundColor(.primary)

          Spacer()

          if let limit = snapshot.limit {
            Text("/ \(limit)")
              .appFont(size: 11)
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

    if !snapshot.events.isEmpty {
      Divider()
        .padding(.vertical, 4)

      Text("Usage by model")
        .appFont(size: 10, weight: .semibold)
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)

      ForEach(Array(snapshot.events.enumerated()), id: \.element.id) { index, event in
        HStack(spacing: 6) {
          Text("\(index + 1).")
            .appFont(size: 10, design: .monospaced)
            .foregroundColor(.secondary)
            .frame(width: 16, alignment: .leading)

          Text(event.model)
            .appFont(size: 10)
            .foregroundColor(.primary)
            .lineLimit(1)
            .truncationMode(.tail)

          Spacer(minLength: 4)

          Text(String(format: "$%.2f", event.dollars))
            .appFont(size: 10, design: .monospaced)
            .foregroundColor(event.dollars > 0 ? .primary : .secondary)
        }
      }
    }

    Divider()
      .padding(.vertical, 4)

    /// Footer: timestamp + refresh.
    HStack {
      Text("Updated \(snapshot.fetchedAt.formatted(.dateTime.hour().minute().second()))")
        .appFont(size: 9)
        .foregroundColor(.secondary.opacity(0.7))

      Spacer()

      Button {
        Task {
          await usageService.fetch(provider: provider)
        }
      } label: {
        HStack(spacing: 4) {
          Image(systemName: "arrow.clockwise")
            .appFont(size: 9)

          Text("Refresh")
            .appFont(size: 10)
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
        .appFont(size: 11)
        .foregroundColor(.secondary)
    }
    .padding(.vertical, 20)
  }

  @ViewBuilder
  private func errorView(_ message: String, provider: UsageProvider) -> some View {
    VStack(spacing: 8) {
      HStack(spacing: 6) {
        Image(systemName: "exclamationmark.triangle")
          .appFont(size: 11)
          .foregroundColor(.orange)

        Text(message)
          .appFont(size: 11)
          .foregroundColor(.secondary)
          .lineLimit(3)
      }

      Button {
        Task {
          await usageService.fetch(provider: provider)
        }
      } label: {
        Text("Retry")
          .appFont(size: 10)
      }
      .buttonStyle(.bordered)
      .controlSize(.small)
    }
    .padding(.vertical, 12)
  }

  @ViewBuilder
  private func tokenExpiredView(provider: UsageProvider) -> some View {
    VStack(spacing: 10) {
      Image(systemName: "key.slash")
        .appFont(size: 24)
        .foregroundColor(.orange)

      Text("\(provider.displayName) usage data is unavailable because the OAuth token in Keychain has expired or been refreshed.")
        .appFont(size: 11)
        .foregroundColor(.secondary)
        .multilineTextAlignment(.center)
        .lineLimit(4)

      Text("Click Renew to re-read the token from Keychain. macOS will ask for permission.")
        .appFont(size: 10)
        .foregroundColor(.secondary.opacity(0.7))
        .multilineTextAlignment(.center)
        .lineLimit(3)

      Button {
        Task {
          await usageService.renewKeychainToken(provider: provider)
        }
      } label: {
        HStack(spacing: 4) {
          Image(systemName: "key.viewfinder")
            .appFont(size: 10)

          Text("Renew")
            .appFont(size: 11)
        }
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
        .appFont(size: 11)
        .foregroundColor(.secondary)

      Text(reason)
        .appFont(size: 11)
        .foregroundColor(.secondary)
        .lineLimit(2)
    }
    .padding(.vertical, 20)
  }

  @ViewBuilder
  private func noDataView() -> some View {
    HStack(spacing: 6) {
      Image(systemName: "chart.bar")
        .appFont(size: 11)
        .foregroundColor(.secondary)

      Text("No usage data")
        .appFont(size: 11)
        .foregroundColor(.secondary)
    }
    .padding(.vertical, 20)
  }

  @ViewBuilder
  private func disabledView() -> some View {
    VStack(spacing: 4) {
      HStack(spacing: 6) {
        Image(systemName: "chart.bar")
          .appFont(size: 11)
          .foregroundColor(.secondary)

        Text("Usage stats disabled")
          .appFont(size: 11)
          .foregroundColor(.secondary)
      }

      Text("Enable in Settings > Usage")
        .appFont(size: 10)
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
