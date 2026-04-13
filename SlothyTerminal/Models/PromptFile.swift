import Foundation

/// A markdown or text file discovered under `<workspace>/docs/prompts/`.
struct PromptFile: Identifiable, Equatable {
  var id: URL { url }

  /// File name including extension (e.g. `intro.md`).
  let fileName: String

  /// Absolute file URL.
  let url: URL

  /// Path relative to `docs/prompts/` (e.g. `subfolder/intro.md`).
  let relativePath: String

  /// Lowercased extension (`md` or `txt`).
  let fileExtension: String
}
