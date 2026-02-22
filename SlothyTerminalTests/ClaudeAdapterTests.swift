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

  @Test("Always includes interleaved-thinking beta header")
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
}
