import Foundation

enum GitDiffRowKind: String, Equatable {
  case context
  case addition
  case deletion
  case modification
}

struct GitDiffRow: Equatable {
  let oldLineNumber: Int?
  let newLineNumber: Int?
  let leftText: String
  let rightText: String
  let kind: GitDiffRowKind
}

struct GitDiffDocument: Equatable {
  let rows: [GitDiffRow]
  let isBinary: Bool

  init(
    rows: [GitDiffRow] = [],
    isBinary: Bool = false
  ) {
    self.rows = rows
    self.isBinary = isBinary
  }
}
