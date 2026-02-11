# Task Queue & Agent Orchestration Plan

## Goal

Implement a reliable task system where users can enqueue many tasks for Claude/OpenCode (and other agents), and each next task starts automatically after the current one reaches a terminal state.

## Scope

- Serial execution in MVP (one active task at a time)
- Support multiple agent backends through a shared runner interface
- Persist queue/task state so work survives app restarts
- Provide basic queue UI (create, reorder, run, cancel, retry)
- Capture task logs and final summaries for review
- Add approval gates for risky operations (commit/push/delete/migrations)

## Non-Goals (MVP)

- Full DAG/workflow editor
- Cross-machine distributed execution
- Complex policy engine (RBAC, quotas)

## Requirements

1. Users can add tasks with:
   - Prompt/instructions
   - Agent type (Claude/OpenCode/Terminal)
   - Optional model/mode overrides
   - Priority
2. Queue runs tasks sequentially by default.
3. After a task completes/fails/cancels, scheduler starts the next eligible task automatically.
4. Queue state and task history are persisted and restored on launch.
5. Users can cancel active task and retry failed tasks.
6. Intermediate tool events must not be treated as completion; only provider terminal result marks completion.

## Decision Snapshot (Locked)

- Queue topology: per-repository lane model; MVP runs serially with one active task globally.
- Retry default: auto-retry once for transient failures only.
- Cancellation: graceful cancel first, then force-kill after 10 seconds.
- Risk controls: approval gates enabled for risky operations.
- Default timeout: 30 minutes per task.
- Output persistence: structured result fields plus full event/log artifact.
- Log retention: cap full log artifact at 5 MB per task with truncation marker.
- Task mutability: only pending tasks are editable/reorderable.
- Restart recovery: previously running tasks become pending with "interrupted" note.
- MVP parallelism: disabled (single active task).
- Approval gate behavior: pause queue until user approves/rejects.
- Gate trigger source: structured tool/event detection.
- Model unavailability: fallback to configured default model before failing.

## Architecture

### 1) Data Model

Create a dedicated task domain:

- `TaskStatus`: `pending`, `running`, `completed`, `failed`, `cancelled`
- `TaskPriority`: `high`, `normal`, `low`
- `QueuedTask`:
  - `id`, `title`, `prompt`
  - `repoPath` (execution working directory key)
  - `agentType`, `model`, `mode`
  - `status`, `priority`, `retryCount`, `maxRetries`
  - `runAttemptId` (unique id for each execution attempt)
  - `createdAt`, `startedAt`, `finishedAt`
  - `lastError`, `resultSummary`, `exitReason`
  - `sessionId` (link to chat session if applicable)
  - `approvalState` (`none`, `waiting`, `approved`, `rejected`)
  - `logArtifactPath`

Optional (post-MVP): `dependsOn`, `onSuccess`, `onFailure`, `laneId`.

### 2) Persistence

Add `TaskQueueStore` in storage layer (parallel to `ChatSessionStore` style):

- Save/load queue snapshot JSON
- Atomic write strategy (tmp file + replace)
- Schema version field for future migrations
- Restore in-progress tasks as `pending` with note "interrupted by app restart"
- Persist per-task full logs/events as artifacts with size cap + truncation metadata
- Default per-task log artifact cap: 5 MB

### 3) Execution Abstraction

Define a runner protocol so orchestration is backend-agnostic:

- `TaskRunner` protocol:
  - `start(task:) async -> AsyncThrowingStream<TaskEvent, Error>`
  - `cancel(taskId:) async`
  - `preflight(task:) async throws` (agent availability + repo path checks)
  - `resolveModel(task:) async -> ResolvedModel` (selected model or configured fallback)
- Implementations:
  - `ClaudeTaskRunner` (using Claude transport)
  - `OpenCodeTaskRunner` (using OpenCode transport)
  - `TerminalTaskRunner` (optional MVP if low effort)

Map provider events to unified `TaskEvent` (`log`, `progress`, `result`, `error`).

### 4) Orchestration

Add `TaskOrchestrator` as an `actor`:

- Responsibilities:
  - Select next runnable task (priority + FIFO tie-break)
  - Mark task `running`
  - Stream events/logs
  - Handle approval gates and pause progression when awaiting decision
  - Transition to terminal state
  - Auto-dispatch next task
