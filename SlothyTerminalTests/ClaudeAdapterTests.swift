import Foundation
import Testing

@testable import SlothyTerminalLib

@Suite("ClaudeAdapter")
struct ClaudeAdapterTests {

  private let store = MockTokenStore()

  private var adapter: ClaudeAdapter {
    ClaudeAdapter(tokenStore: store)
  }

  private let sampleModel = ModelDescriptor(
    providerID: .anthropic,
    modelID: "claude-sonnet-4-6",
    packageID: "@ai-sdk/anthropic",
    supportsReasoning: true,
    releaseDate: "2025-05-14",
    outputLimit: 16_384
  )

  private func makeRequest() -> PreparedRequest {
    PreparedRequest(
      url: URL(string: "https://api.anthropic.com/v1/messages")!,
      headers: [:],
      body: Data()
    )
  }

  // MARK: - API Key Auth

  @Test("API key sets x-api-key and anthropic-version headers")
  func apiKeyHeaders() async throws {
    let context = RequestContext(
      sessionID: "s1",
      model: sampleModel,
      auth: .apiKey("sk-ant-test"),
      variant: nil
    )

    let prepared = try await adapter.prepare(request: makeRequest(), context: context)

    #expect(prepared.headers["x-api-key"] == "sk-ant-test")
    #expect(prepared.headers["anthropic-version"] == "2023-06-01")
  }

  // MARK: - anthropic-beta header

  @Test("Always includes interleaved-thinking and fine-grained-tool-streaming beta headers")
  func betaHeader() async throws {
    let context = RequestContext(
      sessionID: "s1",
      model: sampleModel,
      auth: .apiKey("sk-test"),
      variant: nil
    )

    let prepared = try await adapter.prepare(request: makeRequest(), context: context)
    let beta = prepared.headers["anthropic-beta"] ?? ""

    #expect(beta.contains("interleaved-thinking-2025-05-14"))
    #expect(beta.contains("fine-grained-tool-streaming-2025-05-14"))
  }

  @Test("Preserves existing beta headers")
  func preserveExistingBeta() async throws {
    var req = makeRequest()
    req.headers["anthropic-beta"] = "custom-beta-1"

    let context = RequestContext(
      sessionID: "s1",
      model: sampleModel,
      auth: .apiKey("sk-test"),
      variant: nil
    )

    let prepared = try await adapter.prepare(request: req, context: context)
    let beta = prepared.headers["anthropic-beta"] ?? ""

    #expect(beta.contains("custom-beta-1"))
    #expect(beta.contains("interleaved-thinking-2025-05-14"))
  }

  // MARK: - OAuth Auth

  @Test("OAuth sets Authorization Bearer header and removes x-api-key")
  func oauthBearer() async throws {
    let token = OAuthToken(
      accessToken: "oauth-access-abc",
      refreshToken: "refresh-xyz",
      expiresAt: Date().addingTimeInterval(3600),
      accountID: nil
    )

    var req = makeRequest()
    req.headers["x-api-key"] = "should-be-removed"

    let context = RequestContext(
      sessionID: "s1",
      model: sampleModel,
      auth: .oauth(token),
      variant: nil
    )

    let prepared = try await adapter.prepare(request: req, context: context)

    #expect(prepared.headers["Authorization"] == "Bearer oauth-access-abc")
    #expect(prepared.headers["x-api-key"] == nil)
    #expect(prepared.headers["anthropic-version"] == "2023-06-01")
  }

  @Test("OAuth includes all required beta headers")
  func oauthBetaHeader() async throws {
    let token = OAuthToken(
      accessToken: "oauth-access",
      refreshToken: "refresh",
      expiresAt: Date().addingTimeInterval(3600),
      accountID: nil
    )

    let context = RequestContext(
      sessionID: "s1",
      model: sampleModel,
      auth: .oauth(token),
      variant: nil
    )

    let prepared = try await adapter.prepare(request: makeRequest(), context: context)
    let beta = prepared.headers["anthropic-beta"] ?? ""

    #expect(beta.contains("oauth-2025-04-20"))
    #expect(beta.contains("claude-code-20250219"))
    #expect(beta.contains("interleaved-thinking-2025-05-14"))
    #expect(beta.contains("fine-grained-tool-streaming-2025-05-14"))
  }

  @Test("OAuth appends beta=true query parameter to URL")
  func oauthBetaQueryParam() async throws {
    let token = OAuthToken(
      accessToken: "oauth-access",
      refreshToken: "refresh",
      expiresAt: Date().addingTimeInterval(3600),
      accountID: nil
    )

    let context = RequestContext(
      sessionID: "s1",
      model: sampleModel,
      auth: .oauth(token),
      variant: nil
    )

    let prepared = try await adapter.prepare(request: makeRequest(), context: context)

    #expect(prepared.url.query?.contains("beta=true") == true)
  }

  @Test("API key auth does not include OAuth-only beta headers or query param")
  func apiKeyNoBetaOAuth() async throws {
    let context = RequestContext(
      sessionID: "s1",
      model: sampleModel,
      auth: .apiKey("sk-test"),
      variant: nil
    )

    let prepared = try await adapter.prepare(request: makeRequest(), context: context)
    let beta = prepared.headers["anthropic-beta"] ?? ""

    #expect(!beta.contains("oauth-2025-04-20"))
    #expect(!beta.contains("claude-code-20250219"))
    #expect(prepared.url.query == nil)
  }

  // MARK: - No Auth

