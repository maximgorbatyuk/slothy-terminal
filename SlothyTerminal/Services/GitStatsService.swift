import Foundation

/// Service for querying Git repository statistics.
final class GitStatsService {
  static let shared = GitStatsService()

  private init() {}

  /// Checks whether the directory is inside a Git work tree using `git rev-parse`.
  func isGitRepository(in directory: URL) async -> Bool {
    let output = await runGit(["rev-parse", "--is-inside-work-tree"], in: directory)
    return output?.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
  }

  /// Returns per-author commit stats sorted by commit count descending.
  func getAuthorStats(in directory: URL) async -> [AuthorStats] {
    guard let output = await runGit(["shortlog", "-sne", "--all"], in: directory) else {
      return []
    }

    return parseShortlogOutput(output)
  }

  /// Returns daily commit counts for the last `weeks` weeks, sorted by date ascending.
  func getDailyActivity(in directory: URL, weeks: Int = 12) async -> [DailyActivity] {
    guard let output = await runGit(
      ["log", "--format=%ai", "--since=\(weeks) weeks ago", "--all"],
      in: directory
    ) else {
      return []
    }

    return parseDailyActivity(output)
  }

  /// Returns summary stats: total commits, total authors, first commit date, current branch.
  func getRepositorySummary(in directory: URL) async -> RepositorySummary? {
    let totalCommits = await countAllCommits(in: directory)

    guard totalCommits > 0 else {
      return nil
    }

    async let authorCount = countAuthors(in: directory)
    async let firstDate = firstCommitDate(in: directory)
    async let branch = GitService.shared.getCurrentBranch(in: directory)

    return RepositorySummary(
      totalCommits: totalCommits,
      totalAuthors: await authorCount,
      firstCommitDate: await firstDate,
      currentBranch: await branch
    )
  }

  /// Returns commits for the revision graph, in topological order.
  /// - Parameters:
  ///   - directory: The repository directory.
  ///   - limit: Maximum number of commits to fetch (default 200).
  ///   - skip: Number of commits to skip (default 0).
  /// - Returns: Parsed commits with parent and decoration info.
  func getCommitGraph(
    in directory: URL,
    limit: Int = 200,
    skip: Int = 0
  ) async -> [GraphCommit] {
    let format = "%H%n%h%n%s%n%an%n%ae%n%ai%n%P%n%D%n---END---"

    guard let output = await runGit(
      [
        "log",
        "--format=\(format)",
        "--decorate=short",
        "--topo-order",
        "-\(limit)",
        "--skip=\(skip)",
        "--all",
      ],
      in: directory
    ) else {
      return []
    }

    return parseCommitGraphOutput(output)
  }

  // MARK: - Parsing (internal for testing)

  /// Parses `git shortlog -sne --all` output into `[AuthorStats]`.
  /// Each line looks like: `   142\tJohn Doe <john@example.com>`
  /// Entries sharing the same email (case-insensitive) are merged,
  /// keeping the name from the entry with the highest commit count.
  func parseShortlogOutput(_ output: String) -> [AuthorStats] {
    var merged: [String: (name: String, email: String, count: Int)] = [:]

    for line in output.components(separatedBy: "\n") {
      let trimmed = line.trimmingCharacters(in: .whitespaces)

      guard !trimmed.isEmpty else {
        continue
      }

      guard let tabIndex = trimmed.firstIndex(of: "\t") else {
        continue
      }

      let countStr = String(trimmed[trimmed.startIndex..<tabIndex])
        .trimmingCharacters(in: .whitespaces)

      guard let count = Int(countStr) else {
        continue
      }

      let rest = String(trimmed[trimmed.index(after: tabIndex)...])
      let (name, email) = parseNameEmail(rest)
      let key = email.lowercased()

      if let existing = merged[key] {
        let bestName = count > existing.count ? name : existing.name
        merged[key] = (name: bestName, email: existing.email, count: existing.count + count)
      } else {
        merged[key] = (name: name, email: email, count: count)
      }
    }

    return merged.values
      .map { AuthorStats(name: $0.name, email: $0.email, commitCount: $0.count) }
      .sorted { $0.commitCount > $1.commitCount }
  }

  /// Parses `git log --format="%ai"` output into grouped daily activity.
  /// Each line looks like: `2025-06-15 14:23:45 +0200`
  func parseDailyActivity(_ output: String) -> [DailyActivity] {
    let calendar = Calendar.current
    var dayCounts: [Date: Int] = [:]

    for line in output.components(separatedBy: "\n") {
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

      guard !trimmed.isEmpty else {
        continue
      }

      guard let date = parseISODateToDay(trimmed, calendar: calendar) else {
        continue
      }

      dayCounts[date, default: 0] += 1
    }

    return dayCounts
      .map { DailyActivity(date: $0.key, commitCount: $0.value) }
      .sorted { $0.date < $1.date }
  }

  /// Parses `git rev-list --count --all` and `git shortlog -sn --all | wc -l` equivalent.
  func parseSummary(
    commitCountOutput: String,
    authorCountOutput: String,
    firstDateOutput: String?,
    branch: String?
  ) -> RepositorySummary? {
    guard let totalCommits = Int(commitCountOutput.trimmingCharacters(in: .whitespacesAndNewlines)),
          totalCommits > 0
    else {
      return nil
    }

    let totalAuthors = authorCountOutput
      .components(separatedBy: "\n")
      .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
      .count

    var firstDate: Date?
    if let dateStr = firstDateOutput?.trimmingCharacters(in: .whitespacesAndNewlines),
       !dateStr.isEmpty
    {
      firstDate = parseISODateToDay(dateStr, calendar: Calendar.current)
    }

    return RepositorySummary(
      totalCommits: totalCommits,
      totalAuthors: totalAuthors,
      firstCommitDate: firstDate,
      currentBranch: branch
    )
  }