- Safety:
  - Enforce single active task in MVP; scheduler model keyed by `repoPath` for future lanes
  - Default timeout: 30 minutes per task
  - Cancellation policy: graceful stop, then force-kill after 10 seconds
  - Retry policy with exponential backoff

Core loop:

1. Pick next pending task.
2. Start runner and consume events.
3. On terminal result -> complete/fail.
4. Persist snapshot.
5. Start next.

### 5) App Integration

Extend `AppState`:

- Hold `TaskQueueState` and expose user intents:
  - `enqueueTask(...)`
  - `startQueue()` / `pauseQueue()`
  - `cancelTask(id)`
  - `retryTask(id)`
  - `reorderTasks(...)`
  - `approveTask(id)` / `rejectTask(id)`
  - `editPendingTask(id, ...)`
- Wire startup restoration:
  - Load queue from store
  - Initialize orchestrator
  - Resume if auto-run enabled

### 6) UI

MVP screens/components:

- Queue list panel:
  - Pending/running/history sections
  - Status chips, timestamps, agent/model labels
- Task composer sheet:
  - Title, prompt, agent, model, priority
- Task detail/log view:
  - Streaming logs/events
  - Final summary/error
- Controls:
  - Run/Pause queue
  - Cancel running task
  - Retry failed task
  - Reorder pending tasks
  - Approve/Reject gated task

### 6.1) UI Visualization

Desktop layout sketch:

```text
+----------------------------------------------------------------------------------+
| Sidebar                 | Task Queue                                | Inspector   |
|-------------------------|-------------------------------------------|-------------|
| [New Task]              | Queue: Running / Pending / History        | Task Detail |
| [Run/Pause]             |-------------------------------------------|-------------|
| [Filter: All Agents]    | RUNNING                                    | Title       |
| [Sort: Priority/FIFO]   | > [OpenCode] Refactor parser   01:42      | Status      |
|                         |   logs streaming...                        | Agent/model |
|                         |-------------------------------------------| Retries     |
|                         | PENDING                                    | Started/End |
|                         | 1. [Claude] Add tests                      |-------------|
|                         | 2. [OpenCode] Update docs                  | Live Logs   |
|                         | 3. [Claude] Fix lint                       | [stream...] |
|                         |-------------------------------------------|-------------|
|                         | HISTORY                                    | Actions     |
|                         | - Completed: Improve UI copy               | Cancel      |
|                         | - Failed: Migrate schema (Retry)           | Retry       |
+----------------------------------------------------------------------------------+
```

Task composer sheet sketch:

```text
+--------------------------------------------------------------+
| Create Task                                                  |
|--------------------------------------------------------------|
| Title            [________________________________________]  |
| Prompt           [________________________________________]  |
|                  [________________________________________]  |
| Agent            (Claude v) (OpenCode) (Terminal)           |
| Model/Mode       [auto___________________________________]   |
| Priority         (High) (Normal) (Low)                      |
| Timeout (sec)    [600___]   Max Retries [1_]                |
|--------------------------------------------------------------|
| [Cancel]                                      [Enqueue Task] |
+--------------------------------------------------------------+
```

Queue state visualization:

```text
pending -> running -> completed
           |   ^
           |   |
           v   |
         failed ----retry----+
           |
           v
        cancelled
```

Primary user flow:

```text
Create Task(s) -> Enqueue -> Scheduler picks next -> Run + stream logs
   -> Terminal result?
      -> yes: Complete -> auto-start next pending
      -> no (error/timeout): Fail -> optional retry -> next pending
```

Mobile/compact fallback:

- Segment control: `Running | Pending | History`
- Tapping a row pushes full-screen detail/log view
- Composer opens as full-screen sheet
- Reorder available in `Pending` list edit mode

## Execution Semantics

### Completion Rules (Critical)

- Mark task `completed` only on provider terminal result event.
- Do not complete on intermediate events (`tool_use`, `tool-calls`, `message_stop`, partial chunks).
- Mark `failed` on terminal error or timeout.
- Mark `cancelled` only on explicit user cancel or orchestrator shutdown handling.

### Failure Taxonomy

- `transient`: transport disconnect, process crash, timeout, temporary model unavailable.
- `permanent`: invalid prompt/config, missing repo path, unsupported model/agent pair, approval rejected.
- Auto-retry only `transient` failures (up to configured max retries).
- Never auto-retry `cancelled` or `approval rejected` outcomes.

