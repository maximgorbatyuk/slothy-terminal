# Authentication

The app itself has no user account. There is nothing to log into. But three concerns live under the umbrella of "authentication" in this repo:

1. Credentials the app uses to **fetch usage stats** from third-party dashboards (Cursor, Anthropic, OpenAI, OpenCode).
2. The **build-time signing chain** for distribution — Apple notarization and Sparkle EdDSA.
3. Credentials the **user** supplies to the spawned CLIs (Claude CLI, OpenCode CLI). The app does not see or store these.

## 1. Runtime usage credentials

### Where they are stored

`Services/UsageKeychainStore.swift` — wraps the macOS Keychain (`Security` framework) for usage auth material.

- Service name: `com.slothyterminal.usage`
- Account format: `<provider>.<sourceKind>` (e.g. `cursor.apiKey`, `claude.cliOAuth`)
- Item class: `kSecClassGenericPassword`
- Accessibility: `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — the credential is bound to this device and is unavailable while the screen is locked. It is not in any Keychain backup or sync.
- Storage backend: `kSecUseDataProtectionKeychain = true` — the modern, app-bound Keychain partition.

`UsageKeychainStore` exposes `save` / `load` / `delete` (binary `Data` and `String` variants), plus `deleteAll(provider:)` and `deleteAll()` for cleanup.

### How they are obtained

Per-provider strategy lives in the corresponding `*UsageProvider` (e.g. `Services/CursorUsageProvider.swift`). Two general patterns:

- **Auto-detect from another app's state.** The Cursor provider reads the active JWT from Cursor.app's SQLite state DB at `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb` (row `cursorAuth/accessToken`). If Cursor rotates the token, the next read reflects it.
- **Manual paste.** The user pastes a token into Settings; the app stores it in the Keychain via `UsageKeychainStore`.

The resolution order and per-provider details are documented in the comments at the top of each `*UsageProvider` file.

### Where they are used

`Services/UsageService.swift` resolves auth sources, kicks off the fetch loop, and caches per-provider snapshots. It honours the user's `usagePreferences` (fetch enabled, refresh interval). Outbound HTTP details are in `docs/interactions.md`.

### Logging discipline

`UsageKeychainStore` and the providers log via `Logger.usage` (subsystem = bundle identifier, category = `Usage`). Tokens are redacted before logging — `CursorUsageProvider` uses a `redact(_:)` helper that emits a length + sample, never the full JWT. New code that touches credentials must follow the same pattern.

## 2. Build-time signing and notarization

### Apple notarization (Developer ID)

The release scripts use `xcrun notarytool` with a Keychain-stored profile (`AC_PASSWORD` by default in `scripts/build-release.sh`). On first run the script provisions the profile from `.env`:

```
APPLE_ID=…             # Apple ID email
APP_SPECIFIC_PASSWORD=… # generated at appleid.apple.com
TEAM_ID=…              # Apple Developer Team ID
```

`.env` is gitignored. `.env.example` shows the schema. The Team ID currently embedded in the build script is `EKKL63HDHJ` — change this if you fork the project.

The signed `.app` and the DMG are both submitted to notarytool and stapled. Gatekeeper acceptance is verified with `spctl -a -vv` at the end of the build.

### Sparkle EdDSA signing (auto-update)

Sparkle requires every appcast entry to carry an EdDSA signature over the DMG.

- The signing tool `sparkle-tools/bin/sign_update` is downloaded from the Sparkle release tarball (see `docs/release.md` for the one-time setup). It is not in the repo.
- The signing **private key** lives outside the repo. Generate it once with `./sparkle-tools/bin/generate_keys`, then keep the private key safe (out of git, out of CI secrets unless you actually run releases from CI). The corresponding public key is embedded in `Info.plist` as `SUPublicEDKey` and is what Sparkle verifies against on user installs.
- The release script signs the DMG and writes both the `sparkle:edSignature` attribute and the `length` attribute into the appcast entry, replacing the placeholders.

### Trust chain on user devices

At install time, Sparkle:

1. Fetches `appcast.xml` over HTTPS from `SUFeedURL` (raw GitHub URL on `main`).
2. Verifies the new entry's `sparkle:edSignature` against the embedded `SUPublicEDKey`.
3. Downloads the DMG and re-verifies before applying.

If `SUPublicEDKey` ever changes, every existing user's installation breaks updates. Treat both `SUPublicEDKey` and `SUFeedURL` in `Info.plist` as load-bearing.

## 3. Credentials the user supplies to CLIs

`Agents/ClaudeAgent.swift` and `Agents/OpenCodeAgent.swift` resolve and launch external CLIs. The app:

- Forwards `ANTHROPIC_API_KEY` from its own process environment into the spawned Claude CLI, if set.
- Honours `CLAUDE_PATH` and `OPENCODE_PATH` to pin a binary location.
- Does **not** read, store, or log the user's CLI auth tokens. Those live wherever the CLIs put them (typically each CLI's own config dir under `~/.claude/` and `~/.config/opencode/`).

If you change agent launch arguments, prefer the `argsWithPrompt(_:)` discipline (use `--` as a flag terminator, or the agent-specific flag like OpenCode's `--prompt`) so that user-supplied prompt text cannot be misinterpreted as a CLI flag.
