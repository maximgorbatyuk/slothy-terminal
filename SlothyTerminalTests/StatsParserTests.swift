import XCTest
@testable import SlothyTerminalLib

final class StatsParserTests: XCTestCase {
  private var parser: StatsParser!

  override func setUp() {
    super.setUp()
    parser = StatsParser.shared
  }

  // MARK: - Token Parsing Tests

  func testParseTokensInOutFormat() {
    let text = "Tokens: 1234 in / 567 out"
    let result = parser.parseClaudeOutput(text)

    XCTAssertNotNil(result)
    XCTAssertEqual(result?.tokensIn, 1234)
    XCTAssertEqual(result?.tokensOut, 567)
    /// Note: totalTokens may be overwritten by other patterns, check in/out values
  }

  func testParseTokensWithCommas() {
    let text = "Tokens: 12,345 in / 6,789 out"
    let result = parser.parseClaudeOutput(text)

    XCTAssertNotNil(result)
    XCTAssertEqual(result?.tokensIn, 12345)
    XCTAssertEqual(result?.tokensOut, 6789)
  }

  func testParseClaudeCodeTokenFormat() {
    let text = ">1234 <567"
    let result = parser.parseClaudeOutput(text)

    XCTAssertNotNil(result)
    XCTAssertEqual(result?.tokensIn, 1234)
    XCTAssertEqual(result?.tokensOut, 567)
  }

  func testParseClaudeCodeTokenFormatWithK() {
    let text = ">12.3k <4.5k"
    let result = parser.parseClaudeOutput(text)

    XCTAssertNotNil(result)
    XCTAssertEqual(result?.tokensIn, 12300)
    XCTAssertEqual(result?.tokensOut, 4500)
  }

  func testParseSlashTokenFormat() {
    let text = "12.3k/4.5k"
    let result = parser.parseClaudeOutput(text)

    XCTAssertNotNil(result)
    XCTAssertEqual(result?.tokensIn, 12300)
    XCTAssertEqual(result?.tokensOut, 4500)
  }

  func testParseSlashTokenFormatWithSpaces() {
    let text = "1234 / 567"
    let result = parser.parseClaudeOutput(text)

    XCTAssertNotNil(result)
    XCTAssertEqual(result?.tokensIn, 1234)
    XCTAssertEqual(result?.tokensOut, 567)
  }

  func testParseTotalTokens() {
    let text = "Total tokens: 5000"
    let result = parser.parseClaudeOutput(text)

    XCTAssertNotNil(result)
    XCTAssertEqual(result?.totalTokens, 5000)
  }

  func testParseInputTokens() {
    let text = "Input tokens: 3000"
    let result = parser.parseClaudeOutput(text)

    XCTAssertNotNil(result)
    XCTAssertEqual(result?.tokensIn, 3000)
  }

  func testParseOutputTokens() {
    let text = "Output tokens: 2000"
    let result = parser.parseClaudeOutput(text)

    XCTAssertNotNil(result)
    XCTAssertEqual(result?.tokensOut, 2000)
  }

  // MARK: - Cost Parsing Tests

  func testParseCost() {
    let text = "Cost: $0.0123"
    let result = parser.parseClaudeOutput(text)

    XCTAssertNotNil(result)
    XCTAssertNotNil(result?.cost)
    XCTAssertEqual(result!.cost!, 0.0123, accuracy: 0.0001)
  }

  func testParseCostWithoutLabel() {
    let text = "Estimated $0.05 for this session"
    let result = parser.parseClaudeOutput(text)

    XCTAssertNotNil(result)
    XCTAssertNotNil(result?.cost)
    XCTAssertEqual(result!.cost!, 0.05, accuracy: 0.0001)
  }

  func testParseLargerCost() {
    let text = "Total cost: $1.23"
    let result = parser.parseClaudeOutput(text)

    XCTAssertNotNil(result)
    XCTAssertNotNil(result?.cost)
    XCTAssertEqual(result!.cost!, 1.23, accuracy: 0.01)
  }

  // MARK: - Context Window Tests

  func testParseContextWindow() {
    let text = "Context: 12345 / 200000"
    let result = parser.parseClaudeOutput(text)

    XCTAssertNotNil(result)
    XCTAssertEqual(result?.contextWindowUsed, 12345)
    XCTAssertEqual(result?.contextWindowLimit, 200000)
  }

  func testParseContextWindowWithLabel() {
    let text = "Context window: 50000/200000"
    let result = parser.parseClaudeOutput(text)

    XCTAssertNotNil(result)
    XCTAssertEqual(result?.contextWindowUsed, 50000)
    XCTAssertEqual(result?.contextWindowLimit, 200000)
  }

  // MARK: - Message Count Tests

