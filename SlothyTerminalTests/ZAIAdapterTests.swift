import Foundation
import Testing

@testable import SlothyTerminalLib

@Suite("ZAIAdapter")
struct ZAIAdapterTests {

  private let adapter = ZAIAdapter(providerID: .zai)

  private let glmModel = ModelDescriptor(
    providerID: .zai,
    modelID: "glm-4-plus",
    packageID: "@ai-sdk/zhipu",
    supportsReasoning: true,
    releaseDate: "2025-01-01",
    outputLimit: 8_192
  )

  private func makeRequest() -> PreparedRequest {
    PreparedRequest(
      url: URL(string: "https://open.bigmodel.cn/api/paas/v4/chat/completions")!,
      headers: [:],
      body: Data()
    )
  }

  // MARK: - Default Options

  @Test("Default options enable thinking")
  func defaultOptionsEnableThinking() {
    let options = adapter.defaultOptions(for: glmModel)
    let thinking = options["thinking"]

    #expect(thinking == .object([
      "type": .string("enabled"),
      "clear_thinking": .bool(false),
    ]))
  }

  // MARK: - Variant Options

  @Test("Variant options are always empty")
  func variantOptionsEmpty() {
    let options = adapter.variantOptions(for: glmModel, variant: .high)
    #expect(options.isEmpty)
  }

  // MARK: - API Key Auth

  @Test("API key sets Authorization Bearer header")
  func apiKeyHeaders() async throws {
    let context = RequestContext(
      sessionID: "s1",
      model: glmModel,
      auth: .apiKey("zai-key-123"),
      variant: nil
    )

    let prepared = try await adapter.prepare(request: makeRequest(), context: context)

    #expect(prepared.headers["Authorization"] == "Bearer zai-key-123")
  }

  // MARK: - OAuth Auth

  @Test("OAuth sets Authorization Bearer from access token")
  func oauthHeaders() async throws {
    let token = OAuthToken(
      accessToken: "zai-access",
      refreshToken: "zai-refresh",
      expiresAt: Date().addingTimeInterval(3600),
      accountID: nil
    )

    let context = RequestContext(
      sessionID: "s1",
      model: glmModel,
      auth: .oauth(token),
      variant: nil
    )

    let prepared = try await adapter.prepare(request: makeRequest(), context: context)

    #expect(prepared.headers["Authorization"] == "Bearer zai-access")
  }

  // MARK: - No Auth

  @Test("No auth leaves headers empty")
  func noAuth() async throws {
    let context = RequestContext(
      sessionID: "s1",
      model: glmModel,
      auth: nil,
      variant: nil
    )

    let prepared = try await adapter.prepare(request: makeRequest(), context: context)

    #expect(prepared.headers["Authorization"] == nil)
  }

  // MARK: - Model Filtering

  @Test("allowedModels returns all models")
  func allowedModels() {
    let models = [glmModel]
    let allowed = adapter.allowedModels(models, auth: .apiKey("key"))
    #expect(allowed.count == 1)
  }

  // MARK: - Provider ID

  @Test("zhipuAI provider ID works")
  func zhipuProvider() {
    let zhipuAdapter = ZAIAdapter(providerID: .zhipuAI)
    #expect(zhipuAdapter.providerID == .zhipuAI)
  }

  // MARK: - Endpoint Override

  @Test("Custom endpoint URL overrides request URL")
  func customEndpointOverridesURL() async throws {
    let customURL = URL(string: "https://api.z.ai/api/paas/v4/chat/completions")!
    let customAdapter = ZAIAdapter(providerID: .zai, endpointURL: customURL)

    let context = RequestContext(
      sessionID: "s1",
      model: glmModel,
      auth: .apiKey("key"),
      variant: nil
    )

    let prepared = try await customAdapter.prepare(request: makeRequest(), context: context)

    #expect(prepared.url == customURL)
  }

  @Test("Coding Plan endpoint URL is set correctly")
  func codingPlanEndpoint() async throws {
    let codingURL = URL(string: "https://api.z.ai/api/coding/paas/v4/chat/completions")!
    let codingAdapter = ZAIAdapter(providerID: .zai, endpointURL: codingURL)

    let context = RequestContext(
      sessionID: "s1",
      model: glmModel,
      auth: .apiKey("key"),
      variant: nil
    )

    let prepared = try await codingAdapter.prepare(request: makeRequest(), context: context)

    #expect(prepared.url == codingURL)
  }

  // MARK: - ZAIEndpoint URLs

  @Test("ZAIEndpoint China URL is correct")
  func chinaEndpointURL() {
    #expect(
      ZAIEndpoint.china.chatCompletionsURL.absoluteString
      == "https://open.bigmodel.cn/api/paas/v4/chat/completions"
    )
  }

  @Test("ZAIEndpoint International URL is correct")
  func internationalEndpointURL() {
    #expect(
      ZAIEndpoint.international.chatCompletionsURL.absoluteString
      == "https://api.z.ai/api/paas/v4/chat/completions"
    )
  }

  @Test("ZAIEndpoint Coding Plan URL is correct")
  func codingPlanEndpointURL() {
    #expect(
      ZAIEndpoint.codingPlan.chatCompletionsURL.absoluteString
      == "https://api.z.ai/api/coding/paas/v4/chat/completions"
    )
  }
}
