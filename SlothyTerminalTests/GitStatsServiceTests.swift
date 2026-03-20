import Foundation
import Testing

@testable import SlothyTerminalLib

@Suite("GitStatsService Parsing")
struct GitStatsServiceTests {
  let service = GitStatsService.shared

  // MARK: - Shortlog Parsing

  @Test("Parses valid multi-line shortlog output")
  func parseShortlogOutput() {
    let output = """
      142\tJohn Doe <john@example.com>
       87\tJane Smith <jane@example.com>
        3\tBot <bot@ci.local>
    """

    let result = service.parseShortlogOutput(output)

    #expect(result.count == 3)
    #expect(result[0].name == "John Doe")
    #expect(result[0].email == "john@example.com")
    #expect(result[0].commitCount == 142)
    #expect(result[1].name == "Jane Smith")
    #expect(result[1].commitCount == 87)
    #expect(result[2].commitCount == 3)
  }

  @Test("Empty shortlog output returns empty array")
  func parseShortlogEmptyOutput() {
    let result = service.parseShortlogOutput("")
    #expect(result.isEmpty)
  }

  @Test("Malformed shortlog lines without tab are skipped")
  func parseShortlogMalformedLines() {
    let output = """
      142\tJohn Doe <john@example.com>
    this line has no tab

       87\tJane Smith <jane@example.com>
    """

    let result = service.parseShortlogOutput(output)

    #expect(result.count == 2)
    #expect(result[0].commitCount == 142)
    #expect(result[1].commitCount == 87)
  }

  // MARK: - Daily Activity Parsing

  @Test("Parses ISO date strings into grouped daily activity")
  func parseDailyActivityFromDates() {
    let output = """
    2025-06-15 14:23:45 +0200
    2025-06-15 16:00:00 +0200
    2025-06-16 09:00:00 +0200
    """

    let result = service.parseDailyActivity(output)

    #expect(result.count == 2)

    let firstDay = result.first { $0.commitCount == 2 }
    #expect(firstDay != nil)

    let secondDay = result.first { $0.commitCount == 1 }
    #expect(secondDay != nil)
  }

  @Test("Empty activity output returns empty array")
  func parseDailyActivityEmptyOutput() {
    let result = service.parseDailyActivity("")
    #expect(result.isEmpty)
  }

  @Test("Same day repeated sums into single entry")
  func parseDailyActivityDuplicateDates() {
    let output = """
    2025-01-10 08:00:00 +0000
    2025-01-10 12:00:00 +0000
    2025-01-10 18:00:00 +0000
    """

    let result = service.parseDailyActivity(output)

    #expect(result.count == 1)
    #expect(result[0].commitCount == 3)
  }

  // MARK: - Summary Parsing

  @Test("Parses valid summary outputs into RepositorySummary")
  func parseSummary() {
    let result = service.parseSummary(
      commitCountOutput: "500",
      authorCountOutput: "  10\tAuthor1\n   5\tAuthor2\n",
      firstDateOutput: "2023-01-15 10:00:00 +0000",
      branch: "main"
    )

    #expect(result != nil)
    #expect(result?.totalCommits == 500)
    #expect(result?.totalAuthors == 2)
    #expect(result?.firstCommitDate != nil)
    #expect(result?.currentBranch == "main")
  }

  @Test("Zero commits returns nil summary")
  func parseSummaryZeroCommits() {
    let result = service.parseSummary(
      commitCountOutput: "0",
      authorCountOutput: "",
      firstDateOutput: nil,
      branch: nil
    )

    #expect(result == nil)
  }

  @Test("Negative commit count returns nil summary")
  func parseSummaryNegativeCommits() {
    let result = service.parseSummary(
      commitCountOutput: "-5",
      authorCountOutput: "  1\tAuthor\n",
      firstDateOutput: nil,
      branch: nil
    )

    #expect(result == nil)
  }

  // MARK: - ISO Date Parsing

  @Test("Malformed date string returns nil")
  func parseISODateMalformed() {
    let calendar = Calendar.current

    #expect(service.parseISODateToDay("not-a-date", calendar: calendar) == nil)
    #expect(service.parseISODateToDay("", calendar: calendar) == nil)
    #expect(service.parseISODateToDay("abc-de-fg 00:00:00 +0000", calendar: calendar) == nil)
  }

  @Test("Malformed activity lines are skipped")
  func parseDailyActivityMalformedLines() {
    let output = """
    2025-06-15 14:23:45 +0200
    not-a-date
    garbage-line
    2025-06-16 09:00:00 +0200
    """

    let result = service.parseDailyActivity(output)

    #expect(result.count == 2)
  }

  // MARK: - Shortlog Edge Cases

  @Test("Author name with angle brackets is parsed correctly")
  func parseShortlogWithAngleBrackets() {
    let output = "  5\tUser <display> Name <user@example.com>\n"

    let result = service.parseShortlogOutput(output)

    #expect(result.count == 1)
    #expect(result[0].name == "User <display> Name")
    #expect(result[0].email == "user@example.com")
  }

  @Test("Author without email falls back to full name")
  func parseShortlogWithoutEmail() {
    let output = "  3\tSome Author\n"

    let result = service.parseShortlogOutput(output)

    #expect(result.count == 1)
    #expect(result[0].name == "Some Author")
    #expect(result[0].email == "")
  }

  @Test("Duplicate emails are merged with summed commit counts")
  func parseShortlogMergesByEmail() {
    let output = """
      100\tJohn Doe <john@example.com>
       50\tJohn D. <john@example.com>
       30\tJane Smith <jane@example.com>
    """

    let result = service.parseShortlogOutput(output)

    #expect(result.count == 2)
    let john = result.first { $0.email == "john@example.com" }
    #expect(john?.commitCount == 150)
    #expect(john?.name == "John Doe")
  }

  @Test("Duplicate emails with different casing are merged")
  func parseShortlogMergesCaseInsensitive() {
    let output = """
       20\tUser A <User@Example.COM>
       10\tUser B <user@example.com>
    """

    let result = service.parseShortlogOutput(output)

    #expect(result.count == 1)
    #expect(result[0].commitCount == 30)
    #expect(result[0].name == "User A")
  }

  // MARK: - Author Count from Shortlog

  @Test("Counts non-empty lines in shortlog output")
  func countAuthorsFromShortlog() {
    let output = """
      142\tJohn Doe
       87\tJane Smith
        3\tBot
    """

    let count = service.countAuthorsFromShortlog(output)

    #expect(count == 3)
  }

  @Test("Empty shortlog returns zero authors")
  func countAuthorsFromShortlogEmpty() {
    #expect(service.countAuthorsFromShortlog("") == 0)
    #expect(service.countAuthorsFromShortlog("   \n  \n") == 0)
  }
}
