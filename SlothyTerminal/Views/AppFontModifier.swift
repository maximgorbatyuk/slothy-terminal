import SwiftUI

extension View {
  /// Applies the configured app UI font as the environment default.
  ///
  /// Caveat: SwiftUI text with an explicit semantic font (`.title`, `.headline`,
  /// `.caption`, etc.) keeps that style and ignores the environment override.
  /// Native AppKit chrome (window title bar, menu bar) also uses the system font.
  /// Most app text uses explicit sizes via `.appFont(size:)` (below), which
  /// respects the configured font directly and is not subject to this caveat.
  ///
  /// Always returns the same view type (`.font(_:)` with an optional `Font`) so
  /// switching `AppFont` at runtime does not change the structural identity of
  /// the subtree. A `@ViewBuilder` with `if let` branches would wrap the result
  /// in `_ConditionalContent`, which destroys child `@State` (e.g. the selected
  /// section in `SettingsView`) every time the font changes.
  func appFont(_ font: AppFont) -> some View {
    let resolved: Font? = font.fontName.map { name in
      Font.custom(name, size: NSFont.systemFontSize)
    }

    return self.font(resolved)
  }

  /// Drop-in replacement for `.font(.system(size:weight:design:))` that swaps
  /// to the configured app font (JetBrains Mono) when selected. Falls back to
  /// the system font with the requested design (e.g. `.monospaced`) otherwise.
  func appFont(
    size: CGFloat,
    weight: Font.Weight = .regular,
    design: Font.Design = .default
  ) -> some View {
    modifier(AppFontSizedModifier(size: size, weight: weight, design: design))
  }

  /// Drop-in replacement for `.font(.body)` / `.font(.caption)` / etc. Uses the
  /// custom font at an equivalent size+weight when JetBrains Mono is selected,
  /// preserving Dynamic Type scaling via `relativeTo:`. Falls back to the
  /// native semantic style for system font.
  func appFont(_ style: Font.TextStyle) -> some View {
    modifier(AppFontStyleModifier(style: style))
  }
}

/// Reads `ConfigManager.shared.config.appFont` (an `@Observable`) so views
/// re-render when the user changes the font in Settings.
///
/// `design` is only consulted on the system-font fallback path. JetBrains Mono
/// is already monospaced and ignores `design`. If a future caller passes
/// `design: .rounded` expecting an SF Rounded fallback, they'll get a
/// non-rounded JetBrains Mono when the picker is set to JetBrains Mono — that
/// is the documented behavior, not a bug.
private struct AppFontSizedModifier: ViewModifier {
  let size: CGFloat
  let weight: Font.Weight
  let design: Font.Design

  private let configManager = ConfigManager.shared

  func body(content: Content) -> some View {
    if let name = configManager.config.appFont.fontName {
      content.font(.custom(name, size: size).weight(weight))
    } else {
      content.font(.system(size: size, weight: weight, design: design))
    }
  }
}

/// Maps `Font.TextStyle` to the matching custom-font size at runtime via
/// `NSFont.preferredFont(forTextStyle:)`, so values stay in sync with macOS
/// SDK changes. Uses `Font.custom(_:size:relativeTo:)` so Dynamic Type still
/// scales for these semantic styles. (The sized variant above intentionally
/// does NOT scale, so layout-critical chrome stays predictable.)
private struct AppFontStyleModifier: ViewModifier {
  let style: Font.TextStyle

  private let configManager = ConfigManager.shared

  func body(content: Content) -> some View {
    if let name = configManager.config.appFont.fontName {
      let size = NSFont.preferredFont(forTextStyle: Self.nsTextStyle(for: style)).pointSize
      content.font(.custom(name, size: size, relativeTo: style).weight(Self.weight(for: style)))
    } else {
      content.font(.system(style))
    }
  }

  private static func nsTextStyle(for style: Font.TextStyle) -> NSFont.TextStyle {
    switch style {
    case .largeTitle:
      return .largeTitle

    case .title:
      return .title1

    case .title2:
      return .title2

    case .title3:
      return .title3

    case .headline:
      return .headline

    case .body:
      return .body

    case .callout:
      return .callout

    case .subheadline:
      return .subheadline

    case .footnote:
      return .footnote

    case .caption:
      return .caption1

    case .caption2:
      return .caption2

    @unknown default:
      return .body
    }
  }

  /// `Font.TextStyle` carries no weight info; only `.headline` is semibold by
  /// convention on macOS.
  private static func weight(for style: Font.TextStyle) -> Font.Weight {
    style == .headline ? .semibold : .regular
  }
}
