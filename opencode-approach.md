# OpenCode API Integration Approach (Codex, Claude, GLM)

This document captures how OpenCode integrates provider auth, model selection, and reasoning/thinking variants, focused on Codex (OpenAI OAuth), Claude (Anthropic OAuth/API), and Z.AI/GLM.

## 1) Provider/Auth Architecture

- OpenCode uses a plugin-based auth layer. Internal plugins are loaded first, then user-configured plugins.
- Built-in auth plugins in core:
  - `CodexAuthPlugin` (`packages/opencode/src/plugin/codex.ts`)
  - `CopilotAuthPlugin` (`packages/opencode/src/plugin/copilot.ts`)
- Anthropic OAuth subscription support is loaded as a built-in npm plugin:
  - `opencode-anthropic-auth@0.0.13` (declared in `packages/opencode/src/plugin/index.ts`)
- Provider runtime state is assembled from:
  1. models catalog (`models.dev`)
  2. config (`opencode.json` etc.)
  3. env/API credentials
  4. plugin auth loader patches

Key files:

- `packages/opencode/src/plugin/index.ts`
- `packages/opencode/src/provider/provider.ts`
- `packages/opencode/src/provider/auth.ts`

## 2) Codex Integration (ChatGPT subscription + API key fallback)

Core implementation:

- `packages/opencode/src/plugin/codex.ts`

### Auth methods

- Browser OAuth (PKCE + local callback server on `localhost:1455`)
- Headless/device auth flow
- Manual API key mode

### Subscription-aware behavior

When OpenAI auth type is OAuth:

- Filters models to Codex-compatible set (`gpt-5.x-codex`, `gpt-5.2`, `gpt-5.3-codex`, etc.)
- Sets model costs to zero in UI/runtime accounting (subscription-inclusive behavior)
- Replaces transport with custom `fetch` that:
  - strips default API key auth header
  - refreshes access token when expired
  - sets `Authorization: Bearer <access_token>`
  - adds `ChatGPT-Account-Id` when available (org/subscription context)
  - rewrites `/v1/responses` and `/chat/completions` to Codex endpoint:
    - `https://chatgpt.com/backend-api/codex/responses`

### Account ID extraction

- Parses JWT claims (`id_token` or fallback `access_token`) for:
  - `chatgpt_account_id`
  - nested `https://api.openai.com/auth.chatgpt_account_id`
  - fallback org id from `organizations[0].id`

## 3) Claude Integration (Anthropic)

Core loader reference in this repo:

- `packages/opencode/src/plugin/index.ts` (loads `opencode-anthropic-auth@0.0.13`)

External plugin behavior (package source inspected):

- Supports OAuth for Claude Pro/Max
- Supports API key mode
- OAuth mode:
  - stores refresh/access/expires
  - refreshes tokens automatically
  - applies OAuth bearer transport
  - ensures required anthropic beta headers
  - zeroes model costs for subscription-backed usage
- Also includes an OAuth path that can create an Anthropic API key

## 4) Model Discovery and Selection

Model/provider composition pipeline:

- `packages/opencode/src/provider/models.ts`: loads models catalog
- `packages/opencode/src/provider/provider.ts`: merges catalog + config + auth + plugin patches

Selection behavior in session:

- User prompt stores model `{providerID, modelID}` and optional `variant`
- If no explicit model is passed:
  - use agent model
  - else last used model in session
  - else provider default model
- TUI stores recents/favorites and per-model selected variant

Key files:

- `packages/opencode/src/session/prompt.ts`
- `packages/opencode/src/cli/cmd/tui/context/local.tsx`
- `packages/opencode/src/cli/cmd/tui/component/prompt/index.tsx`

## 5) Thinking/Reasoning Mode Mapping

Central logic:

- `packages/opencode/src/provider/transform.ts`

### Variant generation

`ProviderTransform.variants(model)` generates named variants (for UI cycle and per-request override), provider-specific:

- OpenAI/Codex (`@ai-sdk/openai`): variants map to `reasoningEffort`
  - commonly `low/medium/high`
  - some models include `minimal`, `none`, `xhigh`
- Anthropic (`@ai-sdk/anthropic`): variants map to `thinking`
  - usually `high/max` via budget tokens
  - some models expose adaptive `low/medium/high/max`
- Z.AI/GLM special behavior:
  - if model id includes `glm`, variants return `{}` (no low/high list)
  - but defaults still enable thinking for `zai`/`zhipuai` providers:
    - `thinking: { type: "enabled", clear_thinking: false }`

### Option merge order

In LLM execution:

1. Base provider/model options (`ProviderTransform.options` or `smallOptions`)
2. Model-level options (`model.options`)
3. Agent options
4. Selected variant options

This lets variant override baseline defaults cleanly.

## 6) Session + Streaming Interaction Model

Pipeline:

