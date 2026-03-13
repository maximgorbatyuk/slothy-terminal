# Make Commit Git Tab Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build the `Make Commit` Git sub-tab with scoped staged and unstaged file management, side-by-side diff review, commit and amend support, push support, and new-branch creation.

**Architecture:** Add a SwiftPM-testable Git working-tree layer for parsing and command orchestration, then replace the existing Git commit stub with a dedicated app-only `MakeCommitView`. Keep repo stats code unchanged where possible, but extend git process execution so mutation flows can surface stderr and exit status to the UI.

**Tech Stack:** Swift 5.9, SwiftUI, Swift Testing, git CLI, Xcode project auto-discovery, SwiftPM core target

---

### Task 1: Add working-tree models and scoped status parsing

**Files:**
- Create: `SlothyTerminal/Models/GitWorkingTreeModels.swift`
- Create: `SlothyTerminalTests/GitWorkingTreeServiceTests.swift`
- Modify: `SlothyTerminal/Services/GitWorkingTreeService.swift`
- Modify: `Package.swift`

**Step 1: Write the failing tests**

Create `SlothyTerminalTests/GitWorkingTreeServiceTests.swift` with parsing tests that cover:

```swift
import Foundation
import Testing

@testable import SlothyTerminalLib

@Suite("Git Working Tree")
struct GitWorkingTreeServiceTests {
  private let service = GitWorkingTreeService.shared

  @Test("Status parsing keeps staged and unstaged columns separate")
  func parseDualColumnStatus() {
    let output = """
    MM Sources/App.swift
    A  Sources/NewFile.swift
     D Sources/OldFile.swift
    ?? Sources/Scratch.swift
    M  README.md
    """

    let snapshot = service.parseStatusOutput(
      output,
      scopePath: "Sources"
    )

    #expect(snapshot.changes.count == 4)

    let app = #require(snapshot.changes.first { $0.repoRelativePath == "Sources/App.swift" })
    #expect(app.indexStatus == .modified)
    #expect(app.workTreeStatus == .modified)
    #expect(app.hasStagedEntry)
    #expect(app.hasUnstagedEntry)

    let scratch = #require(snapshot.changes.first { $0.repoRelativePath == "Sources/Scratch.swift" })
    #expect(scratch.isUntracked)
    #expect(scratch.hasUnstagedEntry)
    #expect(!scratch.hasStagedEntry)
  }

  @Test("Status parsing keeps staged paths outside scope out of the visible snapshot")
  func parseScopeFiltering() {
    let output = """
    M  Sources/App.swift
    M  README.md
    """

    let snapshot = service.parseStatusOutput(output, scopePath: "Sources")

    #expect(snapshot.changes.count == 1)
    #expect(snapshot.changes[0].repoRelativePath == "Sources/App.swift")
    #expect(snapshot.hasStagedChangesOutsideScope)
  }
}
```

**Step 2: Run the tests to verify they fail**

Run: `swift test --filter GitWorkingTreeServiceTests`

Expected: FAIL because `GitWorkingTreeService` and the working-tree models do not exist yet.

**Step 3: Write the minimal model and parser implementation**

Create `SlothyTerminal/Models/GitWorkingTreeModels.swift` with:

- a status enum that can represent the porcelain columns cleanly
- `GitScopedChange`
- `GitWorkingTreeSnapshot`
- a small entry enum or section enum to distinguish `.staged` and `.unstaged`

Add `SlothyTerminal/Services/GitWorkingTreeService.swift` with:

- `parseStatusOutput(_ output: String, scopePath: String?) -> GitWorkingTreeSnapshot`
- dual-column parsing for index and worktree state
- rename target-path handling for `old -> new`
- scope filtering relative to the repo root
- `hasStagedChangesOutsideScope` detection derived from the full output

Use a model shape similar to:

```swift
enum GitStatusColumn: Character {
  case unmodified = " "
  case modified = "M"
  case added = "A"
  case deleted = "D"
  case renamed = "R"
  case copied = "C"
  case untracked = "?"
  case unmerged = "U"
}

struct GitScopedChange: Identifiable {
  let repoRelativePath: String
  let displayPath: String
  let indexStatus: GitStatusColumn
  let workTreeStatus: GitStatusColumn

  var hasStagedEntry: Bool { indexStatus != .unmodified && indexStatus != .untracked }
  var hasUnstagedEntry: Bool { workTreeStatus != .unmodified || workTreeStatus == .untracked }
  var isUntracked: Bool { indexStatus == .untracked || workTreeStatus == .untracked }
}
```

**Step 4: Add new core files to SwiftPM**