  /// Parses the multi-record `git log` output into `[GraphCommit]`.
  /// Records are separated by `---END---`. Each record has 8 lines:
  /// hash, short hash, subject, author name, author email, author date, parents, decorations.
  /// Parent and decoration lines may be empty (root commits, undecorated commits).
  func parseCommitGraphOutput(_ output: String) -> [GraphCommit] {
    let records = output.components(separatedBy: "---END---")
    var commits: [GraphCommit] = []

    for record in records {
      // Split preserving empty lines — parents and decorations can be empty.
      var lines = record.components(separatedBy: "\n")

      // Trim leading/trailing empty lines from the record boundary.
      while lines.first?.trimmingCharacters(in: .whitespaces).isEmpty == true {
        lines.removeFirst()
      }

      while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
        lines.removeLast()
      }

      guard lines.count >= 6 else {
        continue
      }

      let hash = lines[0].trimmingCharacters(in: .whitespaces)

      guard !hash.isEmpty else {
        continue
      }

      let shortHash = lines[1].trimmingCharacters(in: .whitespaces)
      let subject = lines[2].trimmingCharacters(in: .whitespaces)
      let authorName = lines[3].trimmingCharacters(in: .whitespaces)
      let authorEmail = lines[4].trimmingCharacters(in: .whitespaces)
      let dateString = lines[5].trimmingCharacters(in: .whitespaces)

      // Parent line (index 6) may be absent for root commits with no decorations.
      let parentLine = lines.count > 6 ? lines[6].trimmingCharacters(in: .whitespaces) : ""
      let decorationLine = lines.count > 7 ? lines[7].trimmingCharacters(in: .whitespaces) : ""

      let authorDate = parseFullISODate(dateString) ?? Date.distantPast

      let parentHashes = parentLine
        .split(separator: " ")
        .map(String.init)

      let decorations: [String]
      if decorationLine.isEmpty {
        decorations = []
      } else {
        decorations = decorationLine
          .components(separatedBy: ", ")
          .map { $0.trimmingCharacters(in: .whitespaces) }
          .filter { !$0.isEmpty }
      }

      commits.append(GraphCommit(
        id: hash,
        shortHash: shortHash,
        subject: subject,
        authorName: authorName,
        authorEmail: authorEmail,
        authorDate: authorDate,
        parentHashes: parentHashes,
        decorations: decorations
      ))
    }

    return commits
  }

  /// Parses a full ISO-ish date string (e.g. "2025-06-15 14:23:45 +0200") with time preserved.
  func parseFullISODate(_ string: String) -> Date? {
    Self.fullISODateFormatter.date(from: string)
  }

  private static let fullISODateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter
  }()

  // MARK: - Private helpers

  private func countAllCommits(in directory: URL) async -> Int {
    guard let output = await runGit(["rev-list", "--count", "--all"], in: directory) else {
      return 0
    }

    return Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
  }

  private func countAuthors(in directory: URL) async -> Int {
    guard let output = await runGit(["shortlog", "-sn", "--all"], in: directory) else {
      return 0
    }

    return output
      .components(separatedBy: "\n")
      .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
      .count
  }

  private func firstCommitDate(in directory: URL) async -> Date? {
    // Find the root commit hash first, then get its date.
    // `git log --reverse -1` is wrong: `-1` limits before `--reverse` applies.
    guard let rootHash = await runGit(
      ["rev-list", "--max-parents=0", "HEAD"],
      in: directory
    ) else {
      return nil
    }

    // rev-list may return multiple roots; take the first line.
    let firstRoot = rootHash
      .components(separatedBy: "\n")
      .first?
      .trimmingCharacters(in: .whitespaces) ?? ""

    guard !firstRoot.isEmpty else {
      return nil
    }

    guard let dateOutput = await runGit(
      ["log", "--format=%ai", "-1", firstRoot],
      in: directory
    ) else {
      return nil
    }

    return parseISODateToDay(
      dateOutput.trimmingCharacters(in: .whitespacesAndNewlines),
      calendar: Calendar.current
    )
  }

  /// Parses "Name <email>" into (name, email). Falls back to full string as name.
  private func parseNameEmail(_ input: String) -> (String, String) {
    guard let openAngle = input.lastIndex(of: "<"),
          let closeAngle = input.lastIndex(of: ">"),
          openAngle < closeAngle
    else {
      return (input.trimmingCharacters(in: .whitespaces), "")
    }

    let name = String(input[input.startIndex..<openAngle])
      .trimmingCharacters(in: .whitespaces)
    let email = String(input[input.index(after: openAngle)..<closeAngle])

    return (name, email)
  }

  /// Parses an ISO-ish date string (e.g. "2025-06-15 14:23:45 +0200") to start-of-day.
  /// Timezone offset is intentionally ignored — grouping uses the author-local date portion.
  func parseISODateToDay(_ string: String, calendar: Calendar) -> Date? {
    let parts = string.split(separator: " ")

    guard let datePart = parts.first else {
      return nil
    }

    let dateComponents = datePart.split(separator: "-")

    guard dateComponents.count == 3,
          let year = Int(dateComponents[0]),
          let month = Int(dateComponents[1]),
          let day = Int(dateComponents[2])
    else {
      return nil
    }

    return calendar.date(from: DateComponents(year: year, month: month, day: day))
  }

  /// Runs a git command off the main thread and returns trimmed stdout.
  private func runGit(_ arguments: [String], in directory: URL) async -> String? {
    await GitProcessRunner.run(arguments, in: directory)
  }
}
