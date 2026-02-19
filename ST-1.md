# ST-1 Development Plan: Telegram Bot Tab

## Feature statement (from `FEATURES.md`)

ST-1 requires a Telegram bot that:

1. Listens to incoming Telegram messages.
2. Executes prompts and returns reports.
3. Accepts commands only from one configured Telegram user ID.
4. Ignores/blocks chats from other users.
5. Exposes tab controls: `Start`, `Stop`, `Listen but not execute commands`.
6. Starts listening automatically when the Telegram Bot tab is opened.

Additional command requirements:

7. `/report` returns current app status (open tabs, Claude/OpenCode idle vs processing, selected directory).
8. `/open-directory` opens a new tab with a predefined folder configured in settings.
9. The predefined folder must be inside a configured Telegram root directory.
10. `/new-task` asks for task text, then asks whether to start immediately or put into queue.
11. `/help` shows command hints and descriptions.

## Scope and assumptions

- This plan targets ST-1 only (not ST-3 startup screen redesign, not ST-5 status bar work).
- Bot execution will reuse the existing headless prompt execution stack (`ClaudeTaskRunner` / `OpenCodeTaskRunner`) to avoid duplicated execution logic.
- Telegram bot token may be stored directly in app settings (plain persisted config).
- "Chats with other users should not work" is implemented as strict filtering by `from.id == allowedUserId` (and recommended: private chat only).
- Telegram command protocol is text-first slash commands (no dependency on Telegram inline keyboards).

## High-level architecture

### 1) New Telegram bot domain layer

Add a Telegram-specific module with:

- `TelegramBotMode`: `.stopped`, `.listeningExecute`, `.listeningPassive`
- `TelegramBotStatus`: `.idle`, `.running`, `.error(String)`
- `TelegramBotEvent`: timestamped UI log event (received, ignored, executed, failed, sent)
- `TelegramBotStats`: counters (received, ignored, executed, failed)
- `TelegramUpdate` / `TelegramMessage` models for API decoding
- `TelegramCommand`: parser result for `/help`, `/report`, `/open-directory`, `/new-task`, unknown
- `TelegramInteractionState`: conversational state for `/new-task`
  - `.idle`
  - `.awaitingNewTaskText`
  - `.awaitingNewTaskSchedule(taskText: String)`

### 2) Telegram API service

Create `TelegramBotAPIClient` using `URLSession` and Telegram Bot API:

- `getUpdates(offset:timeout:)`
- `sendMessage(chatId:text:replyToMessageId:)`
- optional `sendChatAction(chatId: "typing")`

Implementation details:

- Long polling timeout: 25-30s
- Retry with exponential backoff on transient network errors
- Maintain `lastUpdateId` and request `offset = lastUpdateId + 1`

### 3) Bot runtime coordinator

Create `TelegramBotRuntime` (observable state container) that owns:

- polling task lifecycle
- mode transitions (`Start`, `Stop`, `Listen but not execute`)
- authorization filtering
- sequential prompt execution queue
- outbound Telegram responses
- command routing and response formatting
- `/new-task` interaction state machine

### 4) Prompt execution integration

Create `TelegramPromptExecutor` that reuses current runners:

- For configured provider `.claude` -> `ClaudeTaskRunner`
- For `.opencode` -> `OpenCodeTaskRunner`

Use existing working directory from the tab.

Response handling:

- send short "processing" ack
- run prompt
- send final report (chunked to Telegram size limit: 4096 chars per message)

## App integration plan

### 1) Configuration

#### `AppConfig` additions

Add Telegram bot settings, e.g.:

- `telegramBotToken: String?`
- `telegramAllowedUserID: Int64?`
- `telegramExecutionAgent: AgentType` (allowed: `.claude` or `.opencode`)
- `telegramAutoStartOnOpen: Bool` (default `true`)
- `telegramDefaultListenMode: TelegramBotMode` (default execute)
- `telegramReplyPrefix` (optional)
- `telegramRootDirectoryPath: String?` (required for `/open-directory` safety checks)
- `telegramPredefinedOpenSubpath: String?` (relative subfolder to open for `/open-directory`)
- `telegramOpenDirectoryTabMode: TabMode` (default `.chat`)
- `telegramOpenDirectoryAgent: AgentType` (default `.claude`, only chat-capable recommended)

### 2) Settings UI

Add a new Telegram section (recommended under `Agents` settings):

