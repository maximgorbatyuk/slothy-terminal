import Foundation

/// A parsed block-level element from a markdown string.
enum MarkdownBlock: Equatable {
  case heading(level: Int, text: String)
  case codeBlock(language: String?, code: String)
  case paragraph(String)
  case unorderedList(items: [ListItem])
  case orderedList(items: [ListItem])
  case blockquote(String)
  case thematicBreak
  case table(headers: [String], rows: [[String]])
}

/// A single item in a markdown list, optionally with nested children.
struct ListItem: Equatable {
  let text: String
  let children: [ListItem]
}

/// Splits a markdown string into typed blocks.
/// Uses line-by-line sequential parsing — no external dependencies.
enum MarkdownBlockParser {

  static func parse(_ markdown: String) -> [MarkdownBlock] {
    let lines = markdown.split(
      separator: "\n",
      omittingEmptySubsequences: false
    ).map(String.init)

    var blocks: [MarkdownBlock] = []
    var index = 0

    while index < lines.count {
      let line = lines[index]
      let trimmed = line.trimmingCharacters(in: .whitespaces)

      // MARK: - Blank line

      if trimmed.isEmpty {
        index += 1
        continue
      }

      // MARK: - Fenced code block

      if trimmed.hasPrefix("```") {
        let lang = String(trimmed.dropFirst(3))
          .trimmingCharacters(in: .whitespaces)
        var codeLines: [String] = []
        index += 1

        while index < lines.count && !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
          codeLines.append(lines[index])
          index += 1
        }

        if index < lines.count {
          index += 1
        }

        blocks.append(.codeBlock(
          language: lang.isEmpty ? nil : lang,
          code: codeLines.joined(separator: "\n")
        ))
        continue
      }

      // MARK: - Thematic break

      if isThematicBreak(trimmed) {
        blocks.append(.thematicBreak)
        index += 1
        continue
      }

      // MARK: - Heading

      if let match = trimmed.wholeMatch(of: /^(#{1,6})\s+(.+)/) {
        let level = match.1.count
        let text = String(match.2)
        blocks.append(.heading(level: level, text: text))
        index += 1
        continue
      }

      // MARK: - Blockquote

      if trimmed.hasPrefix("> ") || trimmed == ">" {
        var quoteLines: [String] = []

        while index < lines.count {
          let l = lines[index].trimmingCharacters(in: .whitespaces)

          if l.hasPrefix("> ") {
            quoteLines.append(String(l.dropFirst(2)))
          } else if l == ">" {
            quoteLines.append("")
          } else {
            break
          }

          index += 1
        }

        blocks.append(.blockquote(quoteLines.joined(separator: "\n")))
        continue
      }

      // MARK: - Unordered list

      if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
        let items = parseUnorderedList(lines: lines, index: &index)
        blocks.append(.unorderedList(items: items))
        continue
      }

      // MARK: - Ordered list

      if trimmed.contains(where: { $0.isNumber }),
         trimmed.wholeMatch(of: /^\d+\.\s+.*/) != nil
      {
        let items = parseOrderedList(lines: lines, index: &index)
        blocks.append(.orderedList(items: items))
        continue
      }

      // MARK: - Table

      if trimmed.hasPrefix("|"),
         index + 1 < lines.count
      {
        let nextTrimmed = lines[index + 1].trimmingCharacters(in: .whitespaces)

        if nextTrimmed.hasPrefix("|") && nextTrimmed.contains("---") {
          let (table, newIndex) = parseTable(lines: lines, from: index)

          if let table {
            blocks.append(table)
            index = newIndex
            continue
          }
        }
      }

      // MARK: - Paragraph (default)

      var paraLines: [String] = []

      while index < lines.count {
        let l = lines[index]
        let lt = l.trimmingCharacters(in: .whitespaces)

        if lt.isEmpty || startsNewBlock(lt, nextLine: index + 1 < lines.count ? lines[index + 1] : nil) {
          break
        }

        paraLines.append(l)
        index += 1
      }

      if !paraLines.isEmpty {
        blocks.append(.paragraph(paraLines.joined(separator: "\n")))
      }
    }

