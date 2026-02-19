# ST-1 Telegram Tab Visualization

This file visualizes the Telegram Bot tab UI proposed in `ST-1.md`.

## 1) Default layout (execute mode)

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│ Telegram Bot                                                                │
├─────────────────────────────────────────────────────────────────────────────┤
│ Status: ● Running   Mode: Execute   Allowed User: 123456789   Agent: Claude│
│                                                                             │
│ [ Start ]  [ Stop ]  [ Listen but not execute commands ]                   │
│ Commands: /help   /report   /open-directory   /new-task                    │
├─────────────────────────────────────────────────────────────────────────────┤
│ Counters                                                                    │
│ Received: 42   Ignored: 8   Executed: 31   Failed: 3                        │
├─────────────────────────────────────────────────────────────────────────────┤
│ Telegram Messages (auto-scroll to bottom)                                   │
│                                                                             │
│ 22:10:07  [IN ]  @allowedUser: "review latest crash logs"                  │
│ 22:10:07  [OUT]  Bot: "Got it. Processing your request..."                 │
│ 22:10:14  [OUT]  Bot: "Report: root cause is ..."                          │
│ 22:11:45  [OUT]  Bot: "Execution failed: timeout"                          │
├─────────────────────────────────────────────────────────────────────────────┤
│ Activity Log                                                                 │
│ 22:10:01  INFO Bot started (auto-start on tab open)                          │
│ 22:11:02  WARN Ignored message from unauthorized user 99887766               │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 2) Listen-only mode

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│ Telegram Bot                                                                │
├─────────────────────────────────────────────────────────────────────────────┤
│ Status: ● Running   Mode: Listen-only   Allowed User: 123456789            │
│                                                                             │
│ [ Start ]  [ Stop ]  [ Listen but not execute commands ] (active)          │
├─────────────────────────────────────────────────────────────────────────────┤
│ Telegram Messages (auto-scroll to bottom)                                   │
│ 22:20:03  [IN ]  @allowedUser: "deploy latest branch"                      │
│ 22:20:03  [OUT]  Bot: "Listen-only mode: command not executed."            │
├─────────────────────────────────────────────────────────────────────────────┤
│ Activity Log                                                                 │
│ 22:20:03  INFO Message received from user 123456789                          │
│ 22:20:03  INFO Listen-only mode active, execution skipped                    │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 3) Stopped state

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│ Telegram Bot                                                                │
├─────────────────────────────────────────────────────────────────────────────┤
│ Status: ○ Stopped   Mode: Execute                                           │
│                                                                             │
│ [ Start ] (enabled)   [ Stop ] (disabled)   [ Listen but not execute ... ] │
├─────────────────────────────────────────────────────────────────────────────┤
│ Last event: Bot stopped by user                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 4) Configuration error state

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│ Telegram Bot                                                                │
├─────────────────────────────────────────────────────────────────────────────┤
│ Status: ! Error                                                             │
│ Reason: Missing bot token or allowed user ID                                │
│                                                                             │
│ [ Open Settings ]   [ Retry Start ]                                         │
├─────────────────────────────────────────────────────────────────────────────┤
│ Hint: Configure Telegram token and allowed user ID first                     │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 5) Interaction notes

- Opening the tab auto-starts polling when auto-start is enabled.
- `Start` always transitions to active polling.
- `Stop` cancels polling and any in-flight execution.
- `Listen but not execute commands` keeps polling active but suppresses execution.
- Unauthorized messages are visible in log as ignored, never executed.
- Telegram messages are visible in-tab (incoming + outgoing) in a dedicated timeline.
- Timeline always auto-scrolls to latest message at the bottom when new items arrive.

## 6) Predefined command conversations

### `/help`

```text
User -> /help
Bot  -> Available commands:
        /help - show this help
        /report - app/tabs status snapshot
        /open-directory - open configured subfolder
        /new-task - create task (immediately or queue)

        Example: /new-task
        Then reply with task text and schedule: immediately | queue
```

### `/report`

```text
User -> /report
Bot  -> Open tabs:
        1) Claude | chat  (idle)       ~/projects/app-a
        2) Opencode | chat (processing) ~/projects/app-b
        3) Telegram | bot  (running)    ~/projects/slothy
        Selected directory: ~/projects/slothy
```

### `/open-directory`

```text
User -> /open-directory
Bot  -> Opening predefined folder:
        ~/projects/root/client-app
        Created: Claude Chat tab
```

Invalid path guard:

```text
User -> /open-directory
Bot  -> Cannot open directory: configured subfolder is outside Telegram root.
        Update Telegram settings and try again.
```

### `/new-task`

```text
User -> /new-task
Bot  -> Send task text.

User -> Refactor prompt parser and add tests
Bot  -> When should I start it? Reply: immediately or queue

User -> immediately
Bot  -> Starting task now. I will send report when completed.
```

Queue path:

```text
User -> /new-task
Bot  -> Send task text.

User -> Prepare release notes for next build
Bot  -> When should I start it? Reply: immediately or queue

User -> queue
Bot  -> Added to task queue.
```

## 7) Compact mobile-width fallback (narrow window)

```text
┌───────────────────────────────────────┐
│ Telegram Bot                          │
│ ● Running • Execute                   │
│ Allowed: 123456789                    │
│ [Start] [Stop] [Listen-only]          │
│ Rx 42  Ig 8  Ex 31  Fail 3            │
│---------------------------------------│
│ 22:10 [IN ] review latest PR          │
│ 22:10 [OUT] processing...             │
│ 22:10 [OUT] report sent               │
│ (auto-scrolled to newest)             │
└───────────────────────────────────────┘
```