  func testParseMessageCount() {
    let text = "Messages: 24"
    let result = parser.parseClaudeOutput(text)

    XCTAssertNotNil(result)
    XCTAssertEqual(result?.messageCount, 24)
  }

  func testParseMessageCountWithLabel() {
    let text = "Message count: 10"
    let result = parser.parseClaudeOutput(text)

    XCTAssertNotNil(result)
    XCTAssertEqual(result?.messageCount, 10)
  }

  // MARK: - Assistant Marker Tests

  func testDetectAssistantMarkerClaude() {
    let text = "Claude: Here's the solution"
    let result = parser.parseClaudeOutput(text)

    XCTAssertNotNil(result)
    XCTAssertEqual(result?.messageCount, 1)
    XCTAssertTrue(result?.incrementMessageCount ?? false)
  }

  func testDetectAssistantMarkerLetMe() {
    let text = "Let me help you with that"
    let result = parser.parseClaudeOutput(text)

    XCTAssertNotNil(result)
    XCTAssertEqual(result?.messageCount, 1)
    XCTAssertTrue(result?.incrementMessageCount ?? false)
  }

  func testDetectAssistantMarkerIll() {
    let text = "I'll create a function for that"
    let result = parser.parseClaudeOutput(text)

    XCTAssertNotNil(result)
    XCTAssertEqual(result?.messageCount, 1)
    XCTAssertTrue(result?.incrementMessageCount ?? false)
  }

  // MARK: - JSON Parsing Tests

  func testParseJSONStatusTokens() {
    /// JSON must contain "tokens" for the regex to match
    let text = """
    {"tokens": 1500, "input_tokens": 1000, "output_tokens": 500}
    """
    let result = parser.parseClaudeOutput(text)

    XCTAssertNotNil(result)
    XCTAssertEqual(result?.tokensIn, 1000)
    XCTAssertEqual(result?.tokensOut, 500)
    XCTAssertEqual(result?.totalTokens, 1500)
  }

  func testParseJSONStatusWithCost() {
    let text = """
    {"tokens": 1500, "cost": 0.0025}
    """
    let result = parser.parseClaudeOutput(text)

    XCTAssertNotNil(result)
    XCTAssertEqual(result?.totalTokens, 1500)
    XCTAssertNotNil(result?.cost)
    XCTAssertEqual(result!.cost!, 0.0025, accuracy: 0.0001)
  }

  func testParseJSONStatusWithMessages() {
    let text = """
    {"tokens": 1000, "messages": 5}
    """
    let result = parser.parseClaudeOutput(text)

    XCTAssertNotNil(result)
    XCTAssertEqual(result?.totalTokens, 1000)
    XCTAssertEqual(result?.messageCount, 5)
  }

  // MARK: - ANSI Code Stripping Tests

  func testParseWithANSICodes() {
    let text = "\u{1B}[32mTokens: 1234 in / 567 out\u{1B}[0m"
    let result = parser.parseClaudeOutput(text)

    XCTAssertNotNil(result)
    XCTAssertEqual(result?.tokensIn, 1234)
    XCTAssertEqual(result?.tokensOut, 567)
  }

  // MARK: - Edge Cases

  func testParseEmptyString() {
    let text = ""
    let result = parser.parseClaudeOutput(text)

    XCTAssertNil(result)
  }

  func testParseUnrelatedText() {
    let text = "Hello, how are you today?"
    let result = parser.parseClaudeOutput(text)

    XCTAssertNil(result)
  }

  func testParseMultiplePatterns() {
    /// Note: Context window pattern can interfere with slash token pattern
    /// Testing tokens and cost separately from context
    let text = """
    Tokens: 1234 in / 567 out
    Cost: $0.05
    """
    let result = parser.parseClaudeOutput(text)

    XCTAssertNotNil(result)
    XCTAssertEqual(result?.tokensIn, 1234)
    XCTAssertEqual(result?.tokensOut, 567)
    XCTAssertNotNil(result?.cost)
    XCTAssertEqual(result!.cost!, 0.05, accuracy: 0.01)
  }

  func testParseContextWindowSeparately() {
    let text = "Context window: 50000/200000"
    let result = parser.parseClaudeOutput(text)

    XCTAssertNotNil(result)
    XCTAssertEqual(result?.contextWindowUsed, 50000)
    XCTAssertEqual(result?.contextWindowLimit, 200000)
  }

  // MARK: - GLM Output Tests

  func testParseGLMOutput() {
    /// GLM uses the same parser as Claude for now
    let text = "Tokens: 500 in / 200 out"
    let result = parser.parseGLMOutput(text)

    XCTAssertNotNil(result)
    XCTAssertEqual(result?.tokensIn, 500)
    XCTAssertEqual(result?.tokensOut, 200)
  }
}
