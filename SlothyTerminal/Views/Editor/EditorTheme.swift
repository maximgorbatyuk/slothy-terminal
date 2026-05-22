import AppKit
import SwiftUI

/// Maps tree-sitter capture names from `highlights.scm` to `NSColor`.
/// Capture names use dot-separated hierarchies (e.g. `function.method`,
/// `keyword.function`); `EditorTheme.color(for:)` resolves the longest
/// matching prefix so themes don't need to enumerate every variant.
///
/// The theme is chosen by file type, not by the system appearance — see
/// `EditorTheme.resolve(for:)`. Reading-oriented files (`.md`, `.txt`,
/// etc.) open on a light canvas with dark text. Everything else opens on
/// a dark canvas with light/colored text. The editor forces its own
/// SwiftUI `colorScheme` so STTextView's internal `.background(.background)`
/// and the gutter's `NSColor.secondaryLabelColor` match.
struct EditorTheme {
  let colorsByCapture: [String: NSColor]
  let foreground: NSColor
  let background: NSColor
  /// SwiftUI `ColorScheme` to force on the editor subtree so STTextView's
  /// built-in adaptive colors (background, cursor, gutter label) resolve
  /// against the same appearance the theme assumes.
  let colorScheme: ColorScheme

  static let light = EditorTheme(
    foreground: NSColor(calibratedRed: 0.10, green: 0.10, blue: 0.12, alpha: 1.0),
    background: NSColor(calibratedRed: 0.98, green: 0.98, blue: 0.97, alpha: 1.0),
    colorScheme: .light,
    palette: [
      "keyword":              NSColor(calibratedRed: 0.65, green: 0.13, blue: 0.59, alpha: 1.0),
      "operator":             NSColor(calibratedRed: 0.10, green: 0.10, blue: 0.12, alpha: 1.0),
      "string":               NSColor(calibratedRed: 0.78, green: 0.15, blue: 0.15, alpha: 1.0),
      "comment":              NSColor(calibratedRed: 0.35, green: 0.35, blue: 0.40, alpha: 1.0),
      "number":               NSColor(calibratedRed: 0.10, green: 0.36, blue: 0.62, alpha: 1.0),
      "function":             NSColor(calibratedRed: 0.18, green: 0.36, blue: 0.62, alpha: 1.0),
      "function.method":      NSColor(calibratedRed: 0.18, green: 0.36, blue: 0.62, alpha: 1.0),
      "constructor":          NSColor(calibratedRed: 0.18, green: 0.36, blue: 0.62, alpha: 1.0),
      "type":                 NSColor(calibratedRed: 0.07, green: 0.49, blue: 0.46, alpha: 1.0),
      "variable":             NSColor(calibratedRed: 0.10, green: 0.10, blue: 0.12, alpha: 1.0),
      "variable.parameter":   NSColor(calibratedRed: 0.40, green: 0.20, blue: 0.40, alpha: 1.0),
      "variable.builtin":     NSColor(calibratedRed: 0.65, green: 0.13, blue: 0.59, alpha: 1.0),
      "constant":             NSColor(calibratedRed: 0.10, green: 0.36, blue: 0.62, alpha: 1.0),
      "constant.builtin":     NSColor(calibratedRed: 0.65, green: 0.13, blue: 0.59, alpha: 1.0),
      "punctuation":          NSColor(calibratedRed: 0.30, green: 0.30, blue: 0.35, alpha: 1.0),
      "punctuation.bracket":  NSColor(calibratedRed: 0.30, green: 0.30, blue: 0.35, alpha: 1.0),
      "punctuation.delimiter": NSColor(calibratedRed: 0.30, green: 0.30, blue: 0.35, alpha: 1.0),
      "attribute":            NSColor(calibratedRed: 0.50, green: 0.30, blue: 0.10, alpha: 1.0)
    ]
  )