1. Prompt persists user message (model + variant included)
2. Session builds model messages + system prompt
3. Stream is started via `LLM.stream`
4. Streaming events are parsed and persisted as parts:
   - `text`
   - `reasoning`
   - `tool` calls/results
5. Token/cost accounting includes reasoning tokens

Key files:

- `packages/opencode/src/session/llm.ts`
- `packages/opencode/src/session/processor.ts`
- `packages/opencode/src/session/message-v2.ts`
- `packages/opencode/src/session/index.ts`

## 7) Tool System

Central files:

- `packages/opencode/src/tool/registry.ts` (discovery and loading)
- `packages/opencode/src/tool/*.ts` (individual tool implementations)

### Tool interface

Every tool implements:

```
init(ctx) → { description, parameters (zod schema), execute(args, ctx) → { title, metadata, output, attachments? } }
```

Tools are stateless functions. The runtime calls `init()` once to get the schema, then `execute()` per invocation.

### Tool registry

`ToolRegistry.all()` assembles available tools per request:

1. Built-in tools (bash, read, write, edit, glob, grep, ls, task, todo, webfetch, etc.)
2. Custom tools from user config dirs (`{tool,tools}/*.{js,ts}`)
3. Plugin-provided tools via `Plugin.list()`
4. MCP server tools (converted to AI SDK dynamic tools)

Tool set is filtered per request based on:

- Model type (GPT models get `apply_patch` instead of `edit`/`write`)
- Feature flags (`OPENCODE_EXPERIMENTAL_LSP_TOOL`, `OPENCODE_EXPERIMENTAL_PLAN_MODE`)
- Agent mode (explore agent only gets read-only tools)

### Built-in tools

| Tool | Purpose |
|------|---------|
| BashTool | Shell execution with configurable timeout |
| ReadTool | File reading |
| WriteTool | File creation |
| EditTool | String-replacement file editing |
| MultiEditTool | Multi-file edit in one call |
| ApplyPatchTool | Unified diff patch (GPT models) |
| GlobTool | File pattern search |
| GrepTool | Content search (ripgrep) |
| LsTool | Directory listing |
| TaskTool | Spawn subagent for parallel/isolated work |
| TodoWriteTool | Task list management |
| WebFetchTool | URL content fetching |
| WebSearchTool | Web search (restricted) |
| CodeSearchTool | Code search (restricted) |
| SkillTool | Invoke registered skills |
| LspTool | LSP operations (experimental) |
| BatchTool | Parallel tool execution (experimental) |
| PlanEnterTool / PlanExitTool | Plan mode transition |
| QuestionTool | Ask user questions mid-execution |

## 8) Agent Abstraction

Primary file: `packages/opencode/src/agent/agent.ts`

### What an agent is

An agent is a named configuration bundle that controls:

- Which tools are available
- What system prompt to use
- Permission ruleset (what the agent can do without asking)
- Model/variant defaults
- Temperature and sampling parameters
- Whether it's a primary agent or a subagent

### Built-in agents

| Agent | Mode | Key trait |
|-------|------|-----------|
| `build` | primary | Default. Full tool access, question/plan enabled. |
| `plan` | primary | Read-only mode — disallows all edit/write/delete tools. |
| `general` | subagent | Multi-step task executor. Can run tools in parallel. |
| `explore` | subagent | Fast codebase exploration. Read-only: grep, glob, bash, read. |
| `compaction` | primary (hidden) | Summarizes session when context overflows. |
| `title` | primary (hidden) | Auto-generates session titles. |
| `summary` | primary (hidden) | Session summarization on demand. |

### Agent modes

- **primary**: drives the main conversation, shown in UI
- **subagent**: spawned by TaskTool for isolated subtasks, returns result to parent
- **hidden**: internal-use only, not selectable by user

### Configuration

Agents support overrides via `config.agent.<name>.*`:

- `model` / `variant` — force model/variant
- `prompt` — custom system prompt
- `permission` — custom permission ruleset
- `disabled` — hide agent
- `steps` — max tool execution rounds

Default agent is resolved by `Agent.defaultAgent()`: first visible primary agent, or `config.default_agent`.

## 9) Core Agent Loop

The agent loop is the central execution pattern. Located in:

- `packages/opencode/src/session/prompt.ts` (orchestration)
- `packages/opencode/src/session/processor.ts` (stream processing)
- `packages/opencode/src/session/llm.ts` (LLM call assembly)

### Loop steps

```
1. User message → persist to session
2. Build messages array (history + system prompt)
3. Call LLM.stream() with tools, options, variant
4. Process stream events:
   a. text → display to user
   b. reasoning → display thinking
   c. tool-call → execute tool → persist result → append to messages
5. If tool calls were made → go to step 2 (new LLM turn with tool results)
6. If no tool calls (text-only response) → done
```

### Stream events (processor.ts)

The processor emits typed events during streaming:

