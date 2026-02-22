# Plan: Native Multi-Provider Agent System

## Context

SlothyTerminal currently uses CLI transports (`ClaudeCLITransport`, `OpenCodeCLITransport`) that shell out to external CLI tools for chat mode. The CLI processes handle the agent loop (LLM calls, tool execution, result feeding) internally, and SlothyTerminal parses their NDJSON stdout to render the conversation.

This plan adds a **native agent system** that talks directly to LLM provider APIs (Anthropic, OpenAI/Codex, Z.AI/GLM), executes tools in-process, and manages the agent loop natively. The native system replaces CLI transports for **chat mode only**; TUI/terminal mode keeps the existing CLI approach.

**Scope:** All three providers, both API key + OAuth auth, 7 built-in tools (bash, read, write, edit, glob, grep, webfetch). Full agent loop with permission system, doom-loop detection, context compaction, and subagent support.

## Key Architecture Decision

`NativeAgentTransport` implements the existing `ChatTransport` protocol. The agent loop runs inside the transport and emits `StreamEvent` values in the same format the engine already expects. This means **ChatSessionEngine, ChatState, ChatConversation, snapshot persistence, and all chat views remain unchanged** until the final UI phases.

```
Current:  ChatState -> ChatTransport (CLI subprocess) -> CLI handles agent loop
New:      ChatState -> NativeAgentTransport -> AgentLoop -> AgentRuntime -> HTTP API
                                                  |
                                            ToolRegistry -> Tool execution in-process
```

The NativeAgentTransport maps agent loop events to existing `StreamEvent`:

| Agent loop output | StreamEvent emitted |
|---|---|
| Text delta | `contentBlockStart("text")` / `contentBlockDelta("text_delta")` / `contentBlockStop` |
| Thinking delta | `contentBlockStart("thinking")` / `contentBlockDelta("thinking_delta")` / `contentBlockStop` |
| Tool call | `contentBlockStart("tool_use", id, name)` / `contentBlockDelta("input_json_delta")` / `contentBlockStop` |
| Tool result | `userToolResult(toolUseId, output, isError)` |
| Segment complete (before next LLM call) | `messageStop` |
| Final response (no more tool calls) | `result(text, inputTokens, outputTokens)` |

This preserves the engine's multi-segment tool use handling exactly as-is.

## File Structure

All new code lives under `SlothyTerminal/Agent/`:

```
Agent/
  Core/Models/        ProviderID, ModelDescriptor, AuthState, ReasoningVariant, JSONValue, AgentMode
  Core/Protocols/     TokenStore, OAuthClient, ProviderAdapter, VariantMapper, AgentToolProtocol, PermissionDelegate
  Runtime/            AgentRuntime, AgentLoop, RequestBuilder, ProviderStreamParser, ContextCompactor, SystemPromptBuilder, TokenEstimator
  Adapters/Claude/    ClaudeAdapter, ClaudeOAuthClient
  Adapters/Codex/     CodexAdapter, CodexOAuthClient
  Adapters/ZAI/       ZAIAdapter
  Adapters/Variants/  DefaultVariantMapper
  Tools/              ToolRegistry, BashTool, ReadFileTool, WriteFileTool, EditFileTool, GlobTool, GrepTool, WebFetchTool, TaskTool
  Storage/            KeychainTokenStore
  Permission/         RuleBasedPermissions
  Transport/          SSEParser, URLSessionHTTPTransport, NativeAgentTransport
  Definitions/        AgentDefinition
  Auth/               OAuthCallbackServer
  AgentRuntimeFactory.swift
```

## Phase Dependencies

```
Phase 1 (Core Types)
    |
    +-- Phase 2 (Auth + Keychain) -----+
    |                                   |
    +-- Phase 3 (Provider Adapters) ----+-- Phase 5 (SSE + HTTP Transport)
    |                                   |       |
    +-- Phase 4 (Tool System) ---------+       |
                                        |       |
                               Phase 6 (Agent Loop + Runtime)
                                        |
                               Phase 7 (NativeAgentTransport)
                                        |
                               Phase 8 (ChatState Integration)
                                        |
                               Phase 9 (UI: Settings + Model Picker)
                                        |
                               Phase 10 (Compaction, Subagents, Polish)
```

Phases 2, 3, 4 can be developed in parallel after Phase 1.

---

## Phase 1: Core Models and Protocols

**Goal:** All foundational types and protocol contracts. Pure type definitions, zero implementation.

**New files (12):**

