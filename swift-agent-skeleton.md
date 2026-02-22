# Swift Multi-Provider Agent: Detailed Implementation (macOS)

This document is a concrete implementation blueprint you can apply in another macOS app.

Target providers in this design:

- Codex via OpenAI OAuth subscription flow (+ API key fallback)
- Claude via Anthropic API key and OAuth subscription flow
- Z.AI / Zhipu GLM with default thinking enabled

This design mirrors OpenCode patterns:

- auth/plugin-like transport patching
- per-provider request transformation
- per-model variant mapping (`low`, `high`, etc.)
- persisted model + variant state

## 0) Package and target structure

```text
Package.swift
Sources/
  AgentCore/
    Models/
      ProviderID.swift
      ModelDescriptor.swift
      AuthState.swift
      ReasoningVariant.swift
      ChatPayload.swift
      MessagePart.swift
      SessionMessage.swift
    Protocols/
      TokenStore.swift
      OAuthClient.swift
      ProviderAdapter.swift
      VariantMapper.swift
      Transport.swift
      ToolProtocol.swift
      PermissionDelegate.swift
    Runtime/
      AgentRuntime.swift
      AgentLoop.swift
      ToolRegistry.swift
      StreamProcessor.swift
      SessionManager.swift
      ContextCompactor.swift
      RequestBuilder.swift
      JSONValue.swift
    Agents/
      AgentDefinition.swift
  AgentStorage/
    Keychain/
      KeychainTokenStore.swift
    Database/
      SessionStore.swift
  AgentAdapters/
    Codex/
      CodexOAuthClient.swift
      CodexAdapter.swift
    Claude/
      ClaudeOAuthClient.swift
      ClaudeAdapter.swift
    Variants/
      DefaultVariantMapper.swift
  AgentTools/
    BashTool.swift
    ReadFileTool.swift
    WriteFileTool.swift
    EditFileTool.swift
    GlobTool.swift
    GrepTool.swift
    WebFetchTool.swift
    TaskTool.swift
Tests/
  AgentCoreTests/
  AgentAdaptersTests/
  AgentToolsTests/
```

Use four internal Swift targets (`AgentCore`, `AgentStorage`, `AgentAdapters`, `AgentTools`) so your app target imports only one facade if desired.

---

## 1) Protocols and models (copy-ready)

### `ProviderID.swift`

```swift
import Foundation

public enum ProviderID: String, Codable, Sendable {
  case openAI = "openai"
  case anthropic = "anthropic"
  case zai = "zai"
  case zhipuAI = "zhipuai"
}
```

### `ReasoningVariant.swift`

```swift
import Foundation

public enum ReasoningVariant: String, Codable, CaseIterable, Sendable {
  case none
  case minimal
  case low
  case medium
  case high
  case max
  case xhigh
}
```

### `ModelDescriptor.swift`

```swift
import Foundation

public struct ModelDescriptor: Codable, Sendable, Hashable {
  public let providerID: ProviderID
  public let modelID: String
  public let packageID: String
  public let supportsReasoning: Bool
  public let releaseDate: String
  public let outputLimit: Int

  public init(
    providerID: ProviderID,
    modelID: String,
    packageID: String,
    supportsReasoning: Bool,
    releaseDate: String,
    outputLimit: Int
  ) {
    self.providerID = providerID
    self.modelID = modelID
    self.packageID = packageID
    self.supportsReasoning = supportsReasoning
    self.releaseDate = releaseDate
    self.outputLimit = outputLimit
  }
}
```

### `AuthState.swift`

```swift
import Foundation

public struct OAuthToken: Codable, Sendable, Equatable {
  public let accessToken: String
  public let refreshToken: String
  public let expiresAt: Date
  public let accountID: String?

  public init(accessToken: String, refreshToken: String, expiresAt: Date, accountID: String?) {
    self.accessToken = accessToken
    self.refreshToken = refreshToken
    self.expiresAt = expiresAt
    self.accountID = accountID
  }
}

public enum AuthMode: Codable, Sendable, Equatable {
  case apiKey(String)
  case oauth(OAuthToken)
}
```

### `JSONValue.swift` (typed JSON container)

```swift
import Foundation

public enum JSONValue: Codable, Sendable, Equatable {
  case string(String)
  case number(Double)
  case bool(Bool)
  case object([String: JSONValue])
  case array([JSONValue])
  case null
}
```

### `ProviderAdapter.swift` + supporting types

```swift
import Foundation

public struct RequestContext: Sendable {
  public let sessionID: String
  public let model: ModelDescriptor
  public let auth: AuthMode?
  public let variant: ReasoningVariant?

  public init(sessionID: String, model: ModelDescriptor, auth: AuthMode?, variant: ReasoningVariant?) {
    self.sessionID = sessionID
    self.model = model
    self.auth = auth
    self.variant = variant
  }
}

public struct PreparedRequest: Sendable {
  public var url: URL
  public var method: String
  public var headers: [String: String]
  public var body: Data

  public init(url: URL, method: String = "POST", headers: [String: String], body: Data) {
    self.url = url
    self.method = method
    self.headers = headers
    self.body = body
  }
}

public protocol ProviderAdapter: Sendable {
  var providerID: ProviderID { get }

  func allowedModels(_ models: [ModelDescriptor], auth: AuthMode?) -> [ModelDescriptor]
  func defaultOptions(for model: ModelDescriptor) -> [String: JSONValue]
  func variantOptions(for model: ModelDescriptor, variant: ReasoningVariant) -> [String: JSONValue]
  func prepare(request: PreparedRequest, context: RequestContext) async throws -> PreparedRequest
}
```

### `TokenStore.swift` and `OAuthClient.swift`

```swift
import Foundation

public protocol TokenStore: Sendable {
  func load(provider: ProviderID) async throws -> AuthMode?
  func save(provider: ProviderID, auth: AuthMode) async throws
  func remove(provider: ProviderID) async throws
}

public protocol OAuthClient: Sendable {
  associatedtype StartPayload
  func startAuthorization() async throws -> StartPayload
  func exchange(code: String) async throws -> OAuthToken
  func refresh(token: OAuthToken) async throws -> OAuthToken
}
```

### `VariantMapper.swift`

```swift
import Foundation

public protocol VariantMapper: Sendable {
  func variants(for model: ModelDescriptor) -> [ReasoningVariant]
  func options(for model: ModelDescriptor, variant: ReasoningVariant) -> [String: JSONValue]
  func defaultThinkingOptions(for model: ModelDescriptor) -> [String: JSONValue]
}
```

---

## 2) Keychain token store (production-safe baseline)

### `KeychainTokenStore.swift`

```swift
import Foundation
import Security
import AgentCore

public final class KeychainTokenStore: TokenStore {
  private let service: String
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  public init(service: String = "com.example.agent.auth") {
    self.service = service
  }

  public func load(provider: ProviderID) async throws -> AuthMode? {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: provider.rawValue,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne
    ]

    var out: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &out)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = out as? Data else {
      throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
    }

    return try decoder.decode(AuthMode.self, from: data)
  }

  public func save(provider: ProviderID, auth: AuthMode) async throws {
    let data = try encoder.encode(auth)

    let deleteQuery: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: provider.rawValue
    ]
    SecItemDelete(deleteQuery as CFDictionary)

    let addQuery: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: provider.rawValue,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
      kSecValueData as String: data
    ]

    let status = SecItemAdd(addQuery as CFDictionary, nil)
    guard status == errSecSuccess else {
      throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
    }
  }

  public func remove(provider: ProviderID) async throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: provider.rawValue
    ]
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
    }
  }
}
```

