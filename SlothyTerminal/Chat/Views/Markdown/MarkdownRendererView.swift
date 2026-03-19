import SwiftUI

/// Main markdown renderer. Switches between cheap inline-only mode while
/// streaming and full block-level rendering once the message is complete.
struct MarkdownRendererView: View {
  let text: String
  let isStreaming: Bool

  @State private var cachedBlocks: [MarkdownBlock] = []
  @State private var cachedText: String = ""

  var body: some View {
    if isStreaming {
      InlineMarkdownView(text: text)
    } else {
      VStack(alignment: .leading, spacing: 8) {
        ForEach(Array(cachedBlocks.enumerated()), id: \.offset) { _, block in
          blockView(for: block)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .onAppear {
        reparse()
      }
      .onChange(of: text) {
        reparse()
      }
    }
  }

  private func reparse() {
    guard text != cachedText else {
      return
    }

    cachedText = text
    cachedBlocks = MarkdownBlockParser.parse(text)
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