Update `Package.swift` to include:

- `Models/GitWorkingTreeModels.swift`
- `Services/GitWorkingTreeService.swift`

**Step 5: Run the tests again**

Run: `swift test --filter GitWorkingTreeServiceTests`

Expected: PASS.

**Step 6: Commit**

```bash
git add Package.swift SlothyTerminal/Models/GitWorkingTreeModels.swift SlothyTerminal/Services/GitWorkingTreeService.swift SlothyTerminalTests/GitWorkingTreeServiceTests.swift
git commit -m "feat: add git working tree status models"
```

### Task 2: Add structured git command results and mutation helpers

**Files:**
- Modify: `SlothyTerminal/Services/GitProcessRunner.swift`
- Modify: `SlothyTerminal/Services/GitWorkingTreeService.swift`
- Modify: `SlothyTerminalTests/GitWorkingTreeServiceTests.swift`

**Step 1: Write the failing tests**

Add tests for command selection and message handling:

```swift
@Test("Push uses set-upstream when no upstream exists")
func pushArgumentsWithoutUpstream() {
  let arguments = GitWorkingTreeService.shared.pushArguments(
    currentBranch: "feature/make-commit",
    upstreamBranch: nil
  )

  #expect(arguments == ["push", "--set-upstream", "origin", "feature/make-commit"])
}

@Test("Push uses plain push when upstream exists")
func pushArgumentsWithUpstream() {
  let arguments = GitWorkingTreeService.shared.pushArguments(
    currentBranch: "feature/make-commit",
    upstreamBranch: "origin/feature/make-commit"
  )

  #expect(arguments == ["push"])
}
```

**Step 2: Run the tests to verify they fail**

Run: `swift test --filter GitWorkingTreeServiceTests`

Expected: FAIL because the push helper does not exist yet.

**Step 3: Extend the git runner without breaking stats callers**

Modify `GitProcessRunner.swift` to keep the existing simple `run` helper and add a second path that returns structured data:

```swift
struct GitProcessResult {
  let stdout: String
  let stderr: String
  let terminationStatus: Int32

  var isSuccess: Bool { terminationStatus == 0 }
}
```

Add a new async function that captures both stdout and stderr and returns `GitProcessResult`.

Do not remove the old helper yet; existing read-only callers can keep using it.

**Step 4: Add command-building and mutation helpers**

Add to `GitWorkingTreeService.swift`:

- `pushArguments(currentBranch:upstreamBranch:)`
- `getLastCommitMessage(in:)`
- `stageFile(path:in:)`
- `unstageFile(path:in:)`
- `discardTrackedChanges(path:in:)`
- `discardStagedChanges(path:in:)`
- `push(in:)`
- `createAndSwitchBranch(named:in:)`

Use the structured runner for mutation paths so stderr can be surfaced directly to the UI.

**Step 5: Run the tests again**

Run: `swift test --filter GitWorkingTreeServiceTests`

Expected: PASS.

**Step 6: Commit**

```bash
git add SlothyTerminal/Services/GitProcessRunner.swift SlothyTerminal/Services/GitWorkingTreeService.swift SlothyTerminalTests/GitWorkingTreeServiceTests.swift
git commit -m "feat: add git mutation helpers for make commit tab"
```

### Task 3: Add side-by-side diff parsing

**Files:**
- Create: `SlothyTerminal/Models/GitDiffModels.swift`
- Create: `SlothyTerminalTests/GitDiffParserTests.swift`
- Modify: `SlothyTerminal/Services/GitWorkingTreeService.swift`
- Modify: `Package.swift`

**Step 1: Write the failing tests**

Create `SlothyTerminalTests/GitDiffParserTests.swift` with coverage for:

```swift
import Testing

@testable import SlothyTerminalLib

@Suite("Git Diff Parser")
struct GitDiffParserTests {
  private let service = GitWorkingTreeService.shared

  @Test("Unified diff parses into side-by-side rows")
  func parseUnifiedDiff() {
    let diff = """
    @@ -1,3 +1,3 @@
     line 1
    -old value
    +new value
     line 3
    """

    let rows = service.parseUnifiedDiff(diff)

    #expect(rows.count == 3)
    #expect(rows[1].oldLineNumber == 2)
    #expect(rows[1].newLineNumber == 2)
    #expect(rows[1].leftText == "old value")
    #expect(rows[1].rightText == "new value")
    #expect(rows[1].kind == .modification)
  }

  @Test("Binary diff returns non-text placeholder state")
  func parseBinaryDiff() {
    let diff = "Binary files a/logo.png and b/logo.png differ"
    let result = service.parseDiffOutput(diff)

    #expect(result.isBinary)
    #expect(result.rows.isEmpty)
  }
}
```

