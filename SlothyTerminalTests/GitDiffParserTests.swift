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
}