    return blocks
  }

  // MARK: - Private helpers

  private static func isThematicBreak(_ line: String) -> Bool {
    let stripped = line.replacingOccurrences(of: " ", with: "")

    guard stripped.count >= 3 else {
      return false
    }

    return stripped.allSatisfy({ $0 == "-" })
      || stripped.allSatisfy({ $0 == "*" })
      || stripped.allSatisfy({ $0 == "_" })
  }

  private static func startsNewBlock(_ line: String, nextLine: String?) -> Bool {
    if line.hasPrefix("```") { return true }
    if line.wholeMatch(of: /^#{1,6}\s+.*/) != nil { return true }
    if line.hasPrefix("> ") || line == ">" { return true }
    if line.hasPrefix("- ") || line.hasPrefix("* ") { return true }
    if line.wholeMatch(of: /^\d+\.\s+.*/) != nil { return true }
    if isThematicBreak(line) { return true }

    if line.hasPrefix("|"),
       let next = nextLine
    {
      let nextTrimmed = next.trimmingCharacters(in: .whitespaces)

      if nextTrimmed.hasPrefix("|") && nextTrimmed.contains("---") {
        return true
      }
    }

    return false
  }

  // MARK: - List parsing

  private static func leadingSpaces(_ line: String) -> Int {
    line.prefix(while: { $0 == " " }).count
  }

  private static func parseUnorderedList(lines: [String], index: inout Int) -> [ListItem] {
    var items: [ListItem] = []
    let baseIndent = leadingSpaces(lines[index])

    while index < lines.count {
      let line = lines[index]
      let indent = leadingSpaces(line)
      let trimmed = line.trimmingCharacters(in: .whitespaces)

      guard !trimmed.isEmpty,
            trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ")
      else {
        break
      }

      if indent < baseIndent {
        break
      }

      if indent == baseIndent {
        let text = String(trimmed.dropFirst(2))
        index += 1

        var children: [ListItem] = []

        if index < lines.count {
          let nextIndent = leadingSpaces(lines[index])
          let nextTrimmed = lines[index].trimmingCharacters(in: .whitespaces)

          if nextIndent > baseIndent && (nextTrimmed.hasPrefix("- ") || nextTrimmed.hasPrefix("* ")) {
            children = parseUnorderedList(lines: lines, index: &index)
          }
        }

        items.append(ListItem(text: text, children: children))
      } else {
        break
      }
    }

    return items
  }

  private static func parseOrderedList(lines: [String], index: inout Int) -> [ListItem] {
    var items: [ListItem] = []
    let baseIndent = leadingSpaces(lines[index])

    while index < lines.count {
      let line = lines[index]
      let indent = leadingSpaces(line)
      let trimmed = line.trimmingCharacters(in: .whitespaces)

      guard !trimmed.isEmpty,
            trimmed.wholeMatch(of: /^\d+\.\s+.*/) != nil
      else {
        break
      }

      if indent < baseIndent {
        break
      }

      if indent == baseIndent {
        let text: String
        if let dotRange = trimmed.firstIndex(of: ".") {
          text = String(trimmed[trimmed.index(after: dotRange)...])
            .trimmingCharacters(in: .whitespaces)
        } else {
          text = trimmed
        }

        index += 1

        var children: [ListItem] = []

        if index < lines.count {
          let nextIndent = leadingSpaces(lines[index])
          let nextTrimmed = lines[index].trimmingCharacters(in: .whitespaces)

          if nextIndent > baseIndent && nextTrimmed.wholeMatch(of: /^\d+\.\s+.*/) != nil {
            children = parseOrderedList(lines: lines, index: &index)
          }
        }

        items.append(ListItem(text: text, children: children))
      } else {
        break
      }
    }

    return items
  }

  // MARK: - Table parsing

  private static func parseTable(lines: [String], from startIndex: Int) -> (MarkdownBlock?, Int) {
    let headers = parseTableRow(lines[startIndex])

    guard !headers.isEmpty else {
      return (nil, startIndex)
    }

    /// Skip header + separator.
    var index = startIndex + 2
    var rows: [[String]] = []

    while index < lines.count {
      let trimmed = lines[index].trimmingCharacters(in: .whitespaces)

      guard trimmed.hasPrefix("|") else {
        break
      }

      rows.append(parseTableRow(lines[index]))
      index += 1
    }

    return (.table(headers: headers, rows: rows), index)
  }

  private static func parseTableRow(_ line: String) -> [String] {
    var trimmed = line.trimmingCharacters(in: .whitespaces)

    if trimmed.hasPrefix("|") {
      trimmed = String(trimmed.dropFirst())
    }

    if trimmed.hasSuffix("|") {
      trimmed = String(trimmed.dropLast())
    }

    return trimmed
      .split(separator: "|", omittingEmptySubsequences: false)
      .map { $0.trimmingCharacters(in: .whitespaces) }
  }
}