**Step 2: Run the tests to verify they fail**

Run: `swift test --filter GitDiffParserTests`

Expected: FAIL because the diff models and parser do not exist yet.

**Step 3: Write the minimal diff models and parser**

Create `SlothyTerminal/Models/GitDiffModels.swift` with:

- `GitDiffRowKind`
- `GitDiffRow`
- `GitDiffDocument`

Add to `GitWorkingTreeService.swift`:

- `parseUnifiedDiff(_:)`
- `parseDiffOutput(_:)`
- `loadDiff(for:path:in:)`

Implementation rule:

- parse unified diff hunks
- keep running old and new line numbers
- align deletions on the left and additions on the right
- group consecutive deletions and additions into paired rows when possible
- surface binary diff as a special state instead of trying to render text rows

**Step 4: Add new core file to SwiftPM**

Update `Package.swift` to include `Models/GitDiffModels.swift`.

**Step 5: Run the tests again**

Run: `swift test --filter GitDiffParserTests`

Expected: PASS.

**Step 6: Commit**

```bash
git add Package.swift SlothyTerminal/Models/GitDiffModels.swift SlothyTerminal/Services/GitWorkingTreeService.swift SlothyTerminalTests/GitDiffParserTests.swift
git commit -m "feat: add git diff parsing for side-by-side view"
```

### Task 4: Route the Git client to a real Make Commit view

**Files:**
- Create: `SlothyTerminal/Views/MakeCommitView.swift`
- Modify: `SlothyTerminal/Views/GitClientView.swift`
- Modify: `SlothyTerminal/Models/GitTab.swift`

**Step 1: Write the failing integration expectation**

Define the routing target:

- `.commit` in `GitClientView.repoContent` should instantiate `MakeCommitView`
- `GitTab.isStub` should return `false` for `.commit`

**Step 2: Create the minimal view shell**

Create `SlothyTerminal/Views/MakeCommitView.swift` with:

- `let workingDirectory: URL`
- `@State` for snapshot, selection, branch name, commit message, last operation, loading, and confirmation dialog state
- a top-level `body` composed of:
  - header toolbar
  - split main content
  - composer footer

Keep this first pass visual only. Use placeholder empty states and wire `.task` to load status.

**Step 3: Replace the stub route**

Modify `GitClientView.swift`:

```swift
case .commit:
  MakeCommitView(workingDirectory: workingDirectory)
```

Modify `GitTab.swift` so `.commit` is no longer treated as a stub.

**Step 4: Build the app**

Run:

```bash
xcodebuild -project SlothyTerminal.xcodeproj -scheme SlothyTerminal -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Expected: PASS.

**Step 5: Commit**

```bash
git add SlothyTerminal/Views/MakeCommitView.swift SlothyTerminal/Views/GitClientView.swift SlothyTerminal/Models/GitTab.swift
git commit -m "feat: route git commit tab to make commit view"
```

### Task 5: Implement staged and unstaged lists plus diff loading

**Files:**
- Modify: `SlothyTerminal/Views/MakeCommitView.swift`
- Modify: `SlothyTerminal/Services/GitWorkingTreeService.swift`
- Modify: `SlothyTerminal/Models/GitWorkingTreeModels.swift`

**Step 1: Render the two change sections**

In `MakeCommitView.swift`, build:

- `stagedSection`
- `unstagedSection`
- reusable `changeRow(for:section:)`

Each row should show:

- status badge
- filename
- relative display path if needed
- action button for stage or unstage

Selection should be keyed by both path and section so the diff pane knows whether to request staged or unstaged diff.

**Step 2: Load diffs for the selected row**

When selection changes:

- call `loadDiff(for:path:in:)`
- update the right-side panel with `GitDiffDocument`
- show explicit fallback for empty or binary diff

**Step 3: Refresh after mutations**

After stage or unstage:

- reload the status snapshot
- preserve selection when the file still exists in the selected section
- otherwise move selection to the matching path in the other section or clear it

**Step 4: Build and test**

Run:

```bash
swift test --filter GitWorkingTreeServiceTests
swift test --filter GitDiffParserTests
xcodebuild -project SlothyTerminal.xcodeproj -scheme SlothyTerminal -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Expected: PASS.

**Step 5: Commit**

```bash
git add SlothyTerminal/Views/MakeCommitView.swift SlothyTerminal/Services/GitWorkingTreeService.swift SlothyTerminal/Models/GitWorkingTreeModels.swift
git commit -m "feat: add staged and unstaged change lists"
```

