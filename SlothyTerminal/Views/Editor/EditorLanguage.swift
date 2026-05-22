import Foundation
import OSLog
import SwiftTreeSitter
import TreeSitterSwift
import TreeSitterMarkdown

/// Languages with tree-sitter grammars bundled in the app. Unknown
/// extensions fall through to plain text — `EditorLanguage.resolve`
/// returns `nil` for them.
enum EditorLanguage {
  case swift
  case markdown

  /// Resolves the language from a file URL's extension.
  static func resolve(for url: URL) -> EditorLanguage? {
    switch url.pathExtension.lowercased() {
    case "swift":
      return .swift

    case "md", "markdown":
      return .markdown

    default:
      return nil
    }
  }

  /// Underlying tree-sitter `Language`. Constructed each call — Language is
  /// cheap to create from a static C grammar pointer.
  var treeSitterLanguage: Language {
    switch self {
    case .swift:
      return Language(language: tree_sitter_swift())

    case .markdown:
      return Language(language: tree_sitter_markdown())
    }
  }

  /// Loads the package's bundled `queries/highlights.scm` text. Returns nil
  /// if the resource bundle can't be located (Stage 1 fallback: render as
  /// plain text without crashing).
  func loadHighlightsQuery() -> String? {
    let bundleHint: String
    switch self {
    case .swift:
      bundleHint = "TreeSitterSwift"

    case .markdown:
      bundleHint = "TreeSitterMarkdown"
    }

    if let bundle = EditorLanguage.bundleContainingHighlights(for: bundleHint) {
      if let url = bundle.url(forResource: "highlights", withExtension: "scm", subdirectory: "queries"),
         let text = try? String(contentsOf: url, encoding: .utf8)
      {
        return text
      }

      if let url = bundle.url(forResource: "highlights", withExtension: "scm"),
         let text = try? String(contentsOf: url, encoding: .utf8)
      {
        return text
      }
    }

    Logger.app.warning("highlights.scm not found for \(String(describing: self)) - rendering as plain text")
    return nil
  }

  /// Locates an SPM-generated resource bundle matching `hint` and containing
  /// a `queries/highlights.scm` resource.
  ///
  /// Match uses an EXACT suffix on the bundle's `lastPathComponent` so the
  /// hint `"TreeSitterMarkdown"` does not collide with the sibling
  /// `TreeSitterMarkdownInline` bundle (both have `queries/highlights.scm`
  /// but expose different grammars).
  private static func bundleContainingHighlights(for hint: String) -> Bundle? {
    let scanned: [Bundle]
    if let resources = Bundle.main.resourceURL,
       let entries = try? FileManager.default.contentsOfDirectory(at: resources, includingPropertiesForKeys: nil)
    {
      scanned = entries
        .filter { $0.pathExtension == "bundle" }
        .compactMap(Bundle.init(url:))
    } else {
      scanned = []
    }

    for bundle in Bundle.allBundles + scanned {
      let component = bundle.bundleURL.lastPathComponent
      guard EditorLanguage.bundleName(component, matchesHint: hint),
            bundle.url(forResource: "highlights", withExtension: "scm", subdirectory: "queries") != nil
      else {
        continue
      }

      return bundle
    }

    return nil
  }

  /// True when `name` is `<hint>.bundle` or matches the SPM convention
  /// `<package>_<hint>.bundle`. Rejects strict-substring matches such as
  /// `<package>_<hint>Inline.bundle` so we never load an inline grammar's
  /// queries for the block grammar.
  private static func bundleName(_ name: String, matchesHint hint: String) -> Bool {
    guard name.hasSuffix(".bundle") else {
      return false
    }

    let stem = String(name.dropLast(".bundle".count))

    if stem == hint {
      return true
    }

    if let underscoreRange = stem.range(of: "_", options: .backwards) {
      let target = stem[underscoreRange.upperBound...]
      return target == hint
    }

    return false
  }
}