  @Test("No auth still sets anthropic-version and beta headers")
  func noAuth() async throws {
    let context = RequestContext(
      sessionID: "s1",
      model: sampleModel,
      auth: nil,
      variant: nil
    )

    let prepared = try await adapter.prepare(request: makeRequest(), context: context)

    #expect(prepared.headers["x-api-key"] == nil)
    #expect(prepared.headers["Authorization"] == nil)
    #expect(prepared.headers["anthropic-version"] == "2023-06-01")
    #expect(prepared.headers["anthropic-beta"]?.contains("interleaved-thinking") == true)
    #expect(prepared.headers["anthropic-beta"]?.contains("fine-grained-tool-streaming") == true)
  }

  // MARK: - Variant Options

  @Test("High variant returns thinking with budgetTokens 16000")
  func highVariant() {
    let options = adapter.variantOptions(for: sampleModel, variant: .high)
    let thinking = options["thinking"]

    #expect(thinking == .object([
      "type": .string("enabled"),
      "budgetTokens": .number(16_000),
    ]))
  }

  @Test("Max variant returns thinking with budgetTokens 31999")
  func maxVariant() {
    let options = adapter.variantOptions(for: sampleModel, variant: .max)
    let thinking = options["thinking"]

    #expect(thinking == .object([
      "type": .string("enabled"),
      "budgetTokens": .number(31_999),
    ]))
  }

  @Test("Low variant returns empty options")
  func lowVariant() {
    let options = adapter.variantOptions(for: sampleModel, variant: .low)
    #expect(options.isEmpty)
  }

  // MARK: - Model Filtering

  @Test("allowedModels returns all models")
  func allowedModels() {
    let models = [sampleModel]
    let allowed = adapter.allowedModels(models, auth: .apiKey("key"))
    #expect(allowed.count == 1)
  }

  // MARK: - Default Options

  @Test("defaultOptions returns empty dict")
  func defaultOptions() {
    let options = adapter.defaultOptions(for: sampleModel)
    #expect(options.isEmpty)
  }

  // MARK: - OAuth user-agent

  @Test("OAuth sets user-agent header")
  func oauthUserAgent() async throws {
    let token = OAuthToken(
      accessToken: "oauth-access",
      refreshToken: "refresh",
      expiresAt: Date().addingTimeInterval(3600),
      accountID: nil
    )

    let context = RequestContext(
      sessionID: "s1",
      model: sampleModel,
      auth: .oauth(token),
      variant: nil
    )

    let prepared = try await adapter.prepare(request: makeRequest(), context: context)

    #expect(prepared.headers["user-agent"] == "claude-cli/2.1.2 (external, cli)")
  }

  // MARK: - Tool name prefixing (OAuth)

  @Test("prefixToolNames adds mcp_ prefix to tool definitions")
  func prefixToolDefs() throws {
    let body: [String: Any] = [
      "model": "claude-sonnet-4-6",
      "tools": [
        ["name": "read", "description": "Read a file"],
        ["name": "bash", "description": "Run a command"],
      ],
      "messages": [] as [Any],
    ]
    let data = try JSONSerialization.data(withJSONObject: body)

    let result = ClaudeAdapter.prefixToolNames(in: data)
    let parsed = try JSONSerialization.jsonObject(with: result) as! [String: Any]
    let tools = parsed["tools"] as! [[String: Any]]

    #expect(tools[0]["name"] as? String == "mcp_read")
    #expect(tools[1]["name"] as? String == "mcp_bash")
  }

  @Test("prefixToolNames adds mcp_ prefix to tool_use blocks in messages")
  func prefixToolUseInMessages() throws {
    let body: [String: Any] = [
      "model": "claude-sonnet-4-6",
      "tools": [] as [Any],
      "messages": [
        [
          "role": "assistant",
          "content": [
            ["type": "text", "text": "Let me read that file."],
            ["type": "tool_use", "id": "toolu_01", "name": "read", "input": ["path": "/tmp"]],
          ],
        ],
        [
          "role": "user",
          "content": [
            ["type": "tool_result", "tool_use_id": "toolu_01", "content": "file contents"],
          ],
        ],
      ],
    ]
    let data = try JSONSerialization.data(withJSONObject: body)

    let result = ClaudeAdapter.prefixToolNames(in: data)
    let parsed = try JSONSerialization.jsonObject(with: result) as! [String: Any]
    let messages = parsed["messages"] as! [[String: Any]]

    /// Assistant message: tool_use name should be prefixed.
    let assistantContent = messages[0]["content"] as! [[String: Any]]
    let textBlock = assistantContent[0]
    let toolUseBlock = assistantContent[1]
    #expect(textBlock["type"] as? String == "text")
    #expect(toolUseBlock["name"] as? String == "mcp_read")

    /// User message: tool_result should NOT be prefixed (no name field).
    let userContent = messages[1]["content"] as! [[String: Any]]
    let toolResult = userContent[0]
    #expect(toolResult["type"] as? String == "tool_result")
    #expect(toolResult["name"] as? String == nil)
  }

  @Test("prefixToolNames does not double-prefix already-prefixed names")
  func noDoublePrefix() throws {
    let body: [String: Any] = [
      "model": "claude-sonnet-4-6",
      "tools": [
        ["name": "mcp_read", "description": "Already prefixed"],
      ],
      "messages": [] as [Any],
    ]
    let data = try JSONSerialization.data(withJSONObject: body)

    let result = ClaudeAdapter.prefixToolNames(in: data)
    let parsed = try JSONSerialization.jsonObject(with: result) as! [String: Any]
    let tools = parsed["tools"] as! [[String: Any]]

    #expect(tools[0]["name"] as? String == "mcp_read")
  }
}
