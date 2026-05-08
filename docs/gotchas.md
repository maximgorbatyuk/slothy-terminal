# Gotchas

Traps and surprising behaviour that have already burned someone, listed so you don't repeat them. For unresolved product behaviour see `KNOWN_ISSUES.md`.

## Build / project

### `Package.swift` `sources:` list is explicit

The `SlothyTerminalLib` target enumerates every covered file by hand. A new file in `Services/` or `Models/` is invisible to `swift build` and `swift test` until you add it. The file will compile fine in Xcode (which auto-discovers), giving the impression that everything works — but CI, which only runs SPM, will neither build nor test it.

The exclude list mirrors this: anything Sparkle-, AppKit-, or GhosttyKit-bound must stay out of the `sources:` list and (where it lives in a covered subdirectory) appear in the `exclude:` list. See `Package.swift`.

### `GhosttyKit.xcframework` is not committed

A fresh clone cannot open and build the Xcode target. You must build the xcframework from the Ghostty source first. See `docs/release.md` § *Updating Embedded Libghostty*. The xcframework is gitignored on purpose — it is large and built per Ghostty release.

### Xcode project uses `PBXFileSystemSynchronizedRootGroup`

Adding a Swift file under `SlothyTerminal/` requires no `.pbxproj` edits. Conversely, "I added a file but Xcode doesn't see it" almost always means the file lives outside the synchronized root, not that the project is broken.

### `Info.plist` is preprocessed

`INFOPLIST_PREPROCESS = YES` runs `Info.plist` through the C preprocessor at build time. Avoid bare `/* … */` tokens inside the plist. The `DEBUG_BUILD` define switches Finder Services menu titles to `…[DEBUG]` for Debug builds.

### `ATSApplicationFontsPath` must be `"."`, not `"Fonts"`

`PBXFileSystemSynchronizedRootGroup` flattens TTFs under `Resources/Fonts/` into `Contents/Resources/` at build time. Setting `ATSApplicationFontsPath` to `"Fonts"` will silently fail to register bundled fonts and the Appearance picker will fall back to the system font. `AppDelegate.assertBundledFontsRegistered()` traps the silent-failure case at launch.

## Runtime

### Terminal env vars are required

Terminal sessions **must** set `TERM=xterm-256color`, `COLORTERM=truecolor`, `TERM_PROGRAM=SlothyTerminal`, `TERM_PROGRAM_VERSION` before spawning the PTY. Without these, shells launched from the spawned process mishandle escape sequences (cursor, colours, line clearing). The four spawn paths that must set them: `Views/TerminalView.makeLaunchEnvironment()`, `Agents/TerminalAgent.environmentVariables`, `Agents/ClaudeAgent.environmentVariables`, `Agents/OpenCodeAgent.environmentVariables`.

### `sizeDidChange` must only be called from `layout()`

In `Terminal/GhosttySurfaceView.swift`, the libghostty `sizeDidChange` API is sensitive to extra calls during surface creation. Calling it from `createSurface`, `viewDidMoveToWindow`, or `setFrameSize` will duplicate the prompt on startup. Only `layout()` is allowed to call it.

### Claude / OpenCode tabs need a shell host

`AgentType.needsShellHost` is true for `claude` and `opencode`. They are launched under a shell rather than as the PTY's primary process. If the agent exits and there is no shell underneath, the PTY has no leader and the surface freezes. Do not "simplify" by hoisting Claude/OpenCode to be the PTY primary.

### Claude path resolution prefers Mach-O

`Agents/ClaudeAgent.swift` walks a list of common install paths twice — first picking only Mach-O binaries, then any executable. This is deliberate: Node.js wrapper scripts at `/usr/local/bin/claude` work but launch slowly and don't always forward signals correctly. Native installs at `~/.local/bin/claude` are preferred. The user can override with `CLAUDE_PATH`.

### Surface registration is required for injection

Programmatic input (saved prompts, Finder Services drops) goes through `InjectionOrchestrator`. If the surface is not yet registered with `TerminalSurfaceRegistry` when the request arrives, the request fails with `"No surface registered"` rather than queueing forever. Tests in `SlothyTerminalTests/InjectionOrchestratorTests.swift` cover the timing edge cases.

### "Worst wins" on injection status

Once an `InjectionRequest` is `failed` / `timeout` / `cancelled`, a later `completed` from another targeted tab cannot overwrite it. If you change this rule, you will silently lose error visibility on multi-tab broadcasts.

### Resilient config decoding

`AppConfig` decoding tolerates missing keys (e.g. `splitState`, `lastFocusedTabID`, `savedPromptTags` are all `try?`-decoded). Keep this discipline when adding fields. A non-resilient decode will crash existing users on first launch after an update.

## Release

### Run `release.sh` only when both placeholders are real

`scripts/release.sh` greps `appcast.xml` for `SIGNATURE_HERE` and the `[VERSION]` heading in `CHANGELOG.md` before doing anything destructive. Do not pre-fill those placeholders; the script's preflight check is what tells you the entry was forgotten.

### Tag points at `main`, push first

Step 7 of `release.sh` pushes and merges to `main` **before** Step 8 creates the GitHub release. If you reorder these, the tag will land on the previous release's bump commit and Sparkle will serve the wrong binary.

### `SUPublicEDKey` and `SUFeedURL` are load-bearing

Changing `SUPublicEDKey` invalidates auto-update for every existing user. Changing `SUFeedURL` to a path that doesn't serve the appcast does the same. Treat both as immutable.

## Unresolved product behaviour

See `KNOWN_ISSUES.md` for behaviour that is known to be wrong but not yet fixed.