| File | Key types |
|------|-----------|
| `Agent/Core/Models/ProviderID.swift` | `enum ProviderID: String, Codable, Sendable` — openai, anthropic, zai, zhipuai |
| `Agent/Core/Models/ModelDescriptor.swift` | `struct ModelDescriptor: Codable, Sendable, Hashable` — providerID, modelID, packageID, supportsReasoning, outputLimit |
| `Agent/Core/Models/AuthState.swift` | `struct OAuthToken: Codable, Sendable`, `enum AuthMode: Codable, Sendable` — apiKey(String) / oauth(OAuthToken) |
| `Agent/Core/Models/ReasoningVariant.swift` | `enum ReasoningVariant: String, Codable, CaseIterable, Sendable` — none, minimal, low, medium, high, max, xhigh |
| `Agent/Core/Models/JSONValue.swift` | `enum JSONValue: Codable, Sendable, Equatable` — string/number/bool/object/array/null |
| `Agent/Core/Models/AgentMode.swift` | `enum AgentMode: String, Codable, Sendable` — primary, readOnly, subagent |
| `Agent/Core/Protocols/TokenStore.swift` | `protocol TokenStore: Sendable` — load/save/remove per ProviderID |
| `Agent/Core/Protocols/OAuthClient.swift` | `protocol OAuthClient: Sendable` — startAuthorization/exchange/refresh |
| `Agent/Core/Protocols/ProviderAdapter.swift` | `protocol ProviderAdapter: Sendable` + `struct RequestContext` + `struct PreparedRequest` — allowedModels, defaultOptions, variantOptions, prepare(request:context:) |
| `Agent/Core/Protocols/VariantMapper.swift` | `protocol VariantMapper: Sendable` — variants(for:), options(for:variant:), defaultThinkingOptions(for:) |
| `Agent/Core/Protocols/AgentToolProtocol.swift` | `protocol AgentTool: Sendable` + `struct ToolParameterSchema` + `struct ToolResult` + `struct ToolContext` |
| `Agent/Core/Protocols/PermissionDelegate.swift` | `protocol PermissionDelegate: Sendable` + `enum PermissionAction/Reply/Error` |

**Modify:** `Package.swift` — add 12 source paths to `SlothyTerminalLib`.

**Tests:** `JSONValueTests.swift` (Codable round-trip all cases), `ModelDescriptorTests.swift` (Codable, Hashable).

**Verify:** `swift build` + `swift test` + Xcode build pass. No existing behavior changes.

---

## Phase 2: Auth and Keychain Storage

**Goal:** Keychain-based credential persistence for API keys and OAuth tokens.

**New files (1):**

| File | Key types |
|------|-----------|
| `Agent/Storage/KeychainTokenStore.swift` | `final class KeychainTokenStore: TokenStore` — save/load/remove `AuthMode` to macOS Keychain via `Security.framework`. Service = `com.slothyterminal.agent.auth`. |

**Modify:** `Package.swift` — add 1 source path.

**Tests:** `MockTokenStore.swift` (in-memory dict), `KeychainTokenStoreTests.swift` (tests against mock — actual Keychain requires entitlements unavailable in `swift test`).

**Verify:** `swift build` + `swift test` pass.

---

## Phase 3: Provider Adapters and Variant Mapper

**Goal:** Three provider adapters + variant mapper. Each adapter handles auth headers, URL rewriting, and provider-specific options.

**New files (6):**

| File | Purpose |
|------|---------|
| `Agent/Adapters/Claude/ClaudeAdapter.swift` | `x-api-key` header, `anthropic-version`, `anthropic-beta` for thinking, OAuth bearer support |
| `Agent/Adapters/Claude/ClaudeOAuthClient.swift` | PKCE flow skeleton for Anthropic OAuth (exchange/refresh as placeholder `throws`) |
| `Agent/Adapters/Codex/CodexAdapter.swift` | OAuth bearer + `ChatGPT-Account-Id` header, URL rewrite to `chatgpt.com/backend-api/codex/responses`, model filtering for OAuth mode |
| `Agent/Adapters/Codex/CodexOAuthClient.swift` | PKCE flow, JWT account ID extraction, token refresh |
| `Agent/Adapters/ZAI/ZAIAdapter.swift` | API key header, default thinking enabled (`thinking.type: enabled, clear_thinking: false`) |
| `Agent/Adapters/Variants/DefaultVariantMapper.swift` | OpenAI → `reasoningEffort`, Anthropic → thinking `budgetTokens`, Z.AI → no manual variants |