Notes:

- Keep this store app-group aware if you share credentials between helper processes.
- For stricter environments, swap accessibility class to `kSecAttrAccessibleWhenUnlocked`.

---

## 3) Codex implementation (OAuth + transport patch)

### 3.1 `CodexOAuthClient.swift`

```swift
import Foundation
import CryptoKit
import AgentCore

public struct CodexOAuthStart: Sendable {
  public let authorizeURL: URL
  public let state: String
  public let verifier: String
}

public final class CodexOAuthClient: OAuthClient {
  public typealias StartPayload = CodexOAuthStart

  private let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
  private let issuer = URL(string: "https://auth.openai.com")!
  private let redirectURI: String
  private let session: URLSession

  public init(redirectURI: String, session: URLSession = .shared) {
    self.redirectURI = redirectURI
    self.session = session
  }

  public func startAuthorization() async throws -> CodexOAuthStart {
    let verifier = Self.randomURLSafe(length: 64)
    let challenge = Self.pkceChallenge(verifier)
    let state = Self.randomURLSafe(length: 32)

    var comp = URLComponents(url: issuer.appendingPathComponent("oauth/authorize"), resolvingAgainstBaseURL: false)!
    comp.queryItems = [
      .init(name: "response_type", value: "code"),
      .init(name: "client_id", value: clientID),
      .init(name: "redirect_uri", value: redirectURI),
      .init(name: "scope", value: "openid profile email offline_access"),
      .init(name: "code_challenge", value: challenge),
      .init(name: "code_challenge_method", value: "S256"),
      .init(name: "state", value: state),
      .init(name: "id_token_add_organizations", value: "true"),
      .init(name: "codex_cli_simplified_flow", value: "true"),
      .init(name: "originator", value: "your-app")
    ]
    return CodexOAuthStart(authorizeURL: comp.url!, state: state, verifier: verifier)
  }

  public func exchange(code: String) async throws -> OAuthToken {
    throw NSError(domain: "CodexOAuthClient", code: 1, userInfo: [NSLocalizedDescriptionKey: "Use exchange(code:verifier:)"])
  }

  public func exchange(code: String, verifier: String) async throws -> OAuthToken {
    var req = URLRequest(url: issuer.appendingPathComponent("oauth/token"))
    req.httpMethod = "POST"
    req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

    let body = [
      "grant_type": "authorization_code",
      "code": code,
      "redirect_uri": redirectURI,
      "client_id": clientID,
      "code_verifier": verifier
    ]
    req.httpBody = Self.formURLEncoded(body).data(using: .utf8)

    let (data, resp) = try await session.data(for: req)
    guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      throw NSError(domain: "CodexOAuthClient", code: 2)
    }

    let payload = try JSONDecoder().decode(TokenResponse.self, from: data)
    return OAuthToken(
      accessToken: payload.access_token,
      refreshToken: payload.refresh_token,
      expiresAt: Date().addingTimeInterval(TimeInterval(payload.expires_in ?? 3600)),
      accountID: Self.extractAccountID(idToken: payload.id_token, accessToken: payload.access_token)
    )
  }

  public func refresh(token: OAuthToken) async throws -> OAuthToken {
    var req = URLRequest(url: issuer.appendingPathComponent("oauth/token"))
    req.httpMethod = "POST"
    req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    req.httpBody = Self.formURLEncoded([
      "grant_type": "refresh_token",
      "refresh_token": token.refreshToken,
      "client_id": clientID
    ]).data(using: .utf8)

    let (data, resp) = try await session.data(for: req)
    guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      throw NSError(domain: "CodexOAuthClient", code: 3)
    }

    let payload = try JSONDecoder().decode(TokenResponse.self, from: data)
    return OAuthToken(
      accessToken: payload.access_token,
      refreshToken: payload.refresh_token,
      expiresAt: Date().addingTimeInterval(TimeInterval(payload.expires_in ?? 3600)),
      accountID: Self.extractAccountID(idToken: payload.id_token, accessToken: payload.access_token) ?? token.accountID
    )
  }

  private struct TokenResponse: Codable {
    let id_token: String?
    let access_token: String
    let refresh_token: String
    let expires_in: Int?
  }

  private static func pkceChallenge(_ verifier: String) -> String {
    let digest = SHA256.hash(data: Data(verifier.utf8))
    return Data(digest).base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }

  private static func randomURLSafe(length: Int) -> String {
    let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
    var out = ""
    out.reserveCapacity(length)
    for _ in 0..<length { out.append(alphabet.randomElement()!) }
    return out
  }

  private static func formURLEncoded(_ map: [String: String]) -> String {
    map.map { key, val in
      let k = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
      let v = val.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? val
      return "\(k)=\(v)"
    }.joined(separator: "&")
  }

  private static func extractAccountID(idToken: String?, accessToken: String) -> String? {
    if let idToken, let claims = decodeJWTPayload(idToken), let id = accountID(from: claims) { return id }
    if let claims = decodeJWTPayload(accessToken), let id = accountID(from: claims) { return id }
    return nil
  }

  private static func decodeJWTPayload(_ token: String) -> [String: Any]? {
    let parts = token.split(separator: ".")
    guard parts.count == 3 else { return nil }
    var payload = String(parts[1])
      .replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    while payload.count % 4 != 0 { payload += "=" }
    guard let data = Data(base64Encoded: payload) else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
  }

  private static func accountID(from claims: [String: Any]) -> String? {
    if let root = claims["chatgpt_account_id"] as? String { return root }
    if let nested = (claims["https://api.openai.com/auth"] as? [String: Any])?["chatgpt_account_id"] as? String { return nested }
    if let org = (claims["organizations"] as? [[String: Any]])?.first?["id"] as? String { return org }
    return nil
  }
}
```

### 3.2 `CodexAdapter.swift`

```swift
import Foundation
import AgentCore

public final class CodexAdapter: ProviderAdapter {
  public let providerID: ProviderID = .openAI

  private let tokenStore: TokenStore
  private let oauth: CodexOAuthClient
  private let codexEndpoint = URL(string: "https://chatgpt.com/backend-api/codex/responses")!
  private let refreshSkew: TimeInterval = 30

  private let oauthAllowedModels: Set<String> = [
    "gpt-5.1-codex",
    "gpt-5.1-codex-mini",
    "gpt-5.1-codex-max",
    "gpt-5.2",
    "gpt-5.2-codex",
    "gpt-5.3-codex"
  ]

  public init(tokenStore: TokenStore, oauth: CodexOAuthClient) {
    self.tokenStore = tokenStore
    self.oauth = oauth
  }

  public func allowedModels(_ models: [ModelDescriptor], auth: AuthMode?) -> [ModelDescriptor] {
    guard case .oauth = auth else { return models }
    return models.filter { m in m.modelID.contains("codex") || oauthAllowedModels.contains(m.modelID) }
  }

  public func defaultOptions(for model: ModelDescriptor) -> [String: JSONValue] {
    var out: [String: JSONValue] = ["store": .bool(false)]
    if model.modelID.contains("gpt-5"), !model.modelID.contains("gpt-5-pro") {
      out["reasoningEffort"] = .string("medium")
      out["reasoningSummary"] = .string("auto")
    }
    return out
  }

  public func variantOptions(for model: ModelDescriptor, variant: ReasoningVariant) -> [String: JSONValue] {
    guard model.modelID.contains("gpt-") else { return [:] }
    return ["reasoningEffort": .string(variant.rawValue)]
  }

  public func prepare(request: PreparedRequest, context: RequestContext) async throws -> PreparedRequest {
    var req = request
    var headers = req.headers
    headers.removeValue(forKey: "Authorization")
    headers.removeValue(forKey: "authorization")

    guard let auth = context.auth else {
      req.headers = headers
      return req
    }

    switch auth {
    case .apiKey(let key):
      headers["Authorization"] = "Bearer \(key)"
      req.headers = headers
      return req

    case .oauth(let token):
      let active: OAuthToken
      if token.expiresAt.timeIntervalSinceNow <= refreshSkew {
        let refreshed = try await oauth.refresh(token: token)
        try await tokenStore.save(provider: .openAI, auth: .oauth(refreshed))
        active = refreshed
      } else {
        active = token
      }

      headers["Authorization"] = "Bearer \(active.accessToken)"
      if let account = active.accountID {
        headers["ChatGPT-Account-Id"] = account
      }

      let path = req.url.path
      if path.contains("/v1/responses") || path.contains("/chat/completions") {
        req.url = codexEndpoint
      }

      req.headers = headers
      return req
    }
  }
}
```

