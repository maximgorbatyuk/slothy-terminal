import SwiftUI

/// Renders text as markdown. Delegates to `MarkdownRendererView` which uses
/// cheap inline-only rendering while streaming, and full block-level
/// rendering once the message is complete.
struct MarkdownTextView: View {
  let text: String
  var isStreaming: Bool = false
  var fontSize: CGFloat = 13

  var body: some View {
    MarkdownRendererView(text: text, isStreaming: isStreaming)
      .font(.system(size: fontSize))
  }
}
