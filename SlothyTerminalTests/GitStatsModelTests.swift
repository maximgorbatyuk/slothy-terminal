import Foundation
import Testing

@testable import SlothyTerminalLib

@Suite("GitStats Models")
struct GitStatsModelTests {

  @Test("AuthorStats identity is name and email composite")
  func authorStatsIdentity() {
    let author = AuthorStats(name: "John", email: "john@example.com", commitCount: 10)
    #expect(author.id == "John|john@example.com")

    // Two authors with the same email but different names get different ids.
    let other = AuthorStats(name: "Johnny", email: "john@example.com", commitCount: 5)
    #expect(author.id != other.id)

    // Two authors with no email get different ids if names differ.
    let noEmail1 = AuthorStats(name: "Alice", email: "", commitCount: 3)
    let noEmail2 = AuthorStats(name: "Bob", email: "", commitCount: 2)
    #expect(noEmail1.id != noEmail2.id)
  }

  @Test("DailyActivity identity is date")
  func dailyActivityIdentity() {
    let date = Date()
    let activity = DailyActivity(date: date, commitCount: 5)
    #expect(activity.id == date)
  }

  @Test("RepositorySummary handles nil first commit date")
  func repositorySummaryDefaults() {
    let summary = RepositorySummary(
      totalCommits: 100,
      totalAuthors: 3,
      firstCommitDate: nil,
      currentBranch: nil
    )

    #expect(summary.totalCommits == 100)
    #expect(summary.totalAuthors == 3)
    #expect(summary.firstCommitDate == nil)
    #expect(summary.currentBranch == nil)
  }
}