---

## 4) Claude adapter (API key + OAuth)

### 4.1 `ClaudeOAuthClient.swift`

```swift
import Foundation
import AgentCore

public final class ClaudeOAuthClient: OAuthClient {
  public struct StartPayload: Sendable {
    public let authorizeURL: URL
    public let verifier: String
    public let state: String
  }

  private let clientID = "<your-anthropic-client-id>"
  private let redirectURI: String
  private let session: URLSession

  public init(redirectURI: String, session: URLSession = .shared) {
    self.redirectURI = redirectURI
    self.session = session
  }

  public func startAuthorization() async throws -> StartPayload {
    // Keep same shape as Codex for app-level OAuth UX consistency.
    let verifier = UUID().uuidString.replacingOccurrences(of: "-", with: "")
    let state = UUID().uuidString
    var c = URLComponents(string: "https://claude.ai/oauth/authorize")!
    c.queryItems = [
      .init(name: "response_type", value: "code"),
      .init(name: "client_id", value: clientID),
      .init(name: "redirect_uri", value: redirectURI),
      .init(name: "scope", value: "org:create_api_key user:profile user:inference"),
      .init(name: "state", value: state)
    ]
    return .init(authorizeURL: c.url!, verifier: verifier, state: state)
  }

  public func exchange(code: String) async throws -> OAuthToken {
    // Exchange endpoint depends on your app registration and Anthropic OAuth setup.
    throw NSError(domain: "ClaudeOAuthClient", code: 101, userInfo: [NSLocalizedDescriptionKey: "Implement exchange for your OAuth app"])
  }

  public func refresh(token: OAuthToken) async throws -> OAuthToken {
    // Same note: implement based on your registered OAuth app contract.
    throw NSError(domain: "ClaudeOAuthClient", code: 102, userInfo: [NSLocalizedDescriptionKey: "Implement refresh for your OAuth app"])
  }
}
```

### 4.2 `ClaudeAdapter.swift`

```swift
import Foundation
import AgentCore

public final class ClaudeAdapter: ProviderAdapter {
  public let providerID: ProviderID = .anthropic

  private let tokenStore: TokenStore
  private let oauth: ClaudeOAuthClient
  private let refreshSkew: TimeInterval = 30

  public init(tokenStore: TokenStore, oauth: ClaudeOAuthClient) {
    self.tokenStore = tokenStore
    self.oauth = oauth
  }

  public func allowedModels(_ models: [ModelDescriptor], auth: AuthMode?) -> [ModelDescriptor] {
    models
  }

  public func defaultOptions(for model: ModelDescriptor) -> [String: JSONValue] {
    // Keep empty by default, rely on variant mapping for thinking.
    [:]
  }

  public func variantOptions(for model: ModelDescriptor, variant: ReasoningVariant) -> [String: JSONValue] {
    switch variant {
    case .high:
      return ["thinking": .object(["type": .string("enabled"), "budgetTokens": .number(16_000)])]
    case .max:
      return ["thinking": .object(["type": .string("enabled"), "budgetTokens": .number(31_999)])]
    case .low, .medium:
      // For adaptive models only; no-op here, mapper can override with adaptive shape.
      return [:]
    default:
      return [:]
    }
  }

  public func prepare(request: PreparedRequest, context: RequestContext) async throws -> PreparedRequest {
    var req = request
    var headers = req.headers

    // Merge betas in one place, preserving caller-provided values.
    let incoming = headers["anthropic-beta"]?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? []
    let required = ["interleaved-thinking-2025-05-14"]
    headers["anthropic-beta"] = Array(Set(incoming + required)).joined(separator: ",")

    guard let auth = context.auth else {
      req.headers = headers
      return req
    }

    switch auth {
    case .apiKey(let key):
      headers["x-api-key"] = key
      headers["anthropic-version"] = "2023-06-01"

    case .oauth(let token):
      let active: OAuthToken
      if token.expiresAt.timeIntervalSinceNow <= refreshSkew {
        let refreshed = try await oauth.refresh(token: token)
        try await tokenStore.save(provider: .anthropic, auth: .oauth(refreshed))
        active = refreshed
      } else {
        active = token
      }
      headers.removeValue(forKey: "x-api-key")
      headers["Authorization"] = "Bearer \(active.accessToken)"
    }

    req.headers = headers
    return req
  }
}
```

---

## 5) Thinking variant mapper (Codex + Claude + Z.AI)

### `DefaultVariantMapper.swift`

```swift
import Foundation
import AgentCore

public struct DefaultVariantMapper: VariantMapper {
  public init() {}

  public func variants(for model: ModelDescriptor) -> [ReasoningVariant] {
    guard model.supportsReasoning else { return [] }

    let id = model.modelID.lowercased()

    // GLM models: no manual variants in OpenCode behavior.
    if id.contains("glm") { return [] }

    switch model.providerID {
    case .openAI:
      if id.contains("codex") {
        if id.contains("5.2") || id.contains("5.3") { return [.low, .medium, .high, .xhigh] }
        return [.low, .medium, .high]
      }
      // Non-codex GPT-5 style examples
      if id.contains("gpt-5") { return [.minimal, .low, .medium, .high] }
      return [.low, .medium, .high]

    case .anthropic:
      if isAdaptiveAnthropic(id: id) { return [.low, .medium, .high, .max] }
      return [.high, .max]

    case .zai, .zhipuAI:
      return []
    }
  }

  public func options(for model: ModelDescriptor, variant: ReasoningVariant) -> [String: JSONValue] {
    let id = model.modelID.lowercased()
    switch model.providerID {
    case .openAI:
      return [
        "reasoningEffort": .string(variant.rawValue),
        "reasoningSummary": .string("auto")
      ]

    case .anthropic:
      if isAdaptiveAnthropic(id: id) {
        return [
          "thinking": .object(["type": .string("adaptive")]),
          "effort": .string(variant.rawValue)
        ]
      }
      if variant == .high {
        return ["thinking": .object(["type": .string("enabled"), "budgetTokens": .number(16_000)])]
      }
      if variant == .max {
        return ["thinking": .object(["type": .string("enabled"), "budgetTokens": .number(31_999)])]
      }
      return [:]

    case .zai, .zhipuAI:
      return [:]
    }
  }

  public func defaultThinkingOptions(for model: ModelDescriptor) -> [String: JSONValue] {
    // OpenCode behavior: enable thinking by default for zai/zhipu openai-compatible.
    switch model.providerID {
    case .zai, .zhipuAI:
      return [
        "thinking": .object([
          "type": .string("enabled"),
          "clear_thinking": .bool(false)
        ])
      ]
    default:
      return [:]
    }
  }

  private func isAdaptiveAnthropic(id: String) -> Bool {
    id.contains("opus-4-6") || id.contains("opus-4.6") || id.contains("sonnet-4-6") || id.contains("sonnet-4.6")
  }
}
```