**Modify:** `Package.swift` — add 6 source paths.

**Tests:** `ClaudeAdapterTests.swift` (header injection, OAuth bearer), `CodexAdapterTests.swift` (URL rewrite, account header, model filtering), `ZAIAdapterTests.swift` (default thinking options), `DefaultVariantMapperTests.swift` (variant lists per provider, option payloads). All use `MockTokenStore`, no network calls.

**Verify:** `swift build` + `swift test` pass with 10+ new tests.

---

## Phase 4: Tool System

**Goal:** 7 built-in tools + tool registry. Each tool is a standalone `AgentTool` struct.

**New files (8):**

| File | Purpose |
|------|---------|
| `Agent/Tools/ToolRegistry.swift` | Register tools, filter by `AgentMode` (readOnly gets bash/read/glob/grep only), lookup by ID, generate tool definition JSON for API payloads |
| `Agent/Tools/BashTool.swift` | `Process` execution, configurable timeout, stdout+stderr capture, working directory from `ToolContext` |
| `Agent/Tools/ReadFileTool.swift` | Read file with optional offset/limit, line-numbered output |
| `Agent/Tools/WriteFileTool.swift` | Write content to file, create intermediate directories |
| `Agent/Tools/EditFileTool.swift` | String-replacement editing (old_string → new_string), uniqueness check |
| `Agent/Tools/GlobTool.swift` | File pattern matching via `FileManager` enumeration |
| `Agent/Tools/GrepTool.swift` | Content search via `Process` calling `grep -rn` or ripgrep |
| `Agent/Tools/WebFetchTool.swift` | `URLSession` fetch, HTML-to-text conversion, content truncation |

**Modify:** `Package.swift` — add 8 source paths.

**Tests:** `ToolRegistryTests.swift` (registration, mode filtering, lookup), `ReadFileToolTests.swift` (read, offset/limit, missing file), `EditFileToolTests.swift` (replacement, missing old_string), `BashToolTests.swift` (simple command, timeout, exit code). Tests use temp directories.

**Verify:** `swift build` + `swift test` pass.

---

## Phase 5: SSE Streaming and HTTP Transport

**Goal:** URLSession-based HTTP layer + Server-Sent Events parser for streaming LLM responses. Request builder that knows Anthropic vs OpenAI API formats.

**New files (4):**

| File | Purpose |
|------|---------|
| `Agent/Transport/SSEParser.swift` | Parses `text/event-stream` byte chunks into `(event: String?, data: String)` tuples. Handles multi-line data, empty line delimiters. |
| `Agent/Transport/URLSessionHTTPTransport.swift` | Executes `PreparedRequest` via `URLSession.bytes(for:)` for streaming. Returns `AsyncSequence` of SSE events. |
| `Agent/Runtime/RequestBuilder.swift` | Builds `PreparedRequest` from model + messages + tools + options. Branches by `ProviderID`: Anthropic Messages API vs OpenAI Chat Completions. |
| `Agent/Runtime/ProviderStreamParser.swift` | Converts SSE data strings into normalized stream events. Handles Anthropic SSE (`content_block_start/delta/stop`) and OpenAI SSE (`choices[0].delta`). |

**Modify:** `Package.swift` — add 4 source paths.

**Tests:** `SSEParserTests.swift` (multi-line data, event field, partial chunks), `RequestBuilderTests.swift` (Anthropic message format, OpenAI format, tool definitions), `ProviderStreamParserTests.swift` (Anthropic text/thinking/tool_use, OpenAI content/tool_calls).

**Verify:** `swift build` + `swift test` pass. No network calls in tests (all string/data-level).

---

## Phase 6: Agent Loop and Runtime

**Goal:** The core execution engine. Orchestrates LLM calls, stream parsing, tool execution with permission checks, result feeding, and loop control.

**New files (5):**

