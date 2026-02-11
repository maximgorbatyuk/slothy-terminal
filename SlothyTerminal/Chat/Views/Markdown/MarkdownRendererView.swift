import SwiftUI

/// Main markdown renderer. Switches between cheap inline-only mode while
/// streaming and full block-level rendering once the message is complete.
struct MarkdownRendererView: View {
  let text: String
  let isStreaming: Bool

  var body: some View {
    if isStreaming {
      InlineMarkdownView(text: text)
    } else {
      VStack(alignment: .leading, spacing: 8) {
        let blocks = MarkdownBlockParser.parse(text)

        ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
          blockView(for: block)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  @ViewBuilder
  private func blockView(for block: MarkdownBlock) -> some View {
    switch block {
    case .heading(let level, let text):
      MarkdownHeadingView(level: level, text: text)

    case .codeBlock(let language, let code):
      CodeBlockView(language: language, code: code)

    case .paragraph(let text):
      InlineMarkdownView(text: text)

    case .unorderedList(let items):
      MarkdownUnorderedListView(items: items)

    case .orderedList(let items):
      MarkdownOrderedListView(items: items)

    case .blockquote(let text):
      MarkdownBlockquoteView(text: text)

    case .thematicBreak:
      Divider()

    case .table(let headers, let rows):
      MarkdownTableView(headers: headers, rows: rows)
    }
  }
}