---

## 6) Runtime composition (where these pieces are used)

### `AgentRuntime.swift` (flow)

```swift
import Foundation

public struct RuntimeInput: Sendable {
  public let sessionID: String
  public let model: ModelDescriptor
  public let messages: [[String: JSONValue]]
  public let selectedVariant: ReasoningVariant?
  public let userOptions: [String: JSONValue]
}

public protocol Transport: Sendable {
  func execute(_ request: PreparedRequest) async throws -> (Data, HTTPURLResponse)
}

public final class AgentRuntime {
  private let adapters: [ProviderID: any ProviderAdapter]
  private let tokenStore: TokenStore
  private let mapper: VariantMapper
  private let transport: Transport

  public init(
    adapters: [ProviderID: any ProviderAdapter],
    tokenStore: TokenStore,
    mapper: VariantMapper,
    transport: Transport
  ) {
    self.adapters = adapters
    self.tokenStore = tokenStore
    self.mapper = mapper
    self.transport = transport
  }

  public func run(_ input: RuntimeInput) async throws -> (Data, HTTPURLResponse) {
    guard let adapter = adapters[input.model.providerID] else {
      throw NSError(domain: "AgentRuntime", code: 404)
    }

    let auth = try await tokenStore.load(provider: input.model.providerID)

    var options = adapter.defaultOptions(for: input.model)
    options.merge(mapper.defaultThinkingOptions(for: input.model)) { _, new in new }
    if let variant = input.selectedVariant {
      options.merge(adapter.variantOptions(for: input.model, variant: variant)) { _, new in new }
      options.merge(mapper.options(for: input.model, variant: variant)) { _, new in new }
    }
    options.merge(input.userOptions) { _, new in new }

    let base = try RequestBuilder.build(model: input.model, messages: input.messages, options: options)
    let ctx = RequestContext(sessionID: input.sessionID, model: input.model, auth: auth, variant: input.selectedVariant)
    let prepared = try await adapter.prepare(request: base, context: ctx)

    return try await transport.execute(prepared)
  }
}
```

Important merge order:

1. adapter defaults
2. mapper default thinking
3. variant options
4. caller overrides

This is the same practical order OpenCode uses (base -> variant override).

---

## 7) UI persistence recommendations (macOS app side)

Persist per-model selection:

- key: `"<providerID>/<modelID>"`
- value: selected `ReasoningVariant?`

Persist model recents/favorites separately:

- recents: array of `(providerID, modelID)`
- favorites: array of `(providerID, modelID)`

This mirrors OpenCode's behavior and gives stable UX when users switch between models.

---

## 8) Security and operational notes

- Register your own OAuth app credentials. Do not reuse third-party client IDs in production.
- Keep refresh skew (20-60s) to avoid edge expiry races.
- Add retry only for transient statuses (408, 429, 5xx).
- Keep provider-specific quirks isolated in adapters.
- Log request IDs and provider model IDs for debugging, but never log tokens.

---

## 9) Implementation checklist

1. Add core types and protocols.
2. Implement Keychain token store.
3. Implement Codex OAuth start/exchange/refresh.
4. Implement Codex adapter URL rewrite + account header.
5. Implement Claude adapter API-key path first.
6. Add Claude OAuth refresh path.
7. Implement variant mapper for openai/anthropic/zai.
8. Wire runtime merge/build/prepare/execute flow.
9. Add tests for:
   - token refresh path
   - codex endpoint rewrite
   - variant payload mapping
   - z.ai default thinking payload

---

## 10) Tool protocol and registry (the core of the agent system)

The existing sections (1-9) cover the **transport layer** — auth, variant mapping, and request building. Sections 10-16 add the **agent layer**: tool execution, the agent loop, streaming, session management, and permissions. These mirror the patterns from OpenCode's `packages/opencode/src/tool/`, `session/`, and `permission/` directories.

### `ToolProtocol.swift`

```swift
import Foundation

/// JSON Schema representation for tool parameter definitions.
public struct ToolParameterSchema: Codable, Sendable {
  public let type: String // "object"
  public let properties: [String: PropertySchema]
  public let required: [String]

  public struct PropertySchema: Codable, Sendable {
    public let type: String
    public let description: String?
    public let enumValues: [String]?

    enum CodingKeys: String, CodingKey {
      case type, description
      case enumValues = "enum"
    }
  }
}

/// Result returned by a tool execution.
public struct ToolResult: Sendable {
  public let output: String
  public let isError: Bool
  public let metadata: [String: JSONValue]

  public init(output: String, isError: Bool = false, metadata: [String: JSONValue] = [:]) {
    self.output = output
    self.isError = isError
    self.metadata = metadata
  }
}

/// Context provided to tool execution.
public struct ToolContext: Sendable {
  public let sessionID: String
  public let workingDirectory: URL
  public let permissions: PermissionDelegate

  public init(sessionID: String, workingDirectory: URL, permissions: PermissionDelegate) {
    self.sessionID = sessionID
    self.workingDirectory = workingDirectory
    self.permissions = permissions
  }
}

/// Protocol every tool must implement.
/// Mirrors OpenCode's Tool.Info interface.
public protocol AgentTool: Sendable {
  /// Unique identifier (e.g., "bash", "read", "edit").
  var id: String { get }

  /// Human-readable description for the LLM.
  var description: String { get }

  /// JSON Schema for the tool's parameters.
  var parameters: ToolParameterSchema { get }

  /// Execute the tool with decoded arguments.
  func execute(arguments: [String: JSONValue], context: ToolContext) async throws -> ToolResult
}
```

### `ToolRegistry.swift`

```swift
import Foundation

/// Assembles available tools based on agent mode and configuration.
/// Mirrors OpenCode's ToolRegistry.all().
public final class ToolRegistry: @unchecked Sendable {
  private var builtIn: [AgentTool] = []
  private var custom: [AgentTool] = []

  public init() {}

  public func register(_ tool: AgentTool) {
    custom.append(tool)
  }

  public func registerBuiltIn(_ tools: [AgentTool]) {
    builtIn = tools
  }

  /// Returns tools available for a given agent mode.
  public func tools(for mode: AgentMode) -> [AgentTool] {
    let all = builtIn + custom
    switch mode {
    case .primary:
      return all
    case .readOnly:
      let readOnlyIDs: Set<String> = ["read", "glob", "grep", "bash", "ls", "webfetch"]
      return all.filter { readOnlyIDs.contains($0.id) }
    case .subagent:
      return all
    }
  }

  /// Convert tools to the format expected by LLM APIs (function calling schema).
  public func toolDefinitions(for mode: AgentMode) -> [[String: JSONValue]] {
    tools(for: mode).map { tool in
      [
        "type": .string("function"),
        "function": .object([
          "name": .string(tool.id),
          "description": .string(tool.description),
          "parameters": encodeSchema(tool.parameters)
        ])
      ]
    }
  }

  public func tool(byID id: String) -> AgentTool? {
    (builtIn + custom).first { $0.id == id }
  }

  private func encodeSchema(_ schema: ToolParameterSchema) -> JSONValue {
    // Convert ToolParameterSchema to JSONValue for API payload
    var props: [String: JSONValue] = [:]
    for (key, prop) in schema.properties {
      var obj: [String: JSONValue] = ["type": .string(prop.type)]
      if let desc = prop.description { obj["description"] = .string(desc) }
      if let vals = prop.enumValues { obj["enum"] = .array(vals.map { .string($0) }) }
      props[key] = .object(obj)
    }
    return .object([
      "type": .string(schema.type),
      "properties": .object(props),
      "required": .array(schema.required.map { .string($0) })
    ])
  }
}
```

