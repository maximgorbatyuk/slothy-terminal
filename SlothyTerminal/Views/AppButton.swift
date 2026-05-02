import SwiftUI

/// Plain-text button whose label honors the configured app font.
///
/// Macos `Button("text") { ... }` rendered with `.borderedProminent` (and
/// other NSButton-backed styles) ignores the SwiftUI environment font for
/// string labels. `AppButton` wraps the labeled-closure form so the inner
/// `Text` carries an explicit `.appFont(size:weight:)`.
///
/// Caller-applied modifiers compose normally:
/// ```
/// AppButton("Save", action: save)
///   .buttonStyle(.borderedProminent)
///   .disabled(!canSave)
///   .keyboardShortcut(.return, modifiers: .command)
/// ```
struct AppButton: View {
  let title: String
  var size: CGFloat
  var weight: Font.Weight
  let action: () -> Void

  init(
    _ title: String,
    size: CGFloat = 13,
    weight: Font.Weight = .regular,
    action: @escaping () -> Void
  ) {
    self.title = title
    self.size = size
    self.weight = weight
    self.action = action
  }

  var body: some View {
    Button(action: action) {
      Text(title)
        .appFont(size: size, weight: weight)
    }
  }
}