- Bot token input (stored in app settings)
- Allowed user ID input
- Execution provider picker (`Claude` / `OpenCode`)
- Auto-start toggle
- Default listen mode picker
- Root folder picker (for command sandbox)
- Predefined open subfolder text field (relative path only)
- Open-directory target tab mode + agent pickers
- Connection check button (calls `getMe` endpoint)

Validation rules:

- Token required for start
- Allowed user ID required for execution mode
- Root folder + predefined subfolder required for `/open-directory`
- Predefined subfolder must remain under root after path normalization
- Disable Start in UI when invalid

### 3) Tab model and routing

Integrate Telegram as a first-class tab type:

- Add Telegram tab creation entrypoint in `AppState`
- Add a `TelegramBotView` route in `ActiveTerminalView`
- Ensure closing the tab stops polling and cancels in-flight execution

Recommended minimal approach:

- Introduce a dedicated tab mode for bot view to avoid overloading existing chat/terminal paths.

### 4) Entry points in UI

Add "New Telegram Bot Tab" in:

- New tab modal list
- Empty state quick actions
- App menu (`File`)

## Runtime behavior details

### Start behavior

When Telegram tab appears:

1. If `telegramAutoStartOnOpen == true`, call runtime `start()` immediately.
2. Start in configured default mode (`execute` or `passive`).
3. Show running indicator and write startup event.

### Authorization filter

For each update:

- If message has no `from.id`: ignore
- If `from.id != allowedUserID`: ignore and log
- Recommended: if chat is not private -> ignore and log

No command execution for unauthorized senders.

### Listen-only mode

- Polling remains active
- Messages from allowed user are logged
- No prompt execution occurs
- Optional reply: "Received in listen-only mode"

### Execute mode

- Accept text messages from allowed user
- Queue them FIFO (single execution at a time)
- For each message:
  - send ack
  - execute prompt
  - send summarized/chunked report
  - log result and update counters

### Predefined commands

#### `/help`

- Returns command catalog with concise descriptions:
  - `/help` - show this help and usage hints
  - `/report` - show current app/tabs status snapshot
  - `/open-directory` - open configured subfolder under configured root
  - `/new-task` - create a task via guided dialog (immediately or queue)
- Should include short usage examples and accepted answers for `/new-task` scheduling.

#### `/report`

- Returns a compact snapshot:
  - open tabs list (`tabName`, mode, working directory)
  - Claude/OpenCode tab runtime state (`idle` or `processing`)
  - active/selected directory (active tab directory)
  - Telegram bot mode and queue summary
- Data source: `AppState` + per-tab state (`chatState` / runtime flags).

#### `/open-directory`

- Opens a new tab using predefined folder from settings.
- Resolution flow:
  1. Read `telegramRootDirectoryPath` and `telegramPredefinedOpenSubpath`.
  2. Resolve absolute path and normalize (`standardizedFileURL`, symlink-safe checks).
  3. Reject if resulting path is outside root.
  4. Open tab via `AppState` using configured mode+agent.
- Success reply includes opened path and tab type.

#### `/new-task`

- Conversational flow (only for allowed user):
  1. User sends `/new-task`.
  2. Bot asks: "Send task text".
  3. User sends task description.
  4. Bot asks: "Start immediately or put to queue?".
  5. User replies `immediately` or `queue`.
- Execution behavior:
  - `immediately`: start task execution directly via `TelegramPromptExecutor` when free.
  - `queue`: enqueue in `TaskQueueState` as pending.
- If immediate execution is already busy, fallback is queue with explicit confirmation in reply.
- Any non-matching answer at step 5 prompts retry with accepted options.

### Command precedence

- If message starts with `/`, route through command parser first.
- `/help` always returns command help text.
- Unknown slash command returns help text listing supported commands.
- Non-command text in execute mode is treated as normal prompt input.

### Message timeline and autoscroll

- All inbound and outbound Telegram messages must be visible in the tab.
- Message timeline order is chronological (oldest at top, newest at bottom).
- The message list auto-scrolls to the latest message at the bottom on:
  - new inbound Telegram message
  - bot ack message
  - final report/failure reply
  - mode/status system message appended to the timeline
- Recommended SwiftUI implementation:
  - `ScrollViewReader` + stable message IDs
  - always scroll to latest item with `.bottom` anchor after append
  - keep a `Jump to latest` fallback button if user manually scrolls up

