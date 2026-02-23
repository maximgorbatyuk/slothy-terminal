import Foundation

/// Builds `PreparedRequest` payloads for different LLM provider APIs.
///
/// Branches by `ProviderID` to produce the correct JSON body format:
/// - Anthropic: Messages API (`/v1/messages`)
/// - OpenAI: Chat Completions / Responses API
/// - Z.AI/ZhipuAI: OpenAI-compatible format
enum RequestBuilder {

  // MARK: - Anthropic

  /// Default Anthropic API endpoint.
  static let anthropicURL = URL(string: "https://api.anthropic.com/v1/messages")!

  /// Default OpenAI API endpoint.
  static let openAIURL = URL(string: "https://api.openai.com/v1/chat/completions")!

  /// Default Z.AI API endpoint.
  static let zaiURL = ZAIEndpoint.china.chatCompletionsURL

  /// Maximum tokens for the response.
  private static let defaultMaxTokens = 16_384

  /// Build a `PreparedRequest` for the given model and messages.
  ///
  /// - Parameters:
  ///   - model: The target model descriptor.
  ///   - messages: Conversation messages in provider-agnostic format.
  ///   - tools: Tool definitions for function calling.
  ///   - systemPrompt: Optional system prompt.
  ///   - options: Provider-specific options (thinking, reasoningEffort, etc.).
  ///   - stream: Whether to request streaming responses.
  static func build(
    model: ModelDescriptor,
    messages: [[String: JSONValue]],
    tools: [[String: JSONValue]] = [],
    systemPrompt: String? = nil,
    options: [String: JSONValue] = [:],
    stream: Bool = true
  ) throws -> PreparedRequest {
    switch model.providerID {
    case .anthropic:
      return try buildAnthropic(
        model: model,
        messages: messages,
        tools: tools,
        systemPrompt: systemPrompt,
        options: options,
        stream: stream
      )

    case .openAI:
      return try buildOpenAI(
        model: model,
        messages: messages,
        tools: tools,
        systemPrompt: systemPrompt,
        options: options,
        stream: stream
      )

    case .zai, .zhipuAI:
      return try buildOpenAICompatible(
        model: model,
        messages: messages,
        tools: tools,
        systemPrompt: systemPrompt,
        options: options,
        stream: stream,
        endpoint: zaiURL
      )
    }
  }

  // MARK: - Anthropic Messages API

  private static func buildAnthropic(
    model: ModelDescriptor,
    messages: [[String: JSONValue]],
    tools: [[String: JSONValue]],
    systemPrompt: String?,
    options: [String: JSONValue],
    stream: Bool
  ) throws -> PreparedRequest {
    var body: [String: JSONValue] = [
      "model": .string(model.modelID),
      "max_tokens": .number(Double(model.outputLimit > 0
        ? model.outputLimit
        : defaultMaxTokens)),
      "messages": .array(messages.map { .object($0) }),
      "stream": .bool(stream),
    ]

    if let system = systemPrompt {
      body["system"] = .string(system)
    }

    if !tools.isEmpty {
      let anthropicTools = tools.compactMap { toolDef -> JSONValue? in
        guard case .object(let fn) = toolDef["function"] else {
          return nil
        }
        var toolObj: [String: JSONValue] = [:]
        toolObj["name"] = fn["name"]
        toolObj["description"] = fn["description"]
        toolObj["input_schema"] = fn["parameters"]
        return .object(toolObj)
      }
      body["tools"] = .array(anthropicTools)
    }

    /// Merge provider-specific options (thinking, etc.).
    for (key, value) in options {
      body[key] = value
    }

    let data = try JSONEncoder().encode(body)

    return PreparedRequest(
      url: anthropicURL,
      headers: ["Content-Type": "application/json"],
      body: data
    )
  }

  // MARK: - OpenAI Chat Completions

  private static func buildOpenAI(
    model: ModelDescriptor,
    messages: [[String: JSONValue]],
    tools: [[String: JSONValue]],
    systemPrompt: String?,
    options: [String: JSONValue],
    stream: Bool
  ) throws -> PreparedRequest {
    var allMessages = messages

    if let system = systemPrompt {
      let systemMsg: [String: JSONValue] = [
        "role": .string("system"),
        "content": .string(system),
      ]
      allMessages.insert(systemMsg, at: 0)
    }

    var body: [String: JSONValue] = [
      "model": .string(model.modelID),
      "messages": .array(allMessages.map { .object($0) }),
      "stream": .bool(stream),
    ]

    if !tools.isEmpty {
      body["tools"] = .array(tools.map { .object($0) })
    }

    for (key, value) in options {
      body[key] = value
    }

    let data = try JSONEncoder().encode(body)

    return PreparedRequest(
      url: openAIURL,
      headers: ["Content-Type": "application/json"],
      body: data
    )
  }

  // MARK: - OpenAI-Compatible (Z.AI, etc.)

  private static func buildOpenAICompatible(
    model: ModelDescriptor,
    messages: [[String: JSONValue]],
    tools: [[String: JSONValue]],
    systemPrompt: String?,
    options: [String: JSONValue],
    stream: Bool,
    endpoint: URL
  ) throws -> PreparedRequest {
    var allMessages = messages

    if let system = systemPrompt {
      let systemMsg: [String: JSONValue] = [
        "role": .string("system"),
        "content": .string(system),
      ]
      allMessages.insert(systemMsg, at: 0)
    }

    var body: [String: JSONValue] = [
      "model": .string(model.modelID),
      "messages": .array(allMessages.map { .object($0) }),
      "stream": .bool(stream),
    ]

    if !tools.isEmpty {
      body["tools"] = .array(tools.map { .object($0) })
    }

    for (key, value) in options {
      body[key] = value
    }

    let data = try JSONEncoder().encode(body)

    return PreparedRequest(
      url: endpoint,
      headers: ["Content-Type": "application/json"],
      body: data
    )
  }
}
