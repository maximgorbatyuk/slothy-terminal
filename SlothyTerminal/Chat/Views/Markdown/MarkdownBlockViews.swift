import SwiftUI

// MARK: - Heading

/// Renders a markdown heading sized by level (1-6).
struct MarkdownHeadingView: View {
  let level: Int
  let text: String

  private var fontSize: CGFloat {
    switch level {
    case 1: 24
    case 2: 20
    case 3: 17
    case 4: 15
    case 5: 13
    default: 12
    }
  }

  var body: some View {
    Text(text)
      .font(.system(size: fontSize, weight: .bold))
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.bottom, level <= 2 ? 4 : 2)
  }
}

// MARK: - Unordered list

/// Renders an unordered list with bullet points, supporting nested items.
struct MarkdownUnorderedListView: View {
  let items: [ListItem]
  var indentLevel: Int = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      ForEach(Array(items.enumerated()), id: \.offset) { _, item in
        HStack(alignment: .top, spacing: 6) {
          Text(bulletCharacter)
            .foregroundColor(.secondary)

          InlineMarkdownView(text: item.text)
        }
        .padding(.leading, CGFloat(indentLevel) * 16)

        if !item.children.isEmpty {
          MarkdownUnorderedListView(items: item.children, indentLevel: indentLevel + 1)
        }
      }
    }
  }

  private var bulletCharacter: String {
    switch indentLevel {
    case 0: "\u{2022}"
    case 1: "\u{25E6}"
    default: "\u{2023}"
    }
  }
}

// MARK: - Ordered list

/// Renders an ordered list with numbers, supporting nested items.
struct MarkdownOrderedListView: View {
  let items: [ListItem]
  var indentLevel: Int = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      ForEach(Array(items.enumerated()), id: \.offset) { index, item in
        HStack(alignment: .top, spacing: 6) {
          Text("\(index + 1).")
            .foregroundColor(.secondary)
            .frame(minWidth: 20, alignment: .trailing)

          InlineMarkdownView(text: item.text)
        }
        .padding(.leading, CGFloat(indentLevel) * 16)

        if !item.children.isEmpty {
          MarkdownOrderedListView(items: item.children, indentLevel: indentLevel + 1)
        }
      }
    }
  }
}

// MARK: - Blockquote

/// Renders a blockquote with a left accent border.
struct MarkdownBlockquoteView: View {
  let text: String

  var body: some View {
    HStack(alignment: .top, spacing: 0) {
      RoundedRectangle(cornerRadius: 1)
        .fill(Color.orange.opacity(0.6))
        .frame(width: 3)

      InlineMarkdownView(text: text)
        .padding(.leading, 12)
        .padding(.vertical, 4)
    }
    .padding(.vertical, 2)
  }
}

// MARK: - Table

/// Renders a markdown table with header row and data rows.
struct MarkdownTableView: View {
  let headers: [String]
  let rows: [[String]]

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 0) {
        ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
          Text(header)
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
      }

      Divider()

      ForEach(Array(rows.enumerated()), id: \.offset) { rowIdx, row in
        HStack(spacing: 0) {
          ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
            Text(cell)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.horizontal, 8)
              .padding(.vertical, 4)
          }
        }

        if rowIdx < rows.count - 1 {
          Divider().opacity(0.5)
        }
      }
    }
    .background(Color.white.opacity(0.04))
    .cornerRadius(6)
  }
}
