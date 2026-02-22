import Foundation
import Testing

@testable import SlothyTerminalLib

@Suite("CodexAdapter")
struct CodexAdapterTests {

  private let store = MockTokenStore()

  private var adapter: CodexAdapter {
    CodexAdapter(tokenStore: store)
  }

  private let gpt5Model = ModelDescriptor(
    providerID: .openAI,
    modelID: "gpt-5.1-codex",
    packageID: "@ai-sdk/openai",
    supportsReasoning: true,
    releaseDate: "2025-07-01",
    outputLimit: 32_768
  )

  private let gpt4Model = ModelDescriptor(
    providerID: .openAI,
    modelID: "gpt-4o",
    packageID: "@ai-sdk/openai",
    supportsReasoning: false,
    releaseDate: "2024-05-01",
    outputLimit: 16_384
  )

  private func makeRequest(path: String = "/v1/responses") -> PreparedRequest {
    PreparedRequest(
      url: URL(string: "https://api.openai.com\(path)")!,
      headers: [:],
      body: Data()
    )
  }

  // MARK: - API Key Auth

  @Test("API key sets Authorization Bearer header")
  func apiKeyHeaders() async throws {
    let context = RequestContext(
      sessionID: "s1",
      model: gpt5Model,
      auth: .apiKey("sk-openai-test"),
      variant: nil
    )

    let prepared = try await adapter.prepare(request: makeRequest(), context: context)

    #expect(prepared.headers["Authorization"] == "Bearer sk-openai-test")
  }

  @Test("Strips pre-existing Authorization header")
  func stripsExistingAuth() async throws {
    var req = makeRequest()
    req.headers["Authorization"] = "Bearer old-token"

    let context = RequestContext(
      sessionID: "s1",
      model: gpt5Model,
      auth: .apiKey("new-key"),
      variant: nil
    )

    let prepared = try await adapter.prepare(request: req, context: context)

    #expect(prepared.headers["Authorization"] == "Bearer new-key")
  }

  // MARK: - OAuth URL Rewrite

  @Test("OAuth rewrites /v1/responses to Codex endpoint")
  func urlRewriteResponses() async throws {
    let token = OAuthToken(
      accessToken: "access-token",
      refreshToken: "refresh-token",
      expiresAt: Date().addingTimeInterval(3600),
      accountID: "acct-123"
    )

    let context = RequestContext(
      sessionID: "s1",
      model: gpt5Model,
      auth: .oauth(token),
      variant: nil
    )

    let prepared = try await adapter.prepare(
      request: makeRequest(path: "/v1/responses"),
      context: context
    )

    #expect(prepared.url.absoluteString == "https://chatgpt.com/backend-api/codex/responses")
  }

  @Test("OAuth rewrites /chat/completions to Codex endpoint")
  func urlRewriteCompletions() async throws {
    let token = OAuthToken(
      accessToken: "access-token",
      refreshToken: "refresh-token",
      expiresAt: Date().addingTimeInterval(3600),
      accountID: nil
    )

    let context = RequestContext(
      sessionID: "s1",
      model: gpt5Model,
      auth: .oauth(token),
      variant: nil
    )

    let prepared = try await adapter.prepare(
      request: makeRequest(path: "/chat/completions"),
      context: context
    )

    #expect(prepared.url.absoluteString == "https://chatgpt.com/backend-api/codex/responses")
  }

  @Test("API key does not rewrite URL")
  func noRewriteForAPIKey() async throws {
    let context = RequestContext(
      sessionID: "s1",
      model: gpt5Model,
      auth: .apiKey("key"),
      variant: nil
    )

    let prepared = try await adapter.prepare(
      request: makeRequest(path: "/v1/responses"),
      context: context
    )

    #expect(prepared.url.absoluteString == "https://api.openai.com/v1/responses")
  }

  // MARK: - OAuth Account Header

  @Test("OAuth sets ChatGPT-Account-Id when accountID is present")
  func accountIdHeader() async throws {
    let token = OAuthToken(
      accessToken: "access",
      refreshToken: "refresh",
      expiresAt: Date().addingTimeInterval(3600),
      accountID: "acct-456"
    )

    let context = RequestContext(
      sessionID: "s1",
      model: gpt5Model,
      auth: .oauth(token),
      variant: nil
    )

    let prepared = try await adapter.prepare(request: makeRequest(), context: context)

    #expect(prepared.headers["ChatGPT-Account-Id"] == "acct-456")
  }

  @Test("OAuth omits ChatGPT-Account-Id when accountID is nil")
  func noAccountIdHeader() async throws {
    let token = OAuthToken(
      accessToken: "access",
      refreshToken: "refresh",
      expiresAt: Date().addingTimeInterval(3600),
      accountID: nil
    )

    let context = RequestContext(
      sessionID: "s1",
      model: gpt5Model,
      auth: .oauth(token),
      variant: nil
    )

    let prepared = try await adapter.prepare(request: makeRequest(), context: context)

    #expect(prepared.headers["ChatGPT-Account-Id"] == nil)
  }

  // MARK: - Model Filtering

  @Test("OAuth mode filters to codex-compatible models only")
  func oauthModelFiltering() {
    let models = [gpt5Model, gpt4Model]
    let oauthToken = OAuthToken(
      accessToken: "a",
      refreshToken: "r",
      expiresAt: Date(),
      accountID: nil
    )

    let allowed = adapter.allowedModels(models, auth: .oauth(oauthToken))

    #expect(allowed.count == 1)
    #expect(allowed.first?.modelID == "gpt-5.1-codex")
  }

  @Test("API key mode returns all models")
  func apiKeyReturnsAllModels() {
    let models = [gpt5Model, gpt4Model]
    let allowed = adapter.allowedModels(models, auth: .apiKey("key"))

    #expect(allowed.count == 2)
  }

  // MARK: - Default Options

  @Test("GPT-5 model gets default reasoning options")
  func gpt5DefaultOptions() {
    let options = adapter.defaultOptions(for: gpt5Model)

    #expect(options["store"] == .bool(false))
    #expect(options["reasoningEffort"] == .string("medium"))
    #expect(options["reasoningSummary"] == .string("auto"))
  }

  @Test("Non-GPT-5 model gets store:false only")
  func gpt4DefaultOptions() {
    let options = adapter.defaultOptions(for: gpt4Model)

    #expect(options["store"] == .bool(false))
    #expect(options["reasoningEffort"] == nil)
  }

  // MARK: - Variant Options

  @Test("Variant sets reasoningEffort for GPT models")
  func variantOptions() {
    let options = adapter.variantOptions(for: gpt5Model, variant: .high)
    #expect(options["reasoningEffort"] == .string("high"))
  }

  @Test("Variant returns empty for non-GPT model")
  func variantOptionsNonGPT() {
    let nonGPT = ModelDescriptor(
      providerID: .openAI,
      modelID: "whisper-1",
      packageID: "@ai-sdk/openai",
      supportsReasoning: false,
      releaseDate: "2024-01-01",
      outputLimit: 0
    )
    let options = adapter.variantOptions(for: nonGPT, variant: .high)
    #expect(options.isEmpty)
  }
}
