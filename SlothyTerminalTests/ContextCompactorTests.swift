import Foundation
import Testing

@testable import SlothyTerminalLib

@Suite("ContextCompactor")
struct ContextCompactorTests {

  private let testModel = ModelDescriptor(
    providerID: .anthropic,
    modelID: "claude-sonnet-4-6",
    packageID: "@ai-sdk/anthropic",
    supportsReasoning: true,
    releaseDate: "2025-05-14",
    outputLimit: 16_384
  )

  // MARK: - No compaction needed

  @Test("Does not compact when under budget")
  func noCompactionUnderBudget() {
    var messages: [[String: JSONValue]] = [
      ["role": .string("user"), "content": .string("Hello")],
      ["role": .string("assistant"), "content": .string("Hi!")],
    ]

    let original = messages
    let didCompact = ContextCompactor.compactIfNeeded(
      messages: &messages,
      model: testModel,
      contextBudget: 10_000
    )

    #expect(!didCompact)
    #expect(messages.count == original.count)
  }

  // MARK: - Compaction triggers

  @Test("Compacts when over budget")
  func compactsOverBudget() {
    let longContent = String(repeating: "x", count: 2000)
    var messages: [[String: JSONValue]] = []

    /// Create enough messages to exceed a small budget.
    for i in 0..<10 {
      messages.append([
        "role": .string("user"),
        "content": .array([
          .object([
            "type": .string("tool_result"),
            "tool_use_id": .string("toolu_\(i)"),
            "content": .string(longContent),
            "is_error": .bool(false),
          ])
        ]),
      ])
    }

    let didCompact = ContextCompactor.compactIfNeeded(
      messages: &messages,
      model: testModel,
      contextBudget: 500
    )

    #expect(didCompact)
  }

  // MARK: - Preserves recent messages

  @Test("Preserves minimum recent messages")
  func preservesRecentMessages() {
    let longContent = String(repeating: "data", count: 500)
    var messages: [[String: JSONValue]] = []

    /// Create 10 messages with long tool results.
    for i in 0..<10 {
      messages.append([
        "role": .string("user"),
        "content": .array([
          .object([
            "type": .string("tool_result"),
            "tool_use_id": .string("toolu_\(i)"),
            "content": .string(longContent),
            "is_error": .bool(false),
          ])
        ]),
      ])
    }

    /// Save the last 6 messages (minPreserved default) for comparison.
    let lastSixBefore = messages.suffix(6).map { msg -> String in
      if case .array(let content) = msg["content"],
         case .object(let obj) = content.first,
         case .string(let text) = obj["content"]
      {
        return text
      }
      return ""
    }

    ContextCompactor.compactIfNeeded(
      messages: &messages,
      model: testModel,
      contextBudget: 100,
      minPreserved: 6
    )

    /// Last 6 messages should still have their full content.
    let lastSixAfter = messages.suffix(6).map { msg -> String in
      if case .array(let content) = msg["content"],
         case .object(let obj) = content.first,
         case .string(let text) = obj["content"]
      {
        return text
      }
      return ""
    }

    #expect(lastSixBefore == lastSixAfter)
  }

  // MARK: - Truncation marker

  @Test("Truncated content includes marker")
  func truncationMarker() {
    let longContent = String(repeating: "z", count: 2000)
    var messages: [[String: JSONValue]] = [
      [
        "role": .string("user"),
        "content": .array([
          .object([
            "type": .string("tool_result"),
            "tool_use_id": .string("toolu_1"),
            "content": .string(longContent),
            "is_error": .bool(false),
          ])
        ]),
      ],
      /// Add enough messages after to be "preserved".
      ["role": .string("user"), "content": .string("a")],
      ["role": .string("assistant"), "content": .string("b")],
      ["role": .string("user"), "content": .string("c")],
      ["role": .string("assistant"), "content": .string("d")],
      ["role": .string("user"), "content": .string("e")],
      ["role": .string("assistant"), "content": .string("f")],
    ]

    ContextCompactor.compactIfNeeded(
      messages: &messages,
      model: testModel,
      contextBudget: 100,
      minPreserved: 6
    )

    /// First message should have been truncated.
    if case .array(let content) = messages[0]["content"],
       case .object(let obj) = content.first,
       case .string(let text) = obj["content"]
    {
      #expect(text.contains("[truncated by compaction]"))
      #expect(text.count < longContent.count)
    } else {
      Issue.record("Expected truncated tool result content")
    }
  }

  // MARK: - Empty messages

  @Test("Empty messages array does not crash")
  func emptyMessages() {
    var messages: [[String: JSONValue]] = []

    let didCompact = ContextCompactor.compactIfNeeded(
      messages: &messages,
      model: testModel,
      contextBudget: 100
    )

    #expect(!didCompact)
  }

  // MARK: - Custom budget

  @Test("Respects custom context budget")
  func customBudget() {
    var messages: [[String: JSONValue]] = [
      ["role": .string("user"), "content": .string("Hi")],
    ]

    /// With a huge budget, should not compact.
    let didCompact = ContextCompactor.compactIfNeeded(
      messages: &messages,
      model: testModel,
      contextBudget: 1_000_000
    )

    #expect(!didCompact)
  }
}