---

## 11) Permission system

### `PermissionDelegate.swift`

```swift
import Foundation

/// Permission decision.
public enum PermissionAction: Sendable {
  case allow
  case deny
  case ask
}

/// User's reply when asked for permission.
public enum PermissionReply: Sendable {
  case once       // Allow for this session only
  case always     // Persist as permanent rule
  case reject     // Halt execution
  case corrected(String) // Reject with feedback message for the LLM
}

/// Errors thrown by the permission system.
public enum PermissionError: Error, Sendable {
  case denied(tool: String, path: String?)
  case rejected(tool: String, path: String?)
  case corrected(tool: String, feedback: String)
}

/// Protocol for permission checking. Implement this to wire up your UI.
/// Mirrors OpenCode's PermissionNext.ask() pattern.
public protocol PermissionDelegate: Sendable {
  /// Check if a tool execution is allowed.
  /// For `ask` actions, this should pause and prompt the user.
  func check(tool: String, path: String?) async throws -> PermissionReply
}

/// Simple rule-based implementation.
public struct RuleBasedPermissions: PermissionDelegate, Sendable {
  public struct Rule: Sendable {
    public let toolPattern: String  // Wildcard pattern, e.g., "edit", "bash", "*"
    public let pathPattern: String? // Optional path wildcard, e.g., "/tmp/*"
    public let action: PermissionAction

    public init(toolPattern: String, pathPattern: String? = nil, action: PermissionAction) {
      self.toolPattern = toolPattern
      self.pathPattern = pathPattern
      self.action = action
    }
  }

  private let rules: [Rule]
  private let fallbackHandler: @Sendable (String, String?) async -> PermissionReply

  public init(rules: [Rule], fallbackHandler: @escaping @Sendable (String, String?) async -> PermissionReply) {
    self.rules = rules
    self.fallbackHandler = fallbackHandler
  }

  public func check(tool: String, path: String?) async throws -> PermissionReply {
    // Edit tools all map to "edit" permission (mirrors OpenCode)
    let permKey = ["edit", "write", "patch", "multiedit"].contains(tool) ? "edit" : tool

    for rule in rules {
      guard matches(pattern: rule.toolPattern, value: permKey) else { continue }
      if let pathPattern = rule.pathPattern, let path {
        guard matches(pattern: pathPattern, value: path) else { continue }
      }
      switch rule.action {
      case .allow: return .once
      case .deny: throw PermissionError.denied(tool: tool, path: path)
      case .ask: return await fallbackHandler(tool, path)
      }
    }
    // No rule matched → ask user
    return await fallbackHandler(tool, path)
  }

  private func matches(pattern: String, value: String) -> Bool {
    if pattern == "*" { return true }
    if pattern == value { return true }
    // Simple suffix wildcard: "edit/*" matches "edit/foo"
    if pattern.hasSuffix("*") {
      let prefix = String(pattern.dropLast())
      return value.hasPrefix(prefix)
    }
    return false
  }
}
```

---

## 12) Message and session model

### `MessagePart.swift`

```swift
import Foundation

/// Typed message part — mirrors OpenCode's v2 part model.
/// A message is composed of ordered parts.
public enum MessagePart: Codable, Sendable {
  case text(String)
  case reasoning(String)
  case toolCall(ToolCallPart)
  case toolResult(ToolResultPart)
  case stepStart(StepMark)
  case stepEnd(StepMark)

  public struct ToolCallPart: Codable, Sendable {
    public let toolCallID: String
    public let toolID: String
    public let arguments: String // JSON string
    public init(toolCallID: String, toolID: String, arguments: String) {
      self.toolCallID = toolCallID
      self.toolID = toolID
      self.arguments = arguments
    }
  }

  public struct ToolResultPart: Codable, Sendable {
    public let toolCallID: String
    public let toolID: String
    public let output: String
    public let isError: Bool
    public init(toolCallID: String, toolID: String, output: String, isError: Bool = false) {
      self.toolCallID = toolCallID
      self.toolID = toolID
      self.output = output
      self.isError = isError
    }
  }

  public struct StepMark: Codable, Sendable {
    public let stepIndex: Int
    public let timestamp: Date
    public init(stepIndex: Int, timestamp: Date = Date()) {
      self.stepIndex = stepIndex
      self.timestamp = timestamp
    }
  }
}
```

### `SessionMessage.swift`

```swift
import Foundation

/// A single message in the conversation.
public struct SessionMessage: Codable, Sendable, Identifiable {
  public let id: String
  public let sessionID: String
  public let role: Role
  public var parts: [MessagePart]
  public let createdAt: Date
  public var tokenCount: Int?

  public enum Role: String, Codable, Sendable {
    case user
    case assistant
    case system
  }

  public init(id: String = UUID().uuidString, sessionID: String, role: Role, parts: [MessagePart], createdAt: Date = Date()) {
    self.id = id
    self.sessionID = sessionID
    self.role = role
    self.parts = parts
    self.createdAt = createdAt
  }
}

/// Session metadata.
public struct Session: Codable, Sendable, Identifiable {
  public let id: String
  public let projectID: String?
  public var title: String?
  public var messages: [SessionMessage]
  public var totalTokens: Int
  public let createdAt: Date
  public var updatedAt: Date

  public init(id: String = UUID().uuidString, projectID: String? = nil) {
    self.id = id
    self.projectID = projectID
    self.title = nil
    self.messages = []
    self.totalTokens = 0
    self.createdAt = Date()
    self.updatedAt = Date()
  }
}
```

---

## 13) Streaming processor

### `StreamProcessor.swift`

```swift
import Foundation

/// Events emitted during streaming — for driving UI updates.
/// Mirrors OpenCode's processor.ts event types.
public enum StreamEvent: Sendable {
  case textDelta(String)
  case reasoningDelta(String)
  case toolCallStart(id: String, toolID: String)
  case toolCallArgumentsDelta(id: String, delta: String)
  case toolCallComplete(id: String, toolID: String, arguments: String)
  case toolResult(id: String, toolID: String, output: String, isError: Bool)
  case stepStart(index: Int)
  case stepEnd(index: Int)
  case finished(usage: TokenUsage?)
  case error(Error)
}

public struct TokenUsage: Sendable {
  public let inputTokens: Int
  public let outputTokens: Int
  public let reasoningTokens: Int

  public init(inputTokens: Int, outputTokens: Int, reasoningTokens: Int = 0) {
    self.inputTokens = inputTokens
    self.outputTokens = outputTokens
    self.reasoningTokens = reasoningTokens
  }
}

/// Callback type for stream events.
public typealias StreamHandler = @Sendable (StreamEvent) -> Void
```

