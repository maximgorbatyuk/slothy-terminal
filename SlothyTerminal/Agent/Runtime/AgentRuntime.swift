import Foundation

/// Input for a single LLM call within the agent loop.
struct RuntimeInput: Sendable {
  let sessionID: String
  let model: ModelDescriptor
  let messages: [[String: JSONValue]]
  let tools: [[String: JSONValue]]
  let systemPrompt: String?
  let selectedVariant: ReasoningVariant?
  let userOptions: [String: JSONValue]

  init(
    sessionID: String,
    model: ModelDescriptor,
    messages: [[String: JSONValue]],
    tools: [[String: JSONValue]] = [],
    systemPrompt: String? = nil,
    selectedVariant: ReasoningVariant? = nil,
    userOptions: [String: JSONValue] = [:]
  ) {
    self.sessionID = sessionID
    self.model = model
    self.messages = messages
    self.tools = tools
    self.systemPrompt = systemPrompt
    self.selectedVariant = selectedVariant
    self.userOptions = userOptions
  }
}

/// Protocol for the agent runtime, enabling mock injection in tests.
protocol AgentRuntimeProtocol: Sendable {
  /// Execute a single LLM call and return a stream of provider events.
  func stream(
    _ input: RuntimeInput
  ) async throws -> AsyncThrowingStream<ProviderStreamEvent, Error>
}

/// The real agent runtime that talks to LLM providers via HTTP.
///
/// Assembles options in the correct merge order:
/// 1. Adapter defaults
/// 2. Mapper default thinking
/// 3. Variant options (adapter then mapper)
/// 4. Caller overrides
///
/// Then builds a request, runs it through the provider adapter,
/// and streams SSE events back through the provider stream parser.
final class AgentRuntime: AgentRuntimeProtocol, @unchecked Sendable {
  private let adapters: [ProviderID: any ProviderAdapter]
  private let tokenStore: TokenStore
  private let mapper: VariantMapper
  private let transport: URLSessionHTTPTransport

  init(
    adapters: [ProviderID: any ProviderAdapter],
    tokenStore: TokenStore,
    mapper: VariantMapper,
    transport: URLSessionHTTPTransport = URLSessionHTTPTransport()
  ) {
    self.adapters = adapters
    self.tokenStore = tokenStore
    self.mapper = mapper
    self.transport = transport
  }

  func stream(
    _ input: RuntimeInput
  ) async throws -> AsyncThrowingStream<ProviderStreamEvent, Error> {
    guard let adapter = adapters[input.model.providerID] else {
      throw AgentLoopError.noAdapter(provider: input.model.providerID)
    }

    let auth = try await tokenStore.load(provider: input.model.providerID)

    /// Merge options in the correct order.
    var options = adapter.defaultOptions(for: input.model)
    options.merge(mapper.defaultThinkingOptions(for: input.model)) { _, new in new }

    if let variant = input.selectedVariant {
      options.merge(
        adapter.variantOptions(for: input.model, variant: variant)
      ) { _, new in new }
      options.merge(
        mapper.options(for: input.model, variant: variant)
      ) { _, new in new }
    }

    options.merge(input.userOptions) { _, new in new }

    /// Build the HTTP request.
    let base = try RequestBuilder.build(
      model: input.model,
      messages: input.messages,
      tools: input.tools,
      systemPrompt: input.systemPrompt,
      options: options,
      stream: true
    )

    /// Apply provider-specific auth and URL transformations.
    let context = RequestContext(
      sessionID: input.sessionID,
      model: input.model,
      auth: auth,
      variant: input.selectedVariant
    )
    let prepared = try await adapter.prepare(request: base, context: context)

    /// Stream SSE and parse into provider events.
    let sseStream = transport.stream(request: prepared)
    let providerID = input.model.providerID

    let anthropicParser = ProviderStreamParser()
    return AsyncThrowingStream { continuation in
      let task = Task {
        do {
          for try await sseEvent in sseStream {
            let events: [ProviderStreamEvent]
            switch providerID {
            case .anthropic:
              events = anthropicParser.parseAnthropic(event: sseEvent)

            case .openAI:
              events = ProviderStreamParser.parseOpenAI(event: sseEvent)

            case .zai, .zhipuAI:
              events = ProviderStreamParser.parseOpenAI(event: sseEvent)
            }

            for event in events {
              continuation.yield(event)
            }
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }

      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }
}