| File | Purpose |
|------|---------|
| `Agent/Runtime/AgentRuntime.swift` | Holds adapters dict, token store, variant mapper, HTTP transport. Option merge order: adapter defaults → mapper default thinking → variant options → caller overrides. Returns `AsyncThrowingStream` of provider stream events. |
| `Agent/Runtime/AgentLoop.swift` | Core loop: send messages to LLM → parse streaming response → execute tool calls (with permission checks) → feed results back → repeat until text-only response. Doom-loop detection: 3+ identical tool calls (same toolID + args) pauses and prompts user. |
| `Agent/Runtime/AgentLoopError.swift` | `enum AgentLoopError: Error` — maxStepsExceeded, doomLoopDetected, invalidResponse, cancelled |
| `Agent/Permission/RuleBasedPermissions.swift` | Rule-based permission checker. Edit/write/patch tools map to `"edit"` permission key. Rules evaluated top-to-bottom, first match wins. Fallback: async user prompt handler. |
| `Agent/Definitions/AgentDefinition.swift` | Agent config bundle: name, mode, systemPrompt, maxSteps, model/variant overrides. Presets: `.build` (full tools, 100 steps), `.plan` (read-only), `.explore` (read-only, 30 steps), `.general` (subagent), `.compaction` (hidden, 1 step). |

**Modify:** `Package.swift` — add 5 source paths.

**Tests:**
- `AgentLoopTests.swift` — mock runtime + mock tools: text-only response exits loop; tool call → execute → feed back cycle; doom-loop at 3 identical calls; max steps enforcement; permission denied produces error tool result
- `RuleBasedPermissionsTests.swift` — allow/deny/ask matching, wildcard patterns, edit-tool mapping
- `Mocks/MockAgentRuntime.swift`, `Mocks/MockPermissionDelegate.swift`

**Verify:** `swift build` + `swift test` pass. Agent loop fully testable with mocks (no network, no process execution).

---

## Phase 7: NativeAgentTransport

**Goal:** The integration seam. Implements `ChatTransport`, bridges agent loop to existing engine via `StreamEvent` mapping described in the architecture section above.

**New files (1):**

| File | Purpose |
|------|---------|
| `Agent/Transport/NativeAgentTransport.swift` | `class NativeAgentTransport: ChatTransport` — `start()` generates session ID, calls `onReady`. `send(message:)` kicks off agent loop in a `Task`. Loop's stream handler maps events → `StreamEvent` → `onEvent` callback. `interrupt()` cancels running task. `terminate()` cancels + cleans up. |

**Modify:** `Package.swift` — add 1 source path.

**Tests:** `NativeAgentTransportTests.swift` — start (onReady called), send (correct StreamEvent sequence emitted), interrupt (loop cancelled), terminate. Uses `MockAgentLoop`.

**Verify:** `swift build` + `swift test` pass. Transport can be plugged into ChatState without modifying the engine.

---

## Phase 8: ChatState Integration

**Goal:** Wire NativeAgentTransport into ChatState's transport selection. Add configuration and factory.

**New files (1):**

| File | Purpose |
|------|---------|
| `Agent/AgentRuntimeFactory.swift` | Assembles fully configured `AgentRuntime` from ConfigManager (API keys from Keychain, adapter selection, variant mapper). Single composition point. |

**Modify:**

| File | Change |
|------|--------|
| `Chat/State/ChatState.swift` | In transport creation: if native agent is enabled and auth is available for the provider, create `NativeAgentTransport` instead of CLI transport. Add `useNativeTransport: Bool` computed property. |
| `Models/AppConfig.swift` | Add `nativeAgentEnabled: Bool = false` feature flag, `nativeDefaultProvider: String?`, `nativeDefaultModel: String?` |
| `Package.swift` | Add 1 source path |

**Tests:** `AgentRuntimeFactoryTests.swift` — factory creates runtime with correct adapter per provider, falls back when no auth.

**Verify:** `swift build` + `swift test` + Xcode build pass. Existing `ChatSessionEngineTests` still pass (engine unchanged). Manual: set `nativeAgentEnabled = true`, provide API key, send chat message, verify native streaming end-to-end.

---

## Phase 9: UI — Settings and Model Picker

**Goal:** Settings UI for API keys, OAuth flows, and model/variant selection in chat composer.

**New files (3):**

| File | Purpose |
|------|---------|
| `Views/Settings/NativeAgentSettingsTab.swift` | Toggle native agent, per-provider API key entry (`SecureField`), OAuth login button, connection status |
| `Views/Settings/ProviderAuthRow.swift` | Reusable row: provider icon, name, auth status, API key field or OAuth button |
| `Agent/Auth/OAuthCallbackServer.swift` | Minimal local HTTP server (`NWListener` on localhost) to receive OAuth redirects. Extracts code, passes to `OAuthClient.exchange()`. |

**Modify:**

| File | Change |
|------|--------|
| `Views/SettingsView.swift` | Add "Native Agent" tab |
| `Chat/Views/ChatInputView.swift` (or equivalent) | When native mode active, show provider/model/variant selector in composer |
| `Package.swift` | Add `OAuthCallbackServer.swift` to sources (view files excluded from SPM as per project pattern) |