---

## 14) Agent definition and modes

### `AgentDefinition.swift`

```swift
import Foundation

/// Agent operating mode.
public enum AgentMode: String, Codable, Sendable {
  case primary    // Full tool access, drives main conversation
  case readOnly   // Only read tools (grep, glob, read, bash)
  case subagent   // Spawned by TaskTool, returns result to parent
}

/// Agent definition — mirrors OpenCode's Agent.Info.
public struct AgentDefinition: Sendable {
  public let name: String
  public let description: String?
  public let mode: AgentMode
  public let isHidden: Bool
  public let systemPrompt: String?
  public let temperature: Double?
  public let maxSteps: Int // Max tool-execution rounds before forced stop
  public let model: (providerID: ProviderID, modelID: String)?
  public let variant: ReasoningVariant?

  public init(
    name: String,
    description: String? = nil,
    mode: AgentMode = .primary,
    isHidden: Bool = false,
    systemPrompt: String? = nil,
    temperature: Double? = nil,
    maxSteps: Int = 50,
    model: (providerID: ProviderID, modelID: String)? = nil,
    variant: ReasoningVariant? = nil
  ) {
    self.name = name
    self.description = description
    self.mode = mode
    self.isHidden = isHidden
    self.systemPrompt = systemPrompt
    self.temperature = temperature
    self.maxSteps = maxSteps
    self.model = model
    self.variant = variant
  }

  /// Default agents matching OpenCode's built-in set.
  public static let build = AgentDefinition(name: "build", description: "Default agent with full tool access", mode: .primary, maxSteps: 100)
  public static let plan = AgentDefinition(name: "plan", description: "Read-only planning mode", mode: .readOnly, maxSteps: 50)
  public static let explore = AgentDefinition(name: "explore", description: "Fast codebase exploration", mode: .readOnly, maxSteps: 30)
  public static let general = AgentDefinition(name: "general", description: "Multi-step task executor", mode: .subagent, maxSteps: 50)
  public static let compaction = AgentDefinition(name: "compaction", description: "Session summarization", mode: .primary, isHidden: true, maxSteps: 1)
}
```

---

## 15) The agent loop (core execution engine)

This is the most critical piece — it drives the LLM → tool → LLM cycle that makes an agent actually work.

### `AgentLoop.swift`

