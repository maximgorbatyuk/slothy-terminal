import Foundation
import Testing

@testable import SlothyTerminalLib

@Suite("Commit Graph Parsing")
struct CommitGraphParsingTests {
  private let service = GitStatsService.shared

  @Test("Parse valid multi-commit output")
  func parseValidMultiCommit() {
    let output = """
      abc1234567890abcdef1234567890abcdef123456
      abc1234
      Add feature X
      John Doe
      john@example.com
      2025-06-15 14:23:45 +0200
      def7890567890abcdef1234567890abcdef123456
      HEAD -> main, origin/main
      ---END---
      def7890567890abcdef1234567890abcdef123456
      def7890
      Initial commit
      Jane Smith
      jane@example.com
      2025-06-14 10:00:00 +0000


      ---END---
      """

    let commits = service.parseCommitGraphOutput(output)

    #expect(commits.count == 2)

    let first = commits[0]
    #expect(first.id == "abc1234567890abcdef1234567890abcdef123456")
    #expect(first.shortHash == "abc1234")
    #expect(first.subject == "Add feature X")
    #expect(first.authorName == "John Doe")
    #expect(first.authorEmail == "john@example.com")
    #expect(first.parentHashes.count == 1)
    #expect(first.parentHashes[0] == "def7890567890abcdef1234567890abcdef123456")
    #expect(first.decorations.count == 2)
    #expect(first.decorations.contains("HEAD -> main"))
    #expect(first.decorations.contains("origin/main"))

    let second = commits[1]
    #expect(second.id == "def7890567890abcdef1234567890abcdef123456")
    #expect(second.shortHash == "def7890")
    #expect(second.subject == "Initial commit")
    #expect(second.parentHashes.isEmpty)
    #expect(second.decorations.isEmpty)
  }

  @Test("Parse merge commit with 2 parents")
  func parseMergeCommit() {
    let output = """
      aaaa000000000000000000000000000000000000
      aaaa000
      Merge branch feature
      Dev
      dev@test.com
      2025-06-15 12:00:00 +0000
      bbbb000000000000000000000000000000000000 cccc000000000000000000000000000000000000
      HEAD -> main
      ---END---
      """

    let commits = service.parseCommitGraphOutput(output)

    #expect(commits.count == 1)
    #expect(commits[0].parentHashes.count == 2)
    #expect(commits[0].parentHashes[0] == "bbbb000000000000000000000000000000000000")
    #expect(commits[0].parentHashes[1] == "cccc000000000000000000000000000000000000")
  }

  @Test("Parse decorations with HEAD, remote, and tag")
  func parseDecorations() {
    let output = """
      aaaa000000000000000000000000000000000000
      aaaa000
      Release v1.0
      Dev
      dev@test.com
      2025-06-15 12:00:00 +0000

      HEAD -> main, origin/main, tag: v1.0
      ---END---
      """

    let commits = service.parseCommitGraphOutput(output)

    #expect(commits.count == 1)
    #expect(commits[0].decorations.count == 3)
    #expect(commits[0].decorations.contains("HEAD -> main"))
    #expect(commits[0].decorations.contains("origin/main"))
    #expect(commits[0].decorations.contains("tag: v1.0"))
  }

  @Test("Parse root commit with empty parents")
  func parseRootCommit() {
    let output = """
      aaaa000000000000000000000000000000000000
      aaaa000
      Initial commit
      Dev
      dev@test.com
      2025-06-15 12:00:00 +0000


      ---END---
      """

    let commits = service.parseCommitGraphOutput(output)

    #expect(commits.count == 1)
    #expect(commits[0].parentHashes.isEmpty)
  }

  @Test("Empty output returns empty array")
  func emptyOutput() {
    let commits = service.parseCommitGraphOutput("")
    #expect(commits.isEmpty)
  }

  @Test("Malformed records are skipped, valid ones still parsed")
  func malformedRecords() {
    let output = """
      only-two-lines
      short
      ---END---
      aaaa000000000000000000000000000000000000
      aaaa000
      Valid commit
      Dev
      dev@test.com
      2025-06-15 12:00:00 +0000


      ---END---
      """

    let commits = service.parseCommitGraphOutput(output)

    #expect(commits.count == 1)
    #expect(commits[0].subject == "Valid commit")
  }

  @Test("Full ISO date parsing preserves time")
  func fullISODateParsing() {
    let date = service.parseFullISODate("2025-06-15 14:23:45 +0200")

    #expect(date != nil)

    // Verify the date is not truncated to start of day.
    let calendar = Calendar(identifier: .gregorian)
    var gmtCalendar = calendar
    gmtCalendar.timeZone = TimeZone(secondsFromGMT: 7200)!

    let components = gmtCalendar.dateComponents(
      [.year, .month, .day, .hour, .minute, .second],
      from: date!
    )

    #expect(components.year == 2025)
    #expect(components.month == 6)
    #expect(components.day == 15)
    #expect(components.hour == 14)
    #expect(components.minute == 23)
    #expect(components.second == 45)
  }
}
