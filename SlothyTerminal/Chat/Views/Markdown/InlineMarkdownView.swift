import SwiftUI

/// Renders inline markdown (bold, italic, code, links) via `AttributedString`.
/// Falls back to plain text if parsing fails.
/// Font size is inherited from the parent view's environment.
struct InlineMarkdownView: View {
  let text: String

  var body: some View {
    if let attributed = try? AttributedString(
      markdown: text,
      options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    ) {
      Text(attributed)
        .frame(maxWidth: .infinity, alignment: .leading)
    } else {
      Text(text)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}
