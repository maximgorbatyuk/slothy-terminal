import SwiftUI

/// Renders text as markdown using AttributedString with text selection support.
/// Falls back to plain text if markdown parsing fails.
struct MarkdownTextView: View {
  let text: String

  var body: some View {
    if let attributed = try? AttributedString(
      markdown: text,
      options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    ) {
      Text(attributed)
        .textSelection(.enabled)
    } else {
      Text(text)
        .textSelection(.enabled)
    }
  }
}