- `text-start` / `text-delta` / `text-end`
- `reasoning-start` / `reasoning-delta` / `reasoning-end`
- `tool-input-start` / `tool-input-delta` / `tool-input-end`
- `tool-call` → triggers tool execution
- `tool-result` / `tool-error`
- `start-step` / `finish-step` (with snapshots for undo)
- `finish`

### Doom-loop detection

If the same tool is called 3+ times with identical input, the processor pauses and asks the user for permission to continue. This prevents infinite loops.

### Tool execution within loop

1. LLM emits `tool-call` with tool ID + arguments
2. Processor validates tool exists in registry
3. Permission system checks if tool call is allowed (`PermissionNext.ask()`)
4. If allowed → execute tool → get output string
5. If denied/rejected → stop loop or provide error to LLM
6. Tool result (output string + metadata) appended to message history
7. Loop continues with updated context

## 10) Permission System

Primary file: `packages/opencode/src/permission/next.ts`

### Model

- **Actions**: `allow | deny | ask`
- **Rules**: `{ permission, pattern, action }` — pattern supports wildcards for both permission name and file path
- **Persistence**: rules stored in SQLite `PermissionTable`, scoped per project

### How it works

1. Before tool execution, `PermissionNext.ask(permission, path)` is called
2. Rules evaluated top-to-bottom; first match wins
3. If action is `allow` → proceed silently
4. If action is `deny` → throw `DeniedError`
5. If action is `ask` (or no rule matches) → pause execution, prompt user
6. User replies: `once` (session-scoped), `always` (persist rule), or `reject` (halt)

### Configuration

```json
{
  "permission": {
    "edit": "allow",
    "bash": { "/tmp/*": "deny", "*": "ask" },
    "read": "allow"
  }
}
```

Edit tools (`edit`, `write`, `patch`, `multiedit`) all map to the `"edit"` permission key.

## 11) Session and Message Management

### Message model (v2)

File: `packages/opencode/src/session/message-v2.ts`

Messages have roles (`user` | `assistant`) and contain typed parts:

- `text` — plain text content
- `tool-call` — tool invocation (tool ID, arguments, state)
- `tool-result` — tool output (output string, metadata)
- `reasoning` — extended thinking content
- `step-start` / `step-end` — marks LLM turn boundaries with snapshots

Each part has: `id`, `messageID`, `sessionID`, `type`, `state`, `metadata`.

### Session persistence

- Sessions, messages, and parts are stored in SQLite
- Schema: `packages/opencode/src/session/session.sql.ts`
- CRUD: `packages/opencode/src/session/index.ts`
- Token/cost usage tracked per session

### Context compaction

File: `packages/opencode/src/session/compaction.ts`

When message tokens exceed `model.limit.input - reserved`:

1. **Prune**: remove tool outputs from messages 3+ turns ago (keep min 40k tokens of tool calls)
2. **Summarize**: run `compaction` agent to generate context summary
3. Replace pruned messages with summary

Config: `compaction.auto` (toggle), `compaction.reserved` (buffer override), `compaction.prune` (enable pruning).

### Session revert

File: `packages/opencode/src/session/revert.ts`

Each step boundary stores a snapshot. Users can undo to any previous step.

## 12) Subagent / Task Delegation

The `TaskTool` (`packages/opencode/src/tool/task.ts`) lets the primary agent spawn subagents:

- Spawns a new agent (typically `general` or `explore`) in an isolated context
- The subagent has its own tool set, permission scope, and message history
- Result is returned as a string to the parent agent's tool output
- Enables parallel work: primary agent can spawn multiple subagents simultaneously

Use cases:

- `explore` subagent for codebase research without polluting main context
- `general` subagent for independent multi-step tasks
- Isolation: subagent failures don't crash the parent session

## 13) Practical Reuse Guidance

For your own app, the reusable patterns are:

**Transport layer** (what the current Swift skeleton covers):

- Adapter-based provider auth/transport hooks
- Per-provider request option mapping
- Per-model variant presets with stable names (`low`, `high`, `max`, etc.)
- Persisted model+variant selection in UI state

**Agent layer** (what needs to be added to the Swift skeleton):

- Tool protocol: `id + description + parameters schema + execute(args) → output`
- Tool registry: assemble available tools per agent mode
- Core loop: LLM → parse stream → execute tools → feed results → repeat
- Permission checks before tool execution
- Streaming part model (`text`, `reasoning`, `tool-call`, `tool-result`) for robust UX
- Session persistence: messages + parts in local DB
- Context compaction: prune + summarize when approaching token limit
- Subagent spawning for parallel/isolated work
- Doom-loop detection (same tool + same args 3+ times)
- Step snapshots for undo/revert

Security notes:

- Do not reuse third-party OAuth client IDs in production apps. Register your own OAuth clients where required by provider terms.
- Permission system is critical — never auto-allow destructive tools (bash, write, edit) without user consent.
