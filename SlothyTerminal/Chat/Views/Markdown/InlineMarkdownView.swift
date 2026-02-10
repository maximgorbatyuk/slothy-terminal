import SwiftUI

/// Renders inline markdown (bold, italic, code, links) via `AttributedString`.
/// Falls back to plain text if parsing fails.
struct InlineMarkdownView: View {
  let text: String

  var body: some View {
    if let attributed = try? AttributedString(
      markdown: text,
      options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    ) {
      Text(attributed)
        .font(.system(size: 13))
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    } else {
      Text(text)
        .font(.system(size: 13))
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}
