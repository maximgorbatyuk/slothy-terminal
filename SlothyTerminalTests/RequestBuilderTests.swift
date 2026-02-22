import Foundation
import Testing

@testable import SlothyTerminalLib

@Suite("RequestBuilder")
struct RequestBuilderTests {

  private let anthropicModel = ModelDescriptor(
    providerID: .anthropic,
    modelID: "claude-sonnet-4-6",
    packageID: "@ai-sdk/anthropic",
    supportsReasoning: true,
    releaseDate: "2025-05-14",
    outputLimit: 16_384
  )

  private let openAIModel = ModelDescriptor(
    providerID: .openAI,
    modelID: "gpt-5.1-codex",
    packageID: "@ai-sdk/openai",
    supportsReasoning: true,
    releaseDate: "2025-07-01",
    outputLimit: 32_768
  )

  private let zaiModel = ModelDescriptor(
    providerID: .zai,
    modelID: "glm-4-plus",
    packageID: "@ai-sdk/zhipu",
    supportsReasoning: true,
    releaseDate: "2025-01-01",
    outputLimit: 8_192
  )

  private let sampleMessages: [[String: JSONValue]] = [
    [
      "role": .string("user"),
      "content": .array([
        .object(["type": .string("text"), "text": .string("Hello")])
      ]),
    ]
  ]

  private let sampleTools: [[String: JSONValue]] = [
    [
      "type": .string("function"),
      "function": .object([
        "name": .string("read"),
        "description": .string("Read a file"),
        "parameters": .object([
          "type": .string("object"),
          "properties": .object([
            "file_path": .object([
              "type": .string("string"),
              "description": .string("Path to file"),
            ])
          ]),
          "required": .array([.string("file_path")]),
        ]),
      ]),
    ]
  ]

  // MARK: - Anthropic format

  @Test("Anthropic request targets correct URL")
  func anthropicURL() throws {
    let request = try RequestBuilder.build(model: anthropicModel, messages: sampleMessages)
    #expect(request.url == RequestBuilder.anthropicURL)
  }

  @Test("Anthropic request sets Content-Type header")
  func anthropicHeaders() throws {
    let request = try RequestBuilder.build(model: anthropicModel, messages: sampleMessages)
    #expect(request.headers["Content-Type"] == "application/json")
  }

  @Test("Anthropic body contains model, messages, max_tokens, stream")
  func anthropicBody() throws {
    let request = try RequestBuilder.build(model: anthropicModel, messages: sampleMessages)
    let body = try decodeBody(request.body)

    #expect(body["model"] as? String == "claude-sonnet-4-6")
    #expect(body["stream"] as? Bool == true)
    #expect(body["max_tokens"] as? Int == 16_384)
    #expect(body["messages"] != nil)
  }

  @Test("Anthropic body includes system prompt as top-level field")
  func anthropicSystemPrompt() throws {
    let request = try RequestBuilder.build(
      model: anthropicModel,
      messages: sampleMessages,
      systemPrompt: "You are a coding assistant."
    )
    let body = try decodeBody(request.body)

    #expect(body["system"] as? String == "You are a coding assistant.")
  }

  @Test("Anthropic tools use input_schema format")
  func anthropicToolFormat() throws {
    let request = try RequestBuilder.build(
      model: anthropicModel,
      messages: sampleMessages,
      tools: sampleTools
    )
    let body = try decodeBody(request.body)

    guard let tools = body["tools"] as? [[String: Any]],
          let first = tools.first
    else {
      Issue.record("Expected tools array")
      return
    }

    #expect(first["name"] as? String == "read")
    #expect(first["input_schema"] != nil)
    /// Anthropic format should NOT have "type": "function" wrapper.
    #expect(first["type"] == nil)
  }

  @Test("Anthropic merges options into body")
  func anthropicOptions() throws {
    let request = try RequestBuilder.build(
      model: anthropicModel,
      messages: sampleMessages,
      options: [
        "thinking": .object(["type": .string("adaptive")]),
        "effort": .string("medium"),
      ]
    )
    let body = try decodeBody(request.body)

    #expect(body["effort"] as? String == "medium")

    guard let thinking = body["thinking"] as? [String: Any] else {
      Issue.record("Expected thinking object")
      return
    }

    #expect(thinking["type"] as? String == "adaptive")
  }

  // MARK: - OpenAI format

  @Test("OpenAI request targets correct URL")
  func openAIURL() throws {
    let request = try RequestBuilder.build(model: openAIModel, messages: sampleMessages)
    #expect(request.url == RequestBuilder.openAIURL)
  }

  @Test("OpenAI body contains model, messages, stream")
  func openAIBody() throws {
    let request = try RequestBuilder.build(model: openAIModel, messages: sampleMessages)
    let body = try decodeBody(request.body)

    #expect(body["model"] as? String == "gpt-5.1-codex")
    #expect(body["stream"] as? Bool == true)
    #expect(body["messages"] != nil)
    /// OpenAI format should NOT have max_tokens at top level unless from options.
    #expect(body["max_tokens"] == nil)
  }

  @Test("OpenAI system prompt is prepended as a system message")
  func openAISystemPrompt() throws {
    let request = try RequestBuilder.build(
      model: openAIModel,
      messages: sampleMessages,
      systemPrompt: "You are helpful."
    )
    let body = try decodeBody(request.body)

    guard let messages = body["messages"] as? [[String: Any]] else {
      Issue.record("Expected messages array")
      return
    }

    #expect(messages.count == 2)
    #expect(messages[0]["role"] as? String == "system")
    #expect(messages[0]["content"] as? String == "You are helpful.")
  }

  @Test("OpenAI tools keep function wrapper format")
  func openAIToolFormat() throws {
    let request = try RequestBuilder.build(
      model: openAIModel,
      messages: sampleMessages,
      tools: sampleTools
    )
    let body = try decodeBody(request.body)

    guard let tools = body["tools"] as? [[String: Any]],
          let first = tools.first
    else {
      Issue.record("Expected tools array")
      return
    }

    #expect(first["type"] as? String == "function")
    #expect(first["function"] != nil)
  }

  // MARK: - Z.AI format

  @Test("Z.AI request targets correct URL")
  func zaiURL() throws {
    let request = try RequestBuilder.build(model: zaiModel, messages: sampleMessages)
    #expect(request.url == RequestBuilder.zaiURL)
  }

  @Test("Z.AI body uses OpenAI-compatible format")
  func zaiBody() throws {
    let request = try RequestBuilder.build(model: zaiModel, messages: sampleMessages)
    let body = try decodeBody(request.body)

    #expect(body["model"] as? String == "glm-4-plus")
    #expect(body["stream"] as? Bool == true)
    #expect(body["messages"] != nil)
  }

  // MARK: - Stream flag

  @Test("Non-streaming request sets stream to false")
  func nonStreaming() throws {
    let request = try RequestBuilder.build(
      model: anthropicModel,
      messages: sampleMessages,
      stream: false
    )
    let body = try decodeBody(request.body)

    #expect(body["stream"] as? Bool == false)
  }

  // MARK: - Helpers

  private func decodeBody(_ data: Data) throws -> [String: Any] {
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw NSError(domain: "Test", code: 1, userInfo: [
        NSLocalizedDescriptionKey: "Unable to decode body as JSON object"
      ])
    }
    return json
  }
}