**Verify:** Xcode build passes. Settings renders, API key saves to Keychain. Model picker shows models for selected provider. Variant selector shows appropriate variants.

---

## Phase 10: Compaction, Subagents, Polish

**Goal:** Advanced features — context compaction, subagent spawning, system prompt assembly.

**New files (4):**

| File | Purpose |
|------|---------|
| `Agent/Runtime/ContextCompactor.swift` | Checks token count vs model limit, prunes old tool result outputs (keeps most recent within budget), triggers compaction agent for summary |
| `Agent/Runtime/SystemPromptBuilder.swift` | Assembles system prompt from agent definition + tool descriptions + project context + working directory |
| `Agent/Runtime/TokenEstimator.swift` | Rough token count estimation (`chars / 4` heuristic). Used by compactor. |
| `Agent/Tools/TaskTool.swift` | Spawns subagent (new `AgentLoop` with isolated context), returns result string to parent |

**Modify:**

| File | Change |
|------|--------|
| `Agent/Runtime/AgentLoop.swift` | Integrate compaction check before each LLM call |
| `Agent/Tools/ToolRegistry.swift` | Register `TaskTool` for primary mode |
| `Package.swift` | Add 4 source paths |

**Tests:** `ContextCompactorTests.swift` (pruning, threshold, minimum preserved), `TokenEstimatorTests.swift` (estimation accuracy).

**Verify:** `swift build` + `swift test` pass. Compaction triggers when conversation exceeds threshold. TaskTool returns isolated result.

---

## Summary

| Phase | New files | Tests | Key deliverable |
|-------|-----------|-------|-----------------|
| 1 | 12 | 2 | All types and protocols |
| 2 | 1 | 2 | Keychain credential storage |
| 3 | 6 | 4 | Claude, Codex, Z.AI adapters + variant mapper |
| 4 | 8 | 4 | 7 built-in tools + registry |
| 5 | 4 | 3 | SSE parser, HTTP transport, request builder |
| 6 | 5 | 4 | Agent loop + runtime + permissions |
| 7 | 1 | 1 | NativeAgentTransport (ChatTransport impl) |
| 8 | 1 | 1 | ChatState wiring + feature flag |
| 9 | 3 | 0 | Settings UI + OAuth callback server |
| 10 | 4 | 2 | Compaction, subagents, system prompts |
| **Total** | **45** | **23** | |

**Existing files modified:** `Package.swift` (all phases), `ChatState.swift` (Phase 8), `AppConfig.swift` (Phase 8), `SettingsView.swift` (Phase 9), `ChatInputView.swift` (Phase 9), `AgentLoop.swift` (Phase 10), `ToolRegistry.swift` (Phase 10).

## Verification (end-to-end)

After all phases:
1. `swift build` passes
2. `swift test` passes (all 23+ new test files + existing tests)
3. `xcodebuild -project SlothyTerminal.xcodeproj -scheme SlothyTerminal -configuration Debug build` passes
4. Enable native agent in settings, enter Anthropic API key
5. Open chat tab → sends message via native API → streams response with tool use → tools execute in-process → result renders in existing chat UI
6. Switch to terminal tab → still uses CLI transport as before
7. OAuth flow: click "Sign in with Claude" → browser opens → callback received → token stored in Keychain

## Reference Documents

- `opencode-approach.md` — How OpenCode integrates provider auth, model selection, reasoning variants, tool system, agent loop, permissions, session management, and context compaction
- `swift-agent-skeleton.md` — Concrete Swift implementation blueprint with copy-ready code for all protocols, adapters, tools, agent loop, and runtime composition

## Starting Implementation

To begin Phase 1, use the following prompt:

```
Implement Phase 1 of the native agent system from implementation.md.

Create the 12 core model and protocol files under SlothyTerminal/Agent/Core/.
Use the swift-agent-skeleton.md as reference for the concrete type definitions.
Follow the project's Swift style: 2-space indent, guard clauses multi-line with blank line after,
/// for doc comments, Sendable/Codable conformances.

After creating the files, update Package.swift to add all 12 source paths to SlothyTerminalLib.
Then create JSONValueTests.swift and ModelDescriptorTests.swift.

Verify with: swift build && swift test && xcodebuild -project SlothyTerminal.xcodeproj -scheme SlothyTerminal -configuration Debug build
```
