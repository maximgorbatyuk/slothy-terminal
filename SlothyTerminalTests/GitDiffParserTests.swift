import Testing

@testable import SlothyTerminalLib

@Suite("Git Diff Parser")
struct GitDiffParserTests {
  private let service = GitWorkingTreeService.shared

  @Test("Unified diff parses into side-by-side rows")
  func parseUnifiedDiff() {
    let diff = """
    @@ -1,3 +1,3 @@
     line 1
    -old value
    +new value
     line 3
    """

    let rows = service.parseUnifiedDiff(diff)

    #expect(rows.count == 3)
    #expect(rows[1].oldLineNumber == 2)
    #expect(rows[1].newLineNumber == 2)
    #expect(rows[1].leftText == "old value")
    #expect(rows[1].rightText == "new value")
    #expect(rows[1].kind == .modification)
  }

  @Test("Binary diff returns non-text placeholder state")
  func parseBinaryDiff() {
    let diff = "Binary files a/logo.png and b/logo.png differ"
    let result = service.parseDiffOutput(diff)

    #expect(result.isBinary)
    #expect(result.rows.isEmpty)
  }

  @Test("Untracked file content is rendered as additions")
  func untrackedFileContentRendersAsAdditions() {
    let result = service.makeUntrackedDiffDocument(
      from: "line 1\nline 2"
    )

    #expect(result.isBinary == false)
    #expect(result.rows.count == 2)
    #expect(result.rows[0].kind == .addition)
    #expect(result.rows[0].oldLineNumber == nil)
    #expect(result.rows[0].newLineNumber == 1)
    #expect(result.rows[0].rightText == "line 1")
    #expect(result.rows[1].kind == .addition)
    #expect(result.rows[1].newLineNumber == 2)
    #expect(result.rows[1].rightText == "line 2")
  }
}
