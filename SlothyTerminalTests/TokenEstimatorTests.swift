import Foundation
import Testing

@testable import SlothyTerminalLib

@Suite("TokenEstimator")
struct TokenEstimatorTests {

  // MARK: - String estimation

  @Test("Empty string estimates to 1 token minimum")
  func emptyString() {
    let result = TokenEstimator.estimate("")
    #expect(result == 1)
  }

  @Test("Short string estimates proportionally")
  func shortString() {
    /// "hello" = 5 chars → 5/4 = 1
    let result = TokenEstimator.estimate("hello")
    #expect(result == 1)
  }

  @Test("Longer string estimates proportionally")
  func longerString() {
    /// 100 chars → 25 tokens
    let text = String(repeating: "a", count: 100)
    let result = TokenEstimator.estimate(text)
    #expect(result == 25)
  }

  @Test("1000 character string estimates to 250 tokens")
  func thousandChars() {
    let text = String(repeating: "x", count: 1000)
    let result = TokenEstimator.estimate(text)
    #expect(result == 250)
  }

  // MARK: - Message estimation

  @Test("Empty message array estimates to 0")
  func emptyMessages() {
    let result = TokenEstimator.estimate(messages: [])
    #expect(result == 0)
  }

  @Test("Single message includes overhead")
  func singleMessage() {
    let messages: [[String: JSONValue]] = [
      [
        "role": .string("user"),
        "content": .string("Hi"),
      ]
    ]

    let result = TokenEstimator.estimate(messages: messages)
    /// 4 overhead + "role"(1) + "user"(1) + "content"(2) + "Hi"(1) = ~9
    #expect(result > 0)
    #expect(result < 20)
  }

  @Test("Multiple messages accumulate tokens")
  func multipleMessages() {
    let messages: [[String: JSONValue]] = [
      ["role": .string("user"), "content": .string("Hello")],
      ["role": .string("assistant"), "content": .string("Hi there, how can I help?")],
    ]

    let single = TokenEstimator.estimate(messages: [messages[0]])
    let both = TokenEstimator.estimate(messages: messages)

    #expect(both > single)
  }

  @Test("Nested arrays and objects are counted")
  func nestedStructure() {
    let messages: [[String: JSONValue]] = [
      [
        "role": .string("assistant"),
        "content": .array([
          .object(["type": .string("text"), "text": .string("Some response text here")]),
          .object([
            "type": .string("tool_use"),
            "id": .string("toolu_123"),
            "name": .string("bash"),
            "input": .string("{\"command\":\"ls -la\"}"),
          ]),
        ]),
      ]
    ]

    let result = TokenEstimator.estimate(messages: messages)
    #expect(result > 10)
  }

  @Test("Large tool result counts significantly")
  func largeToolResult() {
    let longOutput = String(repeating: "line of output\n", count: 100)
    let messages: [[String: JSONValue]] = [
      [
        "role": .string("user"),
        "content": .array([
          .object([
            "type": .string("tool_result"),
            "content": .string(longOutput),
          ])
        ]),
      ]
    ]

    let result = TokenEstimator.estimate(messages: messages)
    /// longOutput is ~1500 chars → ~375 tokens plus overhead.
    #expect(result > 300)
  }
}