```swift
import Foundation

/// Doom-loop tracking: detects repeated identical tool calls.
private struct ToolCallSignature: Hashable {
  let toolID: String
  let arguments: String
}

/// The core agent execution loop.
/// Mirrors OpenCode's prompt.ts + processor.ts interaction model.
public final class AgentLoop {
  private let runtime: AgentRuntime
  private let registry: ToolRegistry
  private let agent: AgentDefinition
  private let doomLoopThreshold = 3

  public init(runtime: AgentRuntime, registry: ToolRegistry, agent: AgentDefinition) {
    self.runtime = runtime
    self.registry = registry
    self.agent = agent
  }

  /// Execute the agent loop for a session.
  ///
  /// Flow:
  /// 1. Send messages + tools to LLM
  /// 2. Parse response for text, reasoning, tool calls
  /// 3. Execute tool calls (with permission checks)
  /// 4. Append tool results to messages
  /// 5. If tool calls were made → repeat from step 1
  /// 6. If text-only response → return
  ///
  /// - Parameters:
  ///   - session: The session with message history
  ///   - input: The initial RuntimeInput (model, variant, options)
  ///   - context: Tool execution context
  ///   - onEvent: Stream event handler for UI updates
  /// - Returns: The assistant's final text response
  public func run(
    session: inout Session,
    input: RuntimeInput,
    context: ToolContext,
    onEvent: StreamHandler? = nil
  ) async throws -> String {
    var stepIndex = 0
    var finalText = ""
    var toolCallHistory: [ToolCallSignature: Int] = [:]

    let tools = registry.tools(for: agent.mode)
    let toolDefs = registry.toolDefinitions(for: agent.mode)

    while stepIndex < agent.maxSteps {
      onEvent?(.stepStart(index: stepIndex))

      // Build messages for LLM (session history → API format)
      let apiMessages = buildAPIMessages(session: session)

      // Call LLM with tools
      var runtimeInput = input
      runtimeInput = RuntimeInput(
        sessionID: session.id,
        model: input.model,
        messages: apiMessages,
        selectedVariant: input.selectedVariant,
        userOptions: input.userOptions
      )

      let (data, response) = try await runtime.run(runtimeInput)
      // TODO: In production, use streaming (SSE) instead of blocking request.
      // Parse the response for text, reasoning, and tool calls.

      let parsed = try parseResponse(data: data)

      // Emit text deltas
      if !parsed.text.isEmpty {
        onEvent?(.textDelta(parsed.text))
        finalText = parsed.text
      }

      // Emit reasoning
      if let reasoning = parsed.reasoning {
        onEvent?(.reasoningDelta(reasoning))
      }

      // If no tool calls → done
      if parsed.toolCalls.isEmpty {
        onEvent?(.stepEnd(index: stepIndex))
        break
      }

      // Process tool calls
      var assistantParts: [MessagePart] = []
      if !parsed.text.isEmpty { assistantParts.append(.text(parsed.text)) }
      if let r = parsed.reasoning { assistantParts.append(.reasoning(r)) }

      var toolResultParts: [MessagePart] = []

      for call in parsed.toolCalls {
        let sig = ToolCallSignature(toolID: call.toolID, arguments: call.arguments)
        toolCallHistory[sig, default: 0] += 1

        // Doom-loop detection (mirrors OpenCode processor.ts)
        if toolCallHistory[sig]! >= doomLoopThreshold {
          let reply = await context.permissions.check(tool: "__doom_loop__", path: nil)
          // If user doesn't explicitly allow, stop
          if case .reject = reply {
            throw AgentLoopError.doomLoopDetected(toolID: call.toolID)
          }
          if case .corrected(let feedback) = reply {
            // Feed correction back as tool error
            toolResultParts.append(.toolResult(.init(
              toolCallID: call.id, toolID: call.toolID,
              output: "User feedback: \(feedback)", isError: true
            )))
            continue
          }
        }

        assistantParts.append(.toolCall(.init(
          toolCallID: call.id, toolID: call.toolID, arguments: call.arguments
        )))
        onEvent?(.toolCallComplete(id: call.id, toolID: call.toolID, arguments: call.arguments))

        // Permission check
        let toolPath = extractPath(from: call.arguments)
        do {
          let reply = try await context.permissions.check(tool: call.toolID, path: toolPath)
          if case .reject = reply {
            throw PermissionError.rejected(tool: call.toolID, path: toolPath)
          }
          if case .corrected(let feedback) = reply {
            throw PermissionError.corrected(tool: call.toolID, feedback: feedback)
          }
        } catch let error as PermissionError {
          let errorOutput: String
          switch error {
          case .denied(let tool, _): errorOutput = "Permission denied for tool: \(tool)"
          case .rejected(let tool, _): errorOutput = "User rejected tool: \(tool)"
          case .corrected(_, let feedback): errorOutput = "User correction: \(feedback)"
          }
          toolResultParts.append(.toolResult(.init(
            toolCallID: call.id, toolID: call.toolID, output: errorOutput, isError: true
          )))
          onEvent?(.toolResult(id: call.id, toolID: call.toolID, output: errorOutput, isError: true))
          continue
        }

        // Execute tool
        guard let tool = registry.tool(byID: call.toolID) else {
          let errMsg = "Unknown tool: \(call.toolID)"
          toolResultParts.append(.toolResult(.init(
            toolCallID: call.id, toolID: call.toolID, output: errMsg, isError: true
          )))
          onEvent?(.toolResult(id: call.id, toolID: call.toolID, output: errMsg, isError: true))
          continue
        }

        do {
          let args = try decodeArguments(call.arguments)
          let result = try await tool.execute(arguments: args, context: context)
          toolResultParts.append(.toolResult(.init(
            toolCallID: call.id, toolID: call.toolID, output: result.output, isError: result.isError
          )))
          onEvent?(.toolResult(id: call.id, toolID: call.toolID, output: result.output, isError: result.isError))
        } catch {
          let errMsg = "Tool execution error: \(error.localizedDescription)"
          toolResultParts.append(.toolResult(.init(
            toolCallID: call.id, toolID: call.toolID, output: errMsg, isError: true
          )))
          onEvent?(.toolResult(id: call.id, toolID: call.toolID, output: errMsg, isError: true))
        }
      }

      // Append assistant message with tool calls
      let assistantMsg = SessionMessage(sessionID: session.id, role: .assistant, parts: assistantParts)
      session.messages.append(assistantMsg)

      // Append tool results as user message (for next LLM turn)
      if !toolResultParts.isEmpty {
        let toolMsg = SessionMessage(sessionID: session.id, role: .user, parts: toolResultParts)
        session.messages.append(toolMsg)
      }

      onEvent?(.stepEnd(index: stepIndex))
      stepIndex += 1
    }

    if stepIndex >= agent.maxSteps {
      onEvent?(.error(AgentLoopError.maxStepsExceeded))
    }

    onEvent?(.finished(usage: nil))
    return finalText
  }

  // MARK: - Helpers

  private struct ParsedResponse {
    let text: String
    let reasoning: String?
    let toolCalls: [ParsedToolCall]
  }

  private struct ParsedToolCall {
    let id: String
    let toolID: String
    let arguments: String // JSON string
  }

  private func buildAPIMessages(session: Session) -> [[String: JSONValue]] {
    // Convert session messages to API format.
    // This is provider-specific — adapt for OpenAI/Anthropic message formats.
    session.messages.compactMap { msg in
      var content: [JSONValue] = []
      for part in msg.parts {
        switch part {
        case .text(let t):
          content.append(.object(["type": .string("text"), "text": .string(t)]))
        case .toolCall(let tc):
          content.append(.object([
            "type": .string("tool_use"),
            "id": .string(tc.toolCallID),
            "name": .string(tc.toolID),
            "input": .string(tc.arguments)
          ]))
        case .toolResult(let tr):
          content.append(.object([
            "type": .string("tool_result"),
            "tool_use_id": .string(tr.toolCallID),
            "content": .string(tr.output),
            "is_error": .bool(tr.isError)
          ]))
        case .reasoning, .stepStart, .stepEnd:
          break // Not sent back to LLM
        }
      }
      guard !content.isEmpty else { return nil }
      return [
        "role": .string(msg.role.rawValue),
        "content": .array(content)
      ]
    }
  }

  private func parseResponse(data: Data) throws -> ParsedResponse {
    // Parse LLM response JSON. Adapt per provider.
    // This is a simplified version — production code should handle SSE streaming.
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw AgentLoopError.invalidResponse
    }

    var text = ""
    var reasoning: String?
    var toolCalls: [ParsedToolCall] = []

    // OpenAI-style response parsing
    if let choices = json["choices"] as? [[String: Any]],
       let message = choices.first?["message"] as? [String: Any] {
      text = message["content"] as? String ?? ""

      if let calls = message["tool_calls"] as? [[String: Any]] {
        for call in calls {
          guard let id = call["id"] as? String,
                let function = call["function"] as? [String: Any],
                let name = function["name"] as? String,
                let args = function["arguments"] as? String else { continue }
          toolCalls.append(ParsedToolCall(id: id, toolID: name, arguments: args))
        }
      }
    }

    // Anthropic-style: check for thinking blocks
    if let content = json["content"] as? [[String: Any]] {
      for block in content {
        let type = block["type"] as? String
        if type == "text" { text = block["text"] as? String ?? "" }
        if type == "thinking" { reasoning = block["thinking"] as? String }
        if type == "tool_use" {
          let id = block["id"] as? String ?? UUID().uuidString
          let name = block["name"] as? String ?? ""
          let input = block["input"] as? [String: Any] ?? [:]
          let argsData = try JSONSerialization.data(withJSONObject: input)
          toolCalls.append(ParsedToolCall(id: id, toolID: name, arguments: String(data: argsData, encoding: .utf8) ?? "{}"))
        }
      }
    }

    return ParsedResponse(text: text, reasoning: reasoning, toolCalls: toolCalls)
  }

  private func decodeArguments(_ json: String) throws -> [String: JSONValue] {
    guard let data = json.data(using: .utf8) else { return [:] }
    return try JSONDecoder().decode([String: JSONValue].self, from: data)
  }

  private func extractPath(from argumentsJSON: String) -> String? {
    guard let data = argumentsJSON.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
    // Common path keys across tools
    return obj["file_path"] as? String ?? obj["path"] as? String ?? obj["command"] as? String
  }
}

public enum AgentLoopError: Error, Sendable {
  case maxStepsExceeded
  case doomLoopDetected(toolID: String)
  case invalidResponse
}
```

---

## 16) Context compaction

### `ContextCompactor.swift`

```swift
import Foundation

/// Manages context window overflow by pruning old tool outputs and summarizing.
/// Mirrors OpenCode's compaction.ts behavior.
public struct ContextCompactor: Sendable {
  /// Max input tokens before compaction triggers.
  public let tokenLimit: Int
  /// Reserved buffer (default 20k tokens).
  public let reservedTokens: Int
  /// Minimum tool output tokens to keep (default 40k).
  public let minToolTokensToKeep: Int

  public init(tokenLimit: Int = 128_000, reservedTokens: Int = 20_000, minToolTokensToKeep: Int = 40_000) {
    self.tokenLimit = tokenLimit
    self.reservedTokens = reservedTokens
    self.minToolTokensToKeep = minToolTokensToKeep
  }

  /// Check if compaction is needed.
  public func needsCompaction(session: Session) -> Bool {
    session.totalTokens > (tokenLimit - reservedTokens)
  }

  /// Prune old tool outputs from messages.
  /// Keeps the most recent tool outputs (within minToolTokensToKeep budget).
  /// Returns pruned session — the caller should then run a summarization agent.
  public func prune(session: inout Session, estimateTokens: (String) -> Int) {
    // Work backwards from most recent, keeping tool outputs until budget exhausted
    var toolTokenBudget = minToolTokensToKeep
    var i = session.messages.count - 1

    while i >= 0 {
      let msg = session.messages[i]
      for (partIndex, part) in msg.parts.enumerated().reversed() {
        if case .toolResult(let result) = part {
          let tokens = estimateTokens(result.output)
          if toolTokenBudget > 0 {
            toolTokenBudget -= tokens
          } else {
            // Replace with truncated marker
            session.messages[i].parts[partIndex] = .toolResult(.init(
              toolCallID: result.toolCallID,
              toolID: result.toolID,
              output: "[Output pruned for context management]",
              isError: false
            ))
          }
        }
      }
      i -= 1
    }
  }
}
```

