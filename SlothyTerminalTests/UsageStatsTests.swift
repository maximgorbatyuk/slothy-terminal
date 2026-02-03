import XCTest
@testable import SlothyTerminalLib

final class UsageStatsTests: XCTestCase {
  private var stats: UsageStats!

  override func setUp() {
    super.setUp()
    stats = UsageStats()
  }

  override func tearDown() {
    stats = nil
    super.tearDown()
  }

  // MARK: - Initial State Tests

  func testInitialState() {
    XCTAssertEqual(stats.tokensIn, 0)
    XCTAssertEqual(stats.tokensOut, 0)
    XCTAssertEqual(stats.messageCount, 0)
    XCTAssertEqual(stats.commandCount, 0)
    XCTAssertNil(stats.estimatedCost)
    XCTAssertEqual(stats.contextWindowLimit, 200_000)
  }

  // MARK: - Total Tokens Tests

  func testTotalTokensCalculation() {
    stats.tokensIn = 1000
    stats.tokensOut = 500

    XCTAssertEqual(stats.totalTokens, 1500)
  }

  func testTotalTokensWithZeroValues() {
    XCTAssertEqual(stats.totalTokens, 0)
  }

  // MARK: - Apply Update Tests

  func testApplyUpdateTokensIn() {
    let update = UsageUpdate(tokensIn: 1000)
    stats.applyUpdate(update)

    XCTAssertEqual(stats.tokensIn, 1000)
  }

  func testApplyUpdateTokensOut() {
    let update = UsageUpdate(tokensOut: 500)
    stats.applyUpdate(update)

    XCTAssertEqual(stats.tokensOut, 500)
  }

  func testApplyUpdateCost() {
    let update = UsageUpdate(cost: 0.05)
    stats.applyUpdate(update)

    XCTAssertEqual(stats.estimatedCost, 0.05)
  }

  func testApplyUpdateMessageCountReplace() {
    stats.messageCount = 5
    let update = UsageUpdate(messageCount: 10)
    stats.applyUpdate(update, incrementMessages: false)

    XCTAssertEqual(stats.messageCount, 10)
  }

  func testApplyUpdateMessageCountIncrement() {
    stats.messageCount = 5
    let update = UsageUpdate(messageCount: 1)
    stats.applyUpdate(update, incrementMessages: true)

    XCTAssertEqual(stats.messageCount, 6)
  }

  func testApplyUpdateContextWindowLimit() {
    let update = UsageUpdate(contextWindowLimit: 100_000)
    stats.applyUpdate(update)

    XCTAssertEqual(stats.contextWindowLimit, 100_000)
  }

  func testApplyFullUpdate() {
    let update = UsageUpdate(
      tokensIn: 1000,
      tokensOut: 500,
      totalTokens: 1500,
      cost: 0.05,
      messageCount: 10,
      contextWindowLimit: 150_000
    )
    stats.applyUpdate(update)

    XCTAssertEqual(stats.tokensIn, 1000)
    XCTAssertEqual(stats.tokensOut, 500)
    XCTAssertEqual(stats.estimatedCost, 0.05)
    XCTAssertEqual(stats.messageCount, 10)
    XCTAssertEqual(stats.contextWindowLimit, 150_000)
  }

  func testApplyPartialUpdate() {
    stats.tokensIn = 500
    stats.tokensOut = 200
    stats.messageCount = 5

    let update = UsageUpdate(tokensIn: 1000)
    stats.applyUpdate(update)

    XCTAssertEqual(stats.tokensIn, 1000)
    XCTAssertEqual(stats.tokensOut, 200)  /// Unchanged
    XCTAssertEqual(stats.messageCount, 5)  /// Unchanged
  }

  // MARK: - Increment Tests

  func testIncrementMessageCount() {
    stats.messageCount = 5
    stats.incrementMessageCount()

    XCTAssertEqual(stats.messageCount, 6)
  }

  func testIncrementCommandCount() {
    stats.commandCount = 3
    stats.incrementCommandCount()

    XCTAssertEqual(stats.commandCount, 4)
  }

  // MARK: - Reset Tests

  func testReset() {
    stats.tokensIn = 1000
    stats.tokensOut = 500
    stats.messageCount = 10
    stats.commandCount = 5
    stats.estimatedCost = 0.05
    stats.contextWindowLimit = 100_000

    stats.reset()

    XCTAssertEqual(stats.tokensIn, 0)
    XCTAssertEqual(stats.tokensOut, 0)
    XCTAssertEqual(stats.messageCount, 0)
    XCTAssertEqual(stats.commandCount, 0)
    XCTAssertNil(stats.estimatedCost)
    XCTAssertEqual(stats.contextWindowLimit, 200_000)
  }

  // MARK: - Context Window Percentage Tests

  func testContextWindowPercentage() {
    stats.tokensIn = 50_000
    stats.tokensOut = 50_000
    stats.contextWindowLimit = 200_000

    XCTAssertEqual(stats.contextWindowPercentage, 0.5, accuracy: 0.001)
  }

  func testContextWindowPercentageWithZeroLimit() {
    stats.tokensIn = 1000
    stats.contextWindowLimit = 0

    XCTAssertEqual(stats.contextWindowPercentage, 0)
  }

  func testContextWindowPercentageFormatted() {
    stats.tokensIn = 25_000
    stats.tokensOut = 25_000
    stats.contextWindowLimit = 200_000

    XCTAssertEqual(stats.formattedContextPercentage, "25.0%")
  }

  // MARK: - Formatted Values Tests

  func testFormattedTokensIn() {
    stats.tokensIn = 12345

    XCTAssertEqual(stats.formattedTokensIn, "12,345")
  }

  func testFormattedTokensOut() {
    stats.tokensOut = 6789

    XCTAssertEqual(stats.formattedTokensOut, "6,789")
  }

  func testFormattedTotalTokens() {
    stats.tokensIn = 10000
    stats.tokensOut = 5000

    XCTAssertEqual(stats.formattedTotalTokens, "15,000")
  }

  func testFormattedCostWithValue() {
    stats.estimatedCost = 0.0123

    XCTAssertNotNil(stats.formattedCost)
    /// Currency formatting may vary by locale, just check it's not empty
    XCTAssertFalse(stats.formattedCost?.isEmpty ?? true)
  }

  func testFormattedCostWithNil() {
    stats.estimatedCost = nil

    XCTAssertNil(stats.formattedCost)
  }

  // MARK: - Duration Tests

  func testDurationCalculation() {
    /// Duration should be very small immediately after creation
    XCTAssertLessThan(stats.duration, 1.0)
  }

  func testFormattedDurationMinutesSeconds() {
    /// Set start time to 65 seconds ago
    stats.startTime = Date().addingTimeInterval(-65)

    XCTAssertEqual(stats.formattedDuration, "1m 05s")
  }

  func testFormattedDurationHoursMinutes() {
    /// Set start time to 3665 seconds (1h 1m 5s) ago
    stats.startTime = Date().addingTimeInterval(-3665)

    XCTAssertEqual(stats.formattedDuration, "1h 01m")
  }

  func testFormattedDurationZero() {
    XCTAssertEqual(stats.formattedDuration, "0m 00s")
  }

  // MARK: - Start Session Tests

  func testStartSession() {
    let oldStartTime = stats.startTime
    Thread.sleep(forTimeInterval: 0.01)

    stats.startSession()

    XCTAssertGreaterThan(stats.startTime, oldStartTime)
  }
}