  static let dark = EditorTheme(
    foreground: NSColor(calibratedRed: 0.86, green: 0.86, blue: 0.90, alpha: 1.0),
    background: NSColor(calibratedRed: 0.12, green: 0.13, blue: 0.16, alpha: 1.0),
    colorScheme: .dark,
    palette: [
      "keyword":              NSColor(calibratedRed: 0.82, green: 0.50, blue: 0.84, alpha: 1.0),
      "operator":             NSColor(calibratedRed: 0.86, green: 0.86, blue: 0.90, alpha: 1.0),
      "string":               NSColor(calibratedRed: 0.95, green: 0.58, blue: 0.42, alpha: 1.0),
      "comment":              NSColor(calibratedRed: 0.55, green: 0.58, blue: 0.65, alpha: 1.0),
      "number":               NSColor(calibratedRed: 0.45, green: 0.78, blue: 0.92, alpha: 1.0),
      "function":             NSColor(calibratedRed: 0.55, green: 0.80, blue: 0.95, alpha: 1.0),
      "function.method":      NSColor(calibratedRed: 0.55, green: 0.80, blue: 0.95, alpha: 1.0),
      "constructor":          NSColor(calibratedRed: 0.55, green: 0.80, blue: 0.95, alpha: 1.0),
      "type":                 NSColor(calibratedRed: 0.60, green: 0.92, blue: 0.86, alpha: 1.0),
      "variable":             NSColor(calibratedRed: 0.86, green: 0.86, blue: 0.90, alpha: 1.0),
      "variable.parameter":   NSColor(calibratedRed: 0.95, green: 0.72, blue: 0.86, alpha: 1.0),
      "variable.builtin":     NSColor(calibratedRed: 0.82, green: 0.50, blue: 0.84, alpha: 1.0),
      "constant":             NSColor(calibratedRed: 0.45, green: 0.78, blue: 0.92, alpha: 1.0),
      "constant.builtin":     NSColor(calibratedRed: 0.82, green: 0.50, blue: 0.84, alpha: 1.0),
      "punctuation":          NSColor(calibratedRed: 0.65, green: 0.65, blue: 0.72, alpha: 1.0),
      "punctuation.bracket":  NSColor(calibratedRed: 0.65, green: 0.65, blue: 0.72, alpha: 1.0),
      "punctuation.delimiter": NSColor(calibratedRed: 0.65, green: 0.65, blue: 0.72, alpha: 1.0),
      "attribute":            NSColor(calibratedRed: 0.95, green: 0.78, blue: 0.55, alpha: 1.0)
    ]
  )

  init(
    foreground: NSColor,
    background: NSColor,
    colorScheme: ColorScheme,
    palette: [String: NSColor]
  ) {
    self.foreground = foreground
    self.background = background
    self.colorScheme = colorScheme
    self.colorsByCapture = palette
  }

  /// Returns the color for a capture name, walking from the most specific
  /// dot-segment to the least (e.g. `function.method.static` →
  /// `function.method` → `function`). Falls back to the theme foreground.
  func color(for captureName: String) -> NSColor {
    var components = captureName.split(separator: ".").map(String.init)
    while !components.isEmpty {
      let key = components.joined(separator: ".")
      if let color = colorsByCapture[key] {
        return color
      }

      components.removeLast()
    }

    return foreground
  }

  /// Selects the theme by file type. Prose / plain-text files open on
  /// a paper-white canvas; everything else (code, configs, unknown
  /// types) opens on the dark canvas.
  ///
  /// The choice is deliberately not coupled to the system or app
  /// appearance: a Swift file should look like code regardless of
  /// whether the user prefers a light desktop, and a Markdown draft
  /// should look like prose regardless of whether the desktop is dark.
  static func resolve(for url: URL) -> EditorTheme {
    isReadingExtension(url.pathExtension.lowercased()) ? .light : .dark
  }

  private static func isReadingExtension(_ ext: String) -> Bool {
    switch ext {
    case "md",
         "markdown",
         "txt":
      return true

    default:
      return false
    }
  }
}
