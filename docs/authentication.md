# Authentication

The Native Agent System supports two authentication methods: **API Keys** and **OAuth**. All credentials are stored securely in macOS Keychain.

## Two Auth Methods

### 1. API Key (all providers)

The simplest path. Enter a key in Settings, it's saved to macOS Keychain via `KeychainTokenStore`. Each request injects the key as a header:

| Provider | Header | Additional Headers |
|----------|--------|--------------------|
| Anthropic | `x-api-key: <key>` | `anthropic-version: 2023-06-01`, `anthropic-beta` (when thinking enabled) |
| OpenAI/Codex | `Authorization: Bearer <key>` | — |
| Z.AI / Zhipu | `Authorization: Bearer <key>` | — |

All models are available in API key mode. In Codex OAuth mode, models are restricted to the Codex-compatible set (`gpt-5.1-codex`, `gpt-5.1-codex-mini`, `gpt-5.1-codex-max`, `gpt-5.2`, `gpt-5.2-codex`, `gpt-5.3-codex`).

> **Note:** Both `.zai` and `.zhipuAI` provider IDs are supported and share the same `ZAIAdapter`.

### 2. OAuth (Claude, Codex)

Authorization code flow with provider-specific PKCE support:

1. **`OAuthClient.startAuthorization()`** — generates an authorize URL with state parameter (+ PKCE challenge for Codex)
2. **`OAuthCallbackServer`** — spins up a local HTTP server on `localhost:19876` to receive the redirect
3. User authorizes in browser → redirect hits callback → server extracts the `?code=` parameter
4. **`OAuthClient.exchange(code:)`** — exchanges code for access/refresh tokens
5. Token stored as `AuthMode.oauth(OAuthToken)` in Keychain

**Provider-specific OAuth details:**

- **Codex** — fully implemented. Uses SHA-256 PKCE (`code_challenge_method: S256`), extracts `accountID` from JWT payload (needed for `ChatGPT-Account-Id` header), rewrites API URL to `chatgpt.com/backend-api/codex/responses` in OAuth mode. Token exchange and refresh are implemented in `CodexOAuthClient`.
- **Claude** — skeleton only. `startAuthorization()` generates an authorize URL with scopes (`org:create_api_key user:profile user:inference`) but does not use PKCE. `exchange()` and `refresh()` throw `notImplemented` errors. Ready to wire when Anthropic's OAuth endpoints are finalized.
- **Z.AI** — no OAuth client; API key only. OAuth tokens are accepted as simple Bearer tokens without refresh.

**Current limitations:**
- OAuth login buttons are not yet wired in the Settings UI (`ProviderAuthRow` supports `onOAuthLogin` but `NativeAgentSettingsTab` doesn't pass it). API key entry is the only user-facing auth path for now.
- Token refresh is implemented in `CodexOAuthClient.refresh()` but not yet called by the adapters. Both `ClaudeAdapter` and `CodexAdapter` return stale tokens with TODO markers for refresh wiring.

## Credential Storage

All credentials go through the `TokenStore` protocol, implemented by `KeychainTokenStore`:

- **Service:** `com.slothyterminal.agent.auth`
- **One item per provider** keyed by `ProviderID.rawValue`
- **Accessibility:** `kSecAttrAccessibleAfterFirstUnlock`
- Credentials are JSON-encoded `AuthMode` (either `.apiKey(String)` or `.oauth(OAuthToken)`)

The `OAuthToken` struct carries: `accessToken`, `refreshToken`, `expiresAt`, and optional `accountID`.

## Settings UI Flow

In `NativeAgentSettingsTab`:

1. User enters API key in a `SecureField` (keys are never displayed back in plaintext)
2. "Save Credentials" saves to Keychain as `.apiKey()`
3. Status badge updates: green (connected), gray (no credentials), red (expired/error)

## Where Auth Plugs Into Requests

On every LLM call, the adapter's `prepare(request:context:)` method:

1. Loads `AuthMode` from `TokenStore`
2. If OAuth — checks expiry (refresh not yet wired; see limitations above)
3. Injects auth headers + provider-specific headers:
   - Anthropic: `x-api-key` or `Authorization: Bearer`, plus `anthropic-version` and `anthropic-beta`
   - Codex: `Authorization: Bearer`, plus `ChatGPT-Account-Id` for OAuth; rewrites URL to `chatgpt.com/backend-api/codex/responses`
   - Z.AI: `Authorization: Bearer`
4. Returns a `PreparedRequest` ready for `URLSessionHTTPTransport`