### Stop behavior

- Cancel polling task
- Cancel current runner (SIGINT + force-kill fallback)
- Transition UI to stopped

## Telegram Bot tab UI spec

`TelegramBotView` should include:

- Top controls:
  - `Start`
  - `Stop`
  - `Listen but not execute commands`
- Status row:
  - mode badge
  - running/error state
  - allowed user id
  - execution provider
- Supported commands hint:
  - `/help`
  - `/report`
  - `/open-directory`
  - `/new-task`
- Telegram message timeline (newest at bottom) showing:
  - incoming user messages
  - bot ack/reports/failure replies
  - command prompts and `/new-task` interactive steps
  - optional system events as muted rows
- Auto-scroll behavior to latest bottom message
- Activity log list (operational events, newest last)
- Counters (received/ignored/executed/failed)

## Error handling and resiliency

- Invalid token (`401`): move to error state, stop polling, show actionable message.
- Network timeout: retry with backoff; keep running state unless retry budget exceeded.
- Execution failure: send failure report to allowed user and log details.
- Telegram send failure: log and continue processing next message.
- Duplicate updates: prevented via `lastUpdateId` offset progression.
- Invalid `/open-directory` path (outside root): reject and never open tab.
- Invalid `/new-task` interaction step input: keep state and ask again.

## Test plan

### Unit tests

1. Authorization filtering:
   - allowed user executes
   - non-allowed user ignored
2. Mode transitions:
   - start/stop/passive transitions
   - auto-start on appear
3. Queue behavior:
   - FIFO execution
   - no parallel executions
4. Message chunking:
   - split >4096 chars correctly
5. Error handling:
   - invalid token stops runtime
   - transient polling errors retry
6. Message timeline behavior:
   - inbound/outbound message append order is correct
   - auto-scroll trigger is fired on each append
7. Command parsing:
   - `/help`, `/report`, `/open-directory`, `/new-task` recognized correctly
   - unknown slash command returns help
8. `/open-directory` path safety:
   - inside-root path accepted
   - outside-root path rejected
9. `/new-task` interaction state machine:
   - prompt -> collect text -> schedule choice -> execute/queue
   - invalid schedule choice retries without losing text

### Integration tests (with mocks)

1. Poll update -> execute -> send report flow
2. Poll update in passive mode -> no execute
3. Stop during execution -> runner cancel path called
4. Message timeline renders both inbound and outbound messages
5. Timeline auto-scrolls to latest bottom entry
6. `/report` returns accurate snapshot of tabs and statuses
7. `/open-directory` creates tab only for valid configured subfolder
8. `/new-task` full conversational flow works for both immediate and queue paths
9. `/help` returns command hints and descriptions

## Implementation phases

### Phase 1: Core plumbing

- Models + API client + message timeline models
- AppConfig settings fields
- Settings UI

### Phase 2: Runtime engine

- Polling lifecycle
- mode state machine
- authorization filter
- event logging
- command parser and dispatcher
- `/new-task` interaction state machine

### Phase 3: Execution bridge

- integrate `TelegramPromptExecutor` with existing task runners
- report formatting/chunking
- `/report` snapshot formatter from `AppState`
- `/open-directory` tab opening bridge to `AppState`
- `/new-task` immediate execution + queue enqueue bridge

### Phase 4: Tab integration

- Telegram tab route and UI
- controls wired to runtime
- message timeline in tab (inbound/outbound)
- bottom auto-scroll to latest message
- auto-start on open

### Phase 5: Hardening

- tests
- manual QA scenarios
- edge-case fixes

## Acceptance criteria mapping to ST-1

1. **Listen to Telegram messages**: runtime long-poll loop is active while started.
2. **Do prompts and return reports**: allowed user message executes via runner and reply is sent.
3. **Only specific user id works**: strict sender filter enforced.
4. **Other chats do not work**: unauthorized updates are ignored and never executed.
5. **Tab buttons**: Start/Stop/Listen-only are available and functional.
6. **Auto-start on open**: opening Telegram tab automatically starts listening.
7. **`/report` works**: bot returns current tab/state/directory snapshot.
8. **`/open-directory` works safely**: opens only configured subfolder under configured root.
9. **`/new-task` works interactively**: bot asks for task text and immediate-vs-queue scheduling.
10. **`/help` works**: bot returns supported commands with short descriptions and usage hints.