### Task 6: Implement destructive actions, commit, amend, push, and branch creation

**Files:**
- Modify: `SlothyTerminal/Views/MakeCommitView.swift`
- Modify: `SlothyTerminal/Services/GitWorkingTreeService.swift`
- Modify: `SlothyTerminalTests/GitWorkingTreeServiceTests.swift`

**Step 1: Add failing tests for commit guards and branch validation**

Extend `GitWorkingTreeServiceTests.swift` with:

```swift
@Test("Commit is blocked when staged changes exist outside scope")
func commitBlockedOutsideScope() {
  let snapshot = GitWorkingTreeSnapshot(
    changes: [],
    hasStagedChangesOutsideScope: true
  )

  #expect(snapshot.canCommit(message: "Ship it") == false)
}

@Test("Branch names must not be blank")
func blankBranchNameIsInvalid() {
  #expect(GitWorkingTreeService.shared.isValidBranchName("") == false)
  #expect(GitWorkingTreeService.shared.isValidBranchName("   ") == false)
}
```

**Step 2: Run the tests to verify they fail**

Run: `swift test --filter GitWorkingTreeServiceTests`

Expected: FAIL because the helpers do not exist yet.

**Step 3: Add commit and amend workflow logic**

In `MakeCommitView.swift`:

- add a multiline text editor for the commit message
- add `Amend last commit` toggle
- when the toggle turns on, fetch and preload the last commit message once
- disable commit when:
  - there are no staged entries in scope
  - the message is blank
  - an operation is running
  - `hasStagedChangesOutsideScope` is true

When the commit action runs:

- use `git commit -m <message>` for normal commit
- use `git commit --amend -m <message>` for amend
- refresh the snapshot, branch state, and diff
- clear message state after successful normal commit

**Step 4: Add push and new-branch workflows**

In `MakeCommitView.swift`:

- add `Push` button with async action
- detect upstream and choose the correct push command
- add `New Branch` sheet or inline popover
- validate non-empty branch name before calling the service
- on success, refresh branch badge and status

**Step 5: Add destructive confirmations**

Add confirmation dialogs for:

- tracked discard
- staged discard to `HEAD`
- untracked delete from disk

The dialog body must name the path being changed or deleted.

**Step 6: Run verification**

Run:

```bash
swift test --filter GitWorkingTreeServiceTests
xcodebuild -project SlothyTerminal.xcodeproj -scheme SlothyTerminal -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Expected: PASS.

**Step 7: Commit**

```bash
git add SlothyTerminal/Views/MakeCommitView.swift SlothyTerminal/Services/GitWorkingTreeService.swift SlothyTerminalTests/GitWorkingTreeServiceTests.swift
git commit -m "feat: add commit actions to git make commit tab"
```

### Task 7: Manual QA and final verification

**Files:**
- Modify: `KNOWN_ISSUES.md` (only if a new limitation is discovered)
- Optional: `README.md` (only if the Git tab behavior should be documented)

**Step 1: Prepare a temporary repository**

Run a manual QA setup in a disposable directory:

```bash
mkdir -p /tmp/slothy-git-tab-qa/repo/Subdir
cd /tmp/slothy-git-tab-qa/repo
git init
printf "one\ntwo\nthree\n" > Subdir/demo.txt
git add .
git commit -m "Initial commit"
printf "one\nTWO\nthree\n" > Subdir/demo.txt
printf "temp\n" > Subdir/untracked.txt
git add Subdir/demo.txt
printf "one\nTWO\nTHREE\n" > Subdir/demo.txt
```
Expected state:

- `Subdir/demo.txt` appears in both staged and unstaged sections
- `Subdir/untracked.txt` appears in unstaged

**Step 2: Verify the UI flows manually**

Check:

- stage and unstage update the correct section
- selected diff switches between staged and unstaged versions
- tracked discard restores file content
- untracked delete removes the file from disk
- amend preloads the last commit message
- push without upstream chooses `origin/<branch>`
- new branch switches immediately

**Step 3: Run final automated verification**

Run:

```bash
swift test
xcodebuild -project SlothyTerminal.xcodeproj -scheme SlothyTerminal -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Expected: PASS.

**Step 4: Capture any residual risk**

If binary diffs, rename diffs, or partial staging limitations remain awkward, document them in `KNOWN_ISSUES.md` rather than silently shipping surprising behavior.

**Step 5: Commit**

```bash
git add KNOWN_ISSUES.md README.md
git commit -m "docs: note git make commit tab limitations"
```