### Model Resolution

- On start, try selected model first.
- If unavailable, fallback to configured default model for that agent.
- Record resolved model in task metadata/history.
- If fallback is also unavailable, fail as permanent preflight error.

### Approval Gate Semantics

- If risky operation is detected via structured tool/event signals, task enters `approvalState = waiting` and queue pauses.
- User decision outcomes:
  - `approve`: task resumes from gate and continues.
  - `reject`: task marked `failed` with `exitReason = approvalRejected`; queue continues to next task.
- Gate timeout (if configured) should default to no auto-decision in MVP (manual decision required).

### Retry Rules

- Default `maxRetries = 1` (configurable)
- Retry only transient failures (transport/process/timeouts/model temporary unavailable)
- Do not auto-retry on explicit user cancellation

## Implementation Phases

### Phase 1: Foundation

1. Create models (`QueuedTask`, status/priority/event types)
2. Implement `TaskQueueStore` with snapshot read/write
3. Add `TaskQueueState` to `AppState`

Deliverable: queue persists and restores with no execution.

### Phase 2: Orchestrator + Runner Adapters

1. Build `TaskOrchestrator` actor + scheduling policy
2. Implement Claude/OpenCode `TaskRunner` adapters
3. Add cancellation, 30-minute timeout, and terminal-state handling
4. Add preflight validation for agent/model/repo path

Deliverable: headless sequential execution works end-to-end.

### Phase 3: UI + Controls

1. Queue list + task composer
2. Task detail with live logs
3. Run/pause/cancel/retry/reorder actions
4. Approval gate prompts + queue-paused state UI

Deliverable: full user-facing queue workflow.

### Phase 4: Hardening

1. Recovery behavior after restart/crash
2. Retry/backoff tuning
3. Observability (event counters, failure reasons)
4. Edge-case fixes (duplicate starts, stale state)

Deliverable: production-ready MVP.

## Testing Plan

### Unit Tests

- Task state transitions are valid and deterministic
- Scheduler ordering: priority first, FIFO within priority
- Retry/backoff logic
- Restore logic for interrupted running tasks
- Failure classification (transient vs permanent)
- Cancel flow (graceful then force-kill)
- Approval gate pause/resume behavior

### Integration Tests

- End-to-end run with mocked transports
- Correct terminal completion behavior (no false positives)
- Cancellation during active task
- Automatic continuation to next task
- Approval gate blocks progression until decision
- Preflight failures are surfaced without starting run

### Manual QA

- Enqueue 5+ mixed tasks and confirm serial execution
- Kill/relaunch app during running task and verify recovery
- Retry failed task and inspect logs/history
- Trigger risky action and verify gate + pause + approve/reject outcomes

## Risks & Mitigations

- **Risk:** Provider event ambiguity causes stuck/early completion.
  - **Mitigation:** Centralize completion checks in one reducer with explicit terminal-event guards.
- **Risk:** Concurrent runs produce repo conflicts.
  - **Mitigation:** Default single lane; add opt-in multi-lane later.
- **Risk:** Persistence corruption on crash.
  - **Mitigation:** Atomic file writes + schema versioning + fallback recovery.

## Acceptance Criteria (MVP)

1. User can enqueue tasks for Claude/OpenCode.
2. Queue executes one-by-one automatically.
3. On completion/failure/cancel, next task starts without manual action.
4. Queue survives app restart with meaningful recovery behavior.
5. User can cancel and retry tasks from UI.
6. Logs and final result summary are visible per task.
7. Risky operations trigger approval gate and pause queue until decision.
8. Transient failures retry once automatically; permanent failures do not auto-retry.

## Suggested File Placement

- `Models/Task/QueuedTask.swift`
- `Task/Engine/TaskOrchestrator.swift`
- `Task/Runner/TaskRunner.swift`
- `Task/Runner/ClaudeTaskRunner.swift`
- `Task/Runner/OpenCodeTaskRunner.swift`
- `Task/Storage/TaskQueueStore.swift`
- `Task/State/TaskQueueState.swift`
- `UI/TaskQueue/*` (views)

## Future Extensions

- Task dependencies and conditional branches
- Multi-lane execution by working directory/repository
- Scheduled tasks and recurring automation
- Templates/macros for common workflows
- Approval checkpoints before risky operations
