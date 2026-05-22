import AppKit
import STTextView
import SwiftTreeSitter

/// STTextView plugin that drives tree-sitter syntax highlighting AND the
/// theme-aware baseline foreground for the editor.
///
/// Parses the full document on each change (no incremental parsing in v1 —
/// fine inside the 10 MB file-size cap) and applies rendering attributes
/// from the configured theme. Rendering attributes don't modify the text
/// storage, so they don't trigger dirty-state changes in EditorTabView.
///
/// `language` is optional: when `nil` the plugin still paints the theme
/// foreground across the entire document so unknown file types stay
/// readable in dark mode (STTextView's built-in `NSColor.textColor`
/// default does not reliably re-resolve when the SwiftUI window's
/// `preferredColorScheme` flips). Capture-driven coloring only runs when
/// a grammar is set. `Coordinator.updateLanguage(_:)` can flip it on/off
/// in place — which is the only working way to change grammar after
/// install, because `STTextView.addPlugin` is one-way (no remove) and
/// the SwiftUI wrapper only calls `addPlugin` in `makeNSView`.
final class SyntaxHighlightingPlugin: STPlugin {
  private let initialLanguage: EditorLanguage?
  private let initialTheme: EditorTheme
  private(set) var coordinator: Coordinator?

  init(language: EditorLanguage?, theme: EditorTheme) {
    self.initialLanguage = language
    self.initialTheme = theme
  }

  func makeCoordinator(context: CoordinatorContext) -> Coordinator {
    let coordinator = Coordinator(
      language: initialLanguage,
      theme: initialTheme,
      textView: context.textView
    )
    self.coordinator = coordinator
    return coordinator
  }

  func setUp(context: any Context) {
    let coordinator = context.coordinator
    coordinator.applyHighlights()

    context.events.onDidChangeText { _, _ in
      coordinator.scheduleHighlights()
    }
  }

  @MainActor
  final class Coordinator {
    private weak var textView: STTextView?
    private var theme: EditorTheme
    private var parser: Parser
    private var query: Query?
    private var language: EditorLanguage?
    private var pendingHighlightTask: Task<Void, Never>?

    init(language: EditorLanguage?, theme: EditorTheme, textView: STTextView) {
      self.textView = textView
      self.theme = theme
      self.language = language

      let parser = Parser()
      if let language {
        try? parser.setLanguage(language.treeSitterLanguage)
      }
      self.parser = parser

      if let language {
        self.query = Coordinator.makeQuery(for: language)
      } else {
        self.query = nil
      }
    }

    deinit {
      pendingHighlightTask?.cancel()
    }

    func updateTheme(_ theme: EditorTheme) {
      self.theme = theme
      applyHighlights()
    }

    /// Updates the active grammar in place. Passing `nil` disables
    /// capture-driven highlighting and resets the document to the theme
    /// foreground.
    func updateLanguage(_ language: EditorLanguage?) {
      self.language = language

      if let language {
        try? parser.setLanguage(language.treeSitterLanguage)
        query = Coordinator.makeQuery(for: language)
      } else {
        query = nil
      }

      applyHighlights()
    }

    func scheduleHighlights() {
      pendingHighlightTask?.cancel()
      pendingHighlightTask = Task { @MainActor [weak self] in
        try? await Task.sleep(nanoseconds: 50_000_000)
        guard let self,
              !Task.isCancelled
        else {
          return
        }

        self.applyHighlights()
      }
    }

    /// Repaints the document. Always applies the theme foreground as the
    /// baseline so unknown file types stay readable; only runs the
    /// tree-sitter capture pass when a grammar+query are loaded.
    func applyHighlights() {
      guard let textView,
            let text = textView.text,
            !text.isEmpty
      else {
        return
      }

      let fullRange = NSRange(location: 0, length: (text as NSString).length)

      textView.removeRenderingAttribute(.foregroundColor, range: fullRange)
      textView.addRenderingAttributes([.foregroundColor: theme.foreground], range: fullRange)

      guard language != nil,
            let query,
            let tree = parser.parse(text),
            let rootNode = tree.rootNode
      else {
        return
      }

      /// Collect captures into a flat list sorted by location so later
      /// captures (more specific matches in tree-sitter's query order)
      /// overwrite earlier ones at the same range — matching how editors
      /// like Helix and Zed render layered highlights.
      var captures: [(NSRange, NSColor)] = []
      let cursor = query.execute(node: rootNode, in: tree)
      while let match = cursor.next() {
        for capture in match.captures {
          guard let name = capture.name else {
            continue
          }

          let color = theme.color(for: name)
          let range = capture.range

          if range.length > 0 && NSMaxRange(range) <= fullRange.length {
            captures.append((range, color))
          }
        }
      }

      for (range, color) in captures {
        textView.addRenderingAttributes([.foregroundColor: color], range: range)
      }
    }

    private static func makeQuery(for language: EditorLanguage) -> Query? {
      guard let queryString = language.loadHighlightsQuery(),
            let data = queryString.data(using: .utf8)
      else {
        return nil
      }

      return try? Query(language: language.treeSitterLanguage, data: data)
    }
  }
}
