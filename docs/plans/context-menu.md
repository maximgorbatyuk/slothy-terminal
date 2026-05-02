# Finder Context Menu — "New SlothyTerminal Tab/Window Here"

## Goal

Add SlothyTerminal entries to Finder's right-click → **Services** submenu, mirroring Ghostty's "New Tab/Window Here" behavior. Selecting a folder in Finder and choosing one of these items should launch (or focus) SlothyTerminal and open a `.terminal` tab rooted at that folder.

## Background

macOS **Services** are system-wide actions any app can register. They appear in the Services submenu when right-clicking on Finder items whose type matches the service's declared `NSSendTypes`. The OS launches the target app if needed and routes the selection (folder URLs) through the pasteboard to a designated `@objc` method on the app's `servicesProvider`.

Three pieces are required:
1. `NSServices` array in `Info.plist` — declares the menu items, accepted types, and selector names.
2. A handler object exposing matching `@objc` methods, registered via `NSApp.servicesProvider`.
3. App-side dispatch from the handler into existing `AppState` APIs.

## Plan Fixes / Corrections (incorporated below)

The previous draft had eight gaps. Each is corrected inline in the relevant section, and summarized here for traceability:

1. **Cold-launch reliability** — Services callbacks can fire before SwiftUI's `.onReceive` is attached. Fixed in §3 and §5 with a pending-request queue on `AppDelegate` that flushes once `AppState` registers as ready.
2. **`NSPortName`** — must align with the actual built `CFBundleName` from Xcode build settings, **not** the runtime `BuildConfig.appName` (which only drives in-app text). Fixed in §1 + §1a.
3. **Selector signature** — macOS Services require an exact Objective-C selector shape; mismatches fail silently. Fixed in §2 with explicit selector contract.
4. **Wiring location wording** — corrected to `SlothyTerminalApp` scene (the `WindowGroup` modifiers in `SlothyTerminalApp.swift`), not "MainView scene". Fixed in §5.
5. **Multi-selection behavior** — explicitly defined in §2a.
6. **Verification scope** — split into warm vs cold launch, Debug vs Release titles, and per-action Finder checks. Fixed in §6.
7. **Test scope** — added unit tests for `createWorkspaceAndTerminalTab` and pasteboard failure paths. Added in §7.
8. **Final-bundle Info.plist verification** — added `plutil -p` step against the built `.app` to confirm preprocessor output. Added in §1a + §6.

## Confirmed requirements

