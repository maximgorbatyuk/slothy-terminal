# Authentication

The Native Agent System supports two authentication methods: **API Keys** and **OAuth**. All credentials are stored securely in macOS Keychain.

## Two Auth Methods

### 1. API Key (all providers)

The simplest path. Enter a key in Settings, it's saved to macOS Keychain via `KeychainTokenStore`. Each request injects the key as a header:

| Provider | Header |
|----------|--------|
| Anthropic | `x-api-key: <key>` |
| OpenAI/Codex | `Authorization: Bearer <key>` |
| Z.AI / Zhipu | `Authorization: Bearer <key>` |

All models are available in API key mode (except Codex, which restricts to `gpt-5.x-codex*` models in OAuth mode only).

### 2. OAuth (Claude, Codex)

Full PKCE authorization code flow:

1. **`OAuthClient.startAuthorization()`** — generates an authorize URL with PKCE challenge + state parameter
2. **`OAuthCallbackServer`** — spins up a local HTTP server on `localhost:19876` to receive the redirect
3. User authorizes in browser → redirect hits callback → server extracts the `?code=` parameter
4. **`OAuthClient.exchange(code:)`** — exchanges code for access/refresh tokens
5. Token stored as `AuthMode.oauth(OAuthToken)` in Keychain
6. **`OAuthClient.refresh(token:)`** — called automatically when token expires (30-second skew)

**Provider-specific OAuth details:**

- **Codex** — fully implemented. Uses SHA-256 PKCE, extracts `accountID` from JWT payload (needed for `ChatGPT-Account-Id` header), rewrites API URL to `chatgpt.com/backend-api/codex/responses` in OAuth mode.
- **Claude** — skeleton in place (authorize URL, scopes defined), but `exchange()` and `refresh()` are placeholder `throws`. Ready to wire when Anthropic's OAuth endpoints are finalized.
- **Z.AI** — no OAuth client; API key only.

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
2. If OAuth — checks expiry, refreshes if within 30 seconds of expiration
3. Injects auth headers + any provider-specific headers (e.g., `anthropic-version`, `ChatGPT-Account-Id`)
4. Returns a `PreparedRequest` ready for `URLSessionHTTPTransport`