---

## 17) Example tool implementations

### `ReadFileTool.swift`

```swift
import Foundation

public struct ReadFileTool: AgentTool {
  public let id = "read"
  public let description = "Read the contents of a file at the given path. Returns the file content with line numbers."

  public let parameters = ToolParameterSchema(
    type: "object",
    properties: [
      "file_path": .init(type: "string", description: "Absolute path to the file to read", enumValues: nil),
      "offset": .init(type: "integer", description: "Line number to start reading from (optional)", enumValues: nil),
      "limit": .init(type: "integer", description: "Number of lines to read (optional)", enumValues: nil)
    ],
    required: ["file_path"]
  )

  public init() {}

  public func execute(arguments: [String: JSONValue], context: ToolContext) async throws -> ToolResult {
    guard case .string(let path) = arguments["file_path"] else {
      return ToolResult(output: "Error: file_path is required", isError: true)
    }

    let url = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: url.path) else {
      return ToolResult(output: "Error: File not found: \(path)", isError: true)
    }

    let content = try String(contentsOf: url, encoding: .utf8)
    let lines = content.components(separatedBy: .newlines)

    var offset = 0
    if case .number(let n) = arguments["offset"] { offset = max(0, Int(n) - 1) }
    var limit = lines.count
    if case .number(let n) = arguments["limit"] { limit = Int(n) }

    let slice = lines[min(offset, lines.count)..<min(offset + limit, lines.count)]
    let numbered = slice.enumerated().map { "\(offset + $0.offset + 1)\t\($0.element)" }.joined(separator: "\n")

    return ToolResult(output: numbered)
  }
}
```

### `BashTool.swift` (simplified)

```swift
import Foundation

public struct BashTool: AgentTool {
  public let id = "bash"
  public let description = "Execute a bash command and return stdout/stderr."

  public let parameters = ToolParameterSchema(
    type: "object",
    properties: [
      "command": .init(type: "string", description: "The bash command to execute", enumValues: nil),
      "timeout": .init(type: "integer", description: "Timeout in milliseconds (default 120000)", enumValues: nil)
    ],
    required: ["command"]
  )

  private let defaultTimeout: TimeInterval = 120

  public init() {}

  public func execute(arguments: [String: JSONValue], context: ToolContext) async throws -> ToolResult {
    guard case .string(let command) = arguments["command"] else {
      return ToolResult(output: "Error: command is required", isError: true)
    }

    var timeout = defaultTimeout
    if case .number(let ms) = arguments["timeout"] { timeout = ms / 1000 }

    let process = Process()
    let stdout = Pipe()
    let stderr = Pipe()

    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = ["-c", command]
    process.currentDirectoryURL = context.workingDirectory
    process.standardOutput = stdout
    process.standardError = stderr

    try process.run()

    // Timeout handling
    let deadline = DispatchTime.now() + timeout
    let group = DispatchGroup()
    group.enter()
    DispatchQueue.global().async {
      process.waitUntilExit()
      group.leave()
    }

    if group.wait(timeout: deadline) == .timedOut {
      process.terminate()
      return ToolResult(output: "Error: Command timed out after \(Int(timeout))s", isError: true)
    }

    let outData = stdout.fileHandleForReading.readDataToEndOfFile()
    let errData = stderr.fileHandleForReading.readDataToEndOfFile()
    let outStr = String(data: outData, encoding: .utf8) ?? ""
    let errStr = String(data: errData, encoding: .utf8) ?? ""

    let exitCode = process.terminationStatus
    let output = exitCode == 0 ? outStr : "Exit code: \(exitCode)\nstdout:\n\(outStr)\nstderr:\n\(errStr)"

    return ToolResult(output: output, isError: exitCode != 0)
  }
}
```

---

## 18) Updated implementation checklist

1. Add core types and protocols (sections 1-2: done).
2. Implement Keychain token store (section 2: done).
3. Implement Codex OAuth + adapter (sections 3: done).
4. Implement Claude adapter (section 4: done).
5. Implement variant mapper (section 5: done).
6. Wire runtime merge/build/prepare/execute (section 6: done).
7. **Add tool protocol and registry** (section 10).
8. **Add permission system** (section 11).
9. **Add message/session model** (section 12).
10. **Add stream event types** (section 13).
11. **Add agent definitions** (section 14).
12. **Implement the agent loop** (section 15) — this is the central piece.
13. **Add context compaction** (section 16).
14. **Implement core tools**: read, bash, edit, write, glob, grep (section 17).
15. Add tests for:
    - Token refresh path
    - Codex endpoint rewrite
    - Variant payload mapping
    - Z.AI default thinking payload
    - **Tool execution and result formatting**
    - **Agent loop: tool call → execute → feed back cycle**
    - **Doom-loop detection (3+ identical calls)**
    - **Permission allow/deny/ask flow**
    - **Context compaction pruning**
    - **Message serialization round-trip**

## 19) Architecture summary

```
┌─────────────────────────────────────────────────┐
│                  Your macOS App                   │
│                                                   │
│  ┌─────────────┐  ┌──────────────────────────┐   │
│  │   UI Layer   │  │     Session Manager       │   │
│  │  (SwiftUI)   │◄─┤  Messages, Parts, State   │   │
│  └──────┬───────┘  └────────────┬─────────────┘   │
│         │                       │                   │
│         ▼                       ▼                   │
│  ┌──────────────────────────────────────────┐     │
│  │              Agent Loop                    │     │
│  │  LLM call → parse → tool exec → repeat    │     │
│  │                                            │     │
│  │  ┌────────────┐  ┌─────────────────────┐  │     │
│  │  │  Permission │  │  Doom-loop Detector  │  │     │
│  │  │  Delegate   │  │  (3+ same calls)     │  │     │
│  │  └────────────┘  └─────────────────────┘  │     │
│  └──────────────┬───────────────┬────────────┘     │
│                 │               │                   │
│       ┌─────────▼──┐    ┌──────▼──────┐            │
│       │ AgentRuntime│    │ ToolRegistry │            │
│       │ (transport) │    │ (tools)      │            │
│       └──────┬──────┘    └──────┬──────┘            │
│              │                  │                    │
│    ┌─────────▼──────────┐  ┌───▼──────────────┐    │
│    │  Provider Adapters  │  │  Built-in Tools   │    │
│    │  Codex, Claude,     │  │  bash, read, edit │    │
│    │  Copilot, Z.AI      │  │  grep, glob, ...  │    │
│    └─────────┬──────────┘  └──────────────────┘    │
│              │                                      │
│    ┌─────────▼──────────┐                           │
│    │  Keychain + OAuth   │                           │
│    │  Token Store        │                           │
│    └────────────────────┘                           │
│                                                     │
│    ┌───────────────────────────────────────────┐    │
│    │  Context Compactor                         │    │
│    │  Prune old tool outputs → Summarize        │    │
│    └───────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────┘
```

The transport layer (sections 1-9) handles *how to talk to LLM providers*.
The agent layer (sections 10-18) handles *what makes it an agent* — the tool execution loop, permissions, context management, and session persistence.

If you want, next I can generate these as actual `.swift` files with compile-ready imports and a minimal `Package.swift`.