1. **"New SlothyTerminal Tab Here"** → add a `.terminal` tab to the **currently active workspace**. The folder is the tab's working directory; the workspace's own root stays untouched. Existing `AppState.createTab(agent: .terminal, directory: folder)` already does this — it routes through `resolveWorkspaceID`, which prefers the active workspace.
2. **"New SlothyTerminal Window Here"** → create a **brand-new workspace** rooted at the folder, switch to it, and open a `.terminal` tab inside it. If the app isn't running, macOS launches it automatically (standard Services behavior). Needs a new helper because `resolveWorkspaceID` can dedupe / re-use an existing workspace with the same root directory — undesired here.
3. **Menu titles**: `"New SlothyTerminal Tab Here"` / `"New SlothyTerminal Window Here"`, with ` [DEBUG]` suffix in Debug builds (the user-facing title in Finder's Services submenu).

## Implementation plan

### 1. `SlothyTerminal/Info.plist` — add `NSServices`

Two service entries, each declaring:

- `NSMenuItem` → `{ default = "<title>"; }` — the title shown in Finder's Services menu (preprocessor-driven, see below).
- `NSMessage` — selector base name **without** `:` and without arguments. Use `newTabHere` and `newWindowHere`. macOS will look up `<NSMessage>:userData:error:` on the `servicesProvider` (see §2 for the exact selector contract).
- `NSPortName` — see §1a. Must match the **built** `CFBundleName`, which is set by Xcode build settings (`PRODUCT_NAME` / `INFOPLIST_KEY_CFBundleName`), not by `BuildConfig.appName`.
- `NSSendTypes = ["public.folder"]` — items only appear when a folder is selected.
- `NSRequiredContext = { NSTextContent = FilePath; }` — restricts to file-based contexts.

Preprocessor-driven title (avoids two-plist swap):

```xml
#ifdef DEBUG
<string>New SlothyTerminal Tab Here [DEBUG]</string>
#else
<string>New SlothyTerminal Tab Here</string>
#endif
```

(Same pattern for the Window entry.)

This requires the Xcode build-setting changes listed in §8.

### 1a. `NSPortName` — must match built `CFBundleName`

- **Do not** wire `NSPortName` to `BuildConfig.appName`. `BuildConfig` is loaded at runtime from `Config.{debug,release}.json` and only governs in-app strings. macOS reads `NSPortName` from the **static, built** `Info.plist` and matches it against `CFBundleName`.
- Inspect the built bundle to capture the canonical name:
  ```bash
  plutil -p "$(xcodebuild -project SlothyTerminal.xcodeproj -scheme SlothyTerminal -configuration Debug -showBuildSettings | awk -F'= ' '/ BUILT_PRODUCTS_DIR /{p=$2} /^ *FULL_PRODUCT_NAME /{f=$2} END{print p"/"f}')/Contents/Info.plist" | grep -E 'CFBundleName|NSPortName|NSServices'
  ```
- Use the **same literal value** for `NSPortName` that ends up in the built `CFBundleName` for each configuration. If Debug and Release produce different `CFBundleName` values (e.g., "Slothy Terminal Dev" vs "Slothy Terminal"), gate `NSPortName` with the same `#ifdef DEBUG` block as the title:

```xml
<key>NSPortName</key>
#ifdef DEBUG
<string>Slothy Terminal Dev</string>
#else
<string>Slothy Terminal</string>
#endif
```

- After every build, re-run the `plutil -p` check to confirm `CFBundleName == NSPortName` for each entry. Mismatch ⇒ Services registration silently fails.

### 2. New file `SlothyTerminal/Services/FinderServicesProvider.swift` (app-only, NOT in `Package.swift`)

**Selector contract — must match exactly or macOS silently drops the invocation:**

- Objective-C selector: `<NSMessage>:userData:error:` — three parameters, in that order, with those exact keywords.
- Parameter types: `(NSPasteboard *, NSString *, NSString **)`.
- The Swift signature below produces that selector. Verify with `#selector(...)` and a unit test that asserts `provider.responds(to: #selector(...))`.
- Method must be `@objc` and the class must inherit from `NSObject`.

```swift
final class FinderServicesProvider: NSObject {
  /// Selector: newTabHere:userData:error:
  @objc func newTabHere(
    _ pboard: NSPasteboard,
    userData: String,
    error: AutoreleasingUnsafeMutablePointer<NSString>
  ) {
    guard let folder = firstFolder(from: pboard) else {
      setError("No folder selected", error)
      return
    }

    ServiceRequestQueue.shared.dispatchOrQueue(.newTab(folder: folder))
    NSApp.activate(ignoringOtherApps: true)
  }

  /// Selector: newWindowHere:userData:error:
  @objc func newWindowHere(
    _ pboard: NSPasteboard,
    userData: String,
    error: AutoreleasingUnsafeMutablePointer<NSString>
  ) {
    guard let folder = firstFolder(from: pboard) else {
      setError("No folder selected", error)
      return
    }

    ServiceRequestQueue.shared.dispatchOrQueue(.newWindow(folder: folder))
    NSApp.activate(ignoringOtherApps: true)
  }

  // Helpers:
  // - firstFolder(from:) reads NSURL list from pboard via
  //   readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]),
  //   then picks the first entry whose URL is a directory per FileManager.isDirectory.
  //   See §2a for multi-selection rationale.
  // - setError(_:_:) writes an NSLocalizedString message into the error out-pointer;
  //   macOS may surface it in the user-facing Services error.
}
```

### 2a. Multi-selection behavior (explicit)

When Finder sends multiple folders on the pasteboard, **process only the first folder** (pasteboard order — i.e., the order Finder placed the URLs in the pasteboard, which mirrors selection order) and ignore the rest. Rationale:

- Matches Ghostty's behavior and avoids spawning N tabs/workspaces from a single click.
- Predictable result for the user; no surprise burst of tabs.
- Non-folder entries in a mixed selection are filtered out before picking the first folder.
- If the pasteboard contains zero folders, return an error via the `error` out-pointer; do nothing.

### 3. `AppDelegate` — provider lifecycle + cold-launch queue

Two additions:

1. **Strong-ref the provider and register it.** In `applicationWillFinishLaunching(_:)` (earlier than `didFinishLaunching` so the provider is in place before any queued service invocation runs):
   ```swift
   self.servicesProvider = FinderServicesProvider()
   NSApp.servicesProvider = self.servicesProvider
   NSUpdateDynamicServices()
   ```
2. **Pending-request queue.** Services callbacks can fire before SwiftUI attaches its `.onReceive` modifiers — especially on cold launch when macOS invokes the service moments after launching the app. Queue requests until the SwiftUI side signals readiness:

   ```swift
   /// Single-instance request queue; flushes when AppState registers as ready.
   final class ServiceRequestQueue {
     static let shared = ServiceRequestQueue()

     enum Request { case newTab(folder: URL); case newWindow(folder: URL) }

     private var pending: [Request] = []
     private var sink: ((Request) -> Void)?
     private let lock = NSLock()

     func dispatchOrQueue(_ request: Request) {
       lock.lock(); defer { lock.unlock() }
       if let sink {
         DispatchQueue.main.async { sink(request) }
       } else {
         pending.append(request)
       }
     }

     /// Called by SlothyTerminalApp once AppState's .onReceive handlers are attached.
     func attach(_ sink: @escaping (Request) -> Void) {
       lock.lock()
       let drained = pending; pending.removeAll(); self.sink = sink
       lock.unlock()
       DispatchQueue.main.async { drained.forEach { sink($0) } }
     }
   }
   ```

   The provider's `@objc` selectors call `ServiceRequestQueue.shared.dispatchOrQueue(...)` (see §2). The SwiftUI scene attaches the sink in §5.

### 4. `AppState` — add one method

```swift
/// Creates a brand-new workspace and a .terminal tab in it.
/// Used by the "New Window Here" Finder service — always creates a fresh
/// workspace, bypassing the dedupe logic in resolveWorkspaceID.
func createWorkspaceAndTerminalTab(directory: URL) {
  let workspace = createWorkspace(from: directory)  // already switches to it
  let tab = Tab(
    workspaceID: workspace.id,
    agentType: .terminal,
    workingDirectory: directory
  )
  tabs.append(tab)
  switchToTab(id: tab.id)
}
```

### 5. `SlothyTerminalApp` — scene-level wiring (not MainView)

Wire at the **app scene** in `SlothyTerminalApp.swift` (the same location that already handles `.newTabRequested` / `.openFolderRequested`), not inside `MainView`. The scene-level `.onAppear` is the trigger to attach the sink to the cold-launch queue.

- Add `Notification.Name.openFolderInNewWorkspaceRequested` to AppDelegate's existing `Notification.Name` extension (kept for symmetry / scriptable triggers, but the cold-launch path uses `ServiceRequestQueue` directly).
- Inside the `WindowGroup`'s root view modifiers in `SlothyTerminalApp.body`:
  ```swift
  .onAppear {
    ServiceRequestQueue.shared.attach { request in
      switch request {
      case .newTab(let folder):
        appState.createTab(agent: .terminal, directory: folder)
      case .newWindow(let folder):
        appState.createWorkspaceAndTerminalTab(directory: folder)
      }
    }
  }
  ```
- Keep the existing `.onReceive(.openFolderRequested)` handler as-is. Any pending requests received before `.onAppear` fires are drained synchronously on attach.

### 6. Verification

**Build verification:**
- `swift build` and `swift test` — provider/queue are AppKit-only, kept out of `Package.swift`; SPM target unaffected.
- `xcodebuild -project SlothyTerminal.xcodeproj -scheme SlothyTerminal -configuration Debug build CODE_SIGNING_ALLOWED=NO`.
- `xcodebuild ... -configuration Release build CODE_SIGNING_ALLOWED=NO`.
- After each build, run the `plutil -p` snippet from §1a and confirm:
  - `CFBundleName` matches `NSPortName` for both service entries.
  - `NSMenuItem.default` has the `[DEBUG]` suffix in Debug, no suffix in Release.
  - `NSMessage` values are exactly `newTabHere` and `newWindowHere`.

**Functional verification — both must pass:**

| Case | Steps | Expected |
|---|---|---|
| Warm launch — New Tab Here | App already running with an active workspace. Right-click a folder in Finder → Services → "New SlothyTerminal Tab Here". | `.terminal` tab appended to active workspace, working directory = folder. Active workspace's root unchanged. App focused. |
| Warm launch — New Window Here | App running. Right-click a folder → "New SlothyTerminal Window Here". | New workspace created (rootDirectory = folder), switched to. New `.terminal` tab in it. Even if a workspace with the same rootDirectory already existed, a fresh one is created. |
| Cold launch — New Tab Here | Quit the app. Right-click a folder → "New SlothyTerminal Tab Here". | App launches, the queued request flushes after scene attach, a `.terminal` tab opens in the (newly created) workspace. No lost requests. |
| Cold launch — New Window Here | Quit the app. Right-click a folder → "New SlothyTerminal Window Here". | App launches, fresh workspace + `.terminal` tab appears. |
| Multi-selection | Select two folders in Finder, right-click → "New SlothyTerminal Tab Here". | Exactly **one** tab opens, rooted at the first folder per §2a. No extra tabs. |
| Non-folder selection | Select a file (not a folder), right-click. | The two SlothyTerminal items do **not** appear in the Services submenu (filtered by `NSSendTypes = public.folder`). |
| Debug title | Run Debug build; right-click a folder → Services. | Entries read "New SlothyTerminal Tab Here [DEBUG]" / "New SlothyTerminal Window Here [DEBUG]". |
| Release title | Run Release build; right-click a folder → Services. | Entries read "New SlothyTerminal Tab Here" / "New SlothyTerminal Window Here". |

If items don't appear at all after a fresh install:
- Run `/System/Library/CoreServices/pbs -dump_pboard | grep -i slothy` to confirm registration.
- Run `NSUpdateDynamicServices()` (already called in `applicationWillFinishLaunching`) — log out / log in if necessary; macOS caches Service registrations aggressively.

### 7. Tests

Added to `SlothyTerminalTests/` (auto-discovered):

- **`AppStateWorkspaceTests.createWorkspaceAndTerminalTab_alwaysCreatesFreshWorkspace`** — given an existing workspace with `rootDirectory == /tmp/x`, calling `createWorkspaceAndTerminalTab(directory: /tmp/x)` produces **two** workspaces with that root, the second is active, and the new `.terminal` tab belongs to the new workspace.
- **`AppStateWorkspaceTests.createWorkspaceAndTerminalTab_emptyState`** — from zero workspaces, the call yields one workspace + one tab; active IDs match.
- **`AppStateWorkspaceTests.createWorkspaceAndTerminalTab_doesNotMutateExistingWorkspaces`** — pre-existing workspaces and their tabs are unchanged.
- **`FinderServicesProviderTests.respondsToServiceSelectors`** — `provider.responds(to: Selector("newTabHere:userData:error:"))` and `Selector("newWindowHere:userData:error:")` both true. Guards against accidental signature drift.
- **`FinderServicesProviderTests.emptyPasteboard_setsErrorAndQueuesNothing`** — pass a pasteboard with no URLs; `error` out-string is set; `ServiceRequestQueue.shared` has zero pending requests after the call.
- **`FinderServicesProviderTests.nonFolderPasteboard_setsErrorAndQueuesNothing`** — pasteboard with a regular file URL; same expectation.
- **`FinderServicesProviderTests.multiSelection_pickFirstFolder`** — pasteboard with `[fileA.txt, /tmp/folder1, /tmp/folder2]`; queue receives exactly one `newTab(/tmp/folder1)` request.
- **`ServiceRequestQueueTests.dispatchBeforeAttach_queuesAndDrainsOnAttach`** — call `dispatchOrQueue` before `attach`; sink receives all pending requests in order after `attach`.
- **`ServiceRequestQueueTests.dispatchAfterAttach_routesImmediately`** — after `attach`, requests bypass the queue.

`FinderServicesProvider` and `ServiceRequestQueue` are AppKit-only — keep them in the Xcode-only target. If unit-testing them via SwiftPM is impractical (NSPasteboard requires AppKit), put these tests in the Xcode test target. `AppState` tests already live in the SwiftPM test target and stay there.

### 8. Xcode build-setting changes (`project.pbxproj`)

- `INFOPLIST_PREPROCESS = YES` (Debug + Release).
- `INFOPLIST_PREPROCESSOR_DEFINITIONS = DEBUG=1` (Debug only).
- Confirm `INFOPLIST_KEY_CFBundleName` (or `PRODUCT_NAME` if it drives `CFBundleName`) values for each configuration so they match the literal `NSPortName` strings written in `Info.plist` (§1a).

## What will NOT change

- `Package.swift` — `FinderServicesProvider` and `ServiceRequestQueue` are AppKit-only (`NSPasteboard`, `NSApp`); stay out of SPM.
- Existing `createTab`, `resolveWorkspaceID`, workspace dedupe logic, and the `.openFolderRequested` notification path — all reused as-is.
- Code signing, sandboxing, entitlements (the app is unsandboxed; Services need no special entitlement).
- Build/release scripts (`build-release.sh`, `release.sh`) — Info.plist preprocessing is a project-level Xcode setting, not a script change.
- No new agent types, no in-app UI changes, no in-app menu changes.

## Pre-implementation checkpoint

Confirm the `.pbxproj` edits in §8 are acceptable. Once acknowledged, implementation can proceed without further checkpoints.

## Done when

- [ ] `Info.plist` has both `NSServices` entries with correct `NSMessage`, `NSPortName`, `NSSendTypes`, `NSRequiredContext`.
- [ ] Preprocessor produces ` [DEBUG]` suffix in Debug, no suffix in Release; verified via `plutil -p` on built bundle.
- [ ] `CFBundleName == NSPortName` for both configurations; verified on built bundle.
- [ ] `FinderServicesProvider` registered via `NSApp.servicesProvider` in `applicationWillFinishLaunching`.
- [ ] `ServiceRequestQueue` queues cold-launch requests and flushes after scene attach.
- [ ] `AppState.createWorkspaceAndTerminalTab(directory:)` implemented and unit-tested.
- [ ] Wiring added at app scene in `SlothyTerminalApp.swift` (not in `MainView`).
- [ ] All unit tests in §7 pass; `swift test` green.
- [ ] All 8 functional cases in §6's verification table pass on a clean build.
- [ ] Multi-selection opens exactly one tab/workspace per §2a.
- [ ] Non-folder selections do not show the SlothyTerminal items in Services.
