# Make Commit Git Tab Design

## Goal

Build a native `Make Commit` sub-tab inside the Git client that lets the user review and manipulate repository changes without leaving SlothyTerminal.

The tab must support:

- separate staged and unstaged change lists
- staging and unstaging files
- discarding tracked changes
- deleting untracked files from disk
- side-by-side diff review with red removed lines and green added lines
- committing staged changes with a custom message
- amending the last commit with a prefilled editable message
- pushing the current branch
- creating a new branch and switching to it immediately

## Product Decisions

- `Push` should run plain `git push` when the current branch already has an upstream.
- `Push` should run `git push --set-upstream origin <current-branch>` when no upstream exists.
- Discarding an untracked file should delete it from disk after confirmation.
- `Amend last commit` should prefill the composer with the last commit message and keep it editable.
- If the Git tab was opened from a subdirectory inside the repository, the `Make Commit` tab should only show and act on files under that subdirectory.

## Current Constraints

- [GitClientView.swift](/Users/maximgorbatyuk/projects/macos/SlothyTerminal/SlothyTerminal/Views/GitClientView.swift) currently routes `.commit` to `GitStubContentView`.
- [GitTab.swift](/Users/maximgorbatyuk/projects/macos/SlothyTerminal/SlothyTerminal/Models/GitTab.swift) already exposes the `Make Commit` sub-tab label and icon.
- [GitService.swift](/Users/maximgorbatyuk/projects/macos/SlothyTerminal/SlothyTerminal/Services/GitService.swift) currently flattens `git status --porcelain` into a single status per file, which is insufficient for a file that has both staged and unstaged changes.
- [GitProcessRunner.swift](/Users/maximgorbatyuk/projects/macos/SlothyTerminal/SlothyTerminal/Services/GitProcessRunner.swift) discards stderr and only returns stdout, which is acceptable for read-only stats but not for user-facing commit, push, or branch errors.
- `Package.swift` uses an explicit `sources:` list, so any new SwiftPM-covered models or services must be added manually.

## Recommended Approach

Implement a dedicated working-tree layer and keep the SwiftUI tab thin.

The implementation should introduce:

- a richer Git working-tree model that preserves index and worktree status separately
- a `GitWorkingTreeService` responsible for status, diff, stage, unstage, discard, commit, amend, push, and branch creation
- a structured git process result that captures stdout, stderr, and exit status for operations that need user-visible failures
- an app-only `MakeCommitView` that renders the split lists, side-by-side diff, composer, and confirmation flows

This approach matches the existing Git client architecture:

- service and parsing logic remain SwiftPM-testable
- SwiftUI stays in app-only files
- `GitClientView` remains the routing point for Git sub-tabs instead of absorbing repository mutation logic

## UX Design

### Layout

The `Make Commit` sub-tab should have three regions:

1. Header toolbar
2. Main content split into file lists and diff viewer
3. Footer commit composer

### Header Toolbar

The header should show:

- repository or scoped subdirectory label
- current branch badge
- refresh action
- `New Branch` action
- `Push` action
- inline last-operation feedback

### Change Lists

The left side should render two separate cards:

- `Staged`
- `Unstaged`

Each row should show:

- status badge
- filename
- relative path when needed for disambiguation
- trailing action button:
  - `Stage` in the unstaged section
  - `Unstage` in the staged section

A file may appear in both cards when it has both index and worktree changes.

Selecting a row should bind the diff pane to the exact row the user clicked:

- selecting an unstaged row shows the unstaged diff
- selecting a staged row shows the staged diff

### Context Menus

Unstaged tracked rows:

- `Discard Changes…`

Untracked rows:

- `Delete File…`

Staged rows:

- `Discard All Changes…`

Each destructive action must show confirmation first.

### Diff Viewer

The right side should render a side-by-side diff for the selected change.

Visual rules:

- removed lines on the left with red styling
- added lines on the right with green styling
- unchanged context lines aligned across both columns
- binary or unsupported diffs show a non-crashing fallback message

### Commit Composer

The footer should include:

- multiline commit message editor
- `Amend last commit` toggle
- `Commit` button

Behavior:

- toggling amend on loads the last commit message into the editor
- the message stays editable
- the commit button is disabled when the message is blank, nothing is staged in scope, a mutation is running, or staged changes exist outside the visible scope

## Scope Rules

The Git client tab is scoped to the directory it was opened from, not always the repository root.

Status and diff operations must therefore be path-limited to that subdirectory.

Commit and amend are different: Git commits all currently staged changes in the repository. To keep the UX honest, the tab must detect staged changes outside the opened subdirectory and block `Commit` and `Amend` until the repository is safe for a scoped commit.

Recommended behavior:

- show a blocking warning banner when staged changes exist outside scope
- keep `Push`, `Refresh`, and `New Branch` available, because they are repo-wide operations

## Service Design

### Working Tree Models

Add a testable model set that can answer:

- what repository-relative path changed
- how the index column is marked
- how the worktree column is marked
- whether the file contributes a staged entry
- whether the file contributes an unstaged entry
- whether the file is untracked, renamed, deleted, or conflicted

The current `GitModifiedFile` type can remain for older sidebar-style usage if needed, but `Make Commit` should not rely on that flattened model.

### Git Process Results

Keep the existing simple stdout helper for stats calls, but add a structured runner path for mutation and error-reporting flows.

That result should include:

- trimmed stdout
- trimmed stderr
- termination status

This prevents the UI from collapsing all Git failures into a generic nil state.

### Working Tree Service Responsibilities

`GitWorkingTreeService` should own:

- repository root and scope resolution
- scoped status loading
- staged-outside-scope detection
- selected-file diff loading
- stage and unstage mutations
- discard and delete mutations
- last commit message lookup
- commit and amend execution
- upstream detection and push
- branch creation and branch switch

## Git Command Mapping

Recommended commands:

- scoped status: `git status --porcelain=v1 --untracked-files=all -- <scope>`
- staged diff: `git diff --cached -- <path>`
- unstaged diff: `git diff -- <path>`
- stage file: `git add -- <path>`
- unstage file: `git restore --staged -- <path>`
- discard tracked unstaged changes: `git restore -- <path>`
- discard staged tracked changes back to `HEAD`: `git restore --staged --worktree --source=HEAD -- <path>`
- last commit message: `git log -1 --pretty=%B`
- current upstream: `git rev-parse --abbrev-ref --symbolic-full-name @{u}`
- push with upstream: `git push --set-upstream origin <branch>`
- new branch and switch: `git switch -c <branch-name>`

For staged-outside-scope detection, the simplest reliable option is:

- list staged paths repo-wide
- compare them to the current scope path
- if any staged path falls outside scope, block commit and amend

## Risks

### Scoped commit safety

Git itself does not provide a subdirectory-only commit primitive once unrelated files are already staged. The UI guard is required to avoid misleading users into committing hidden changes.

### Diff complexity

Git emits unified diff, not pre-paired side-by-side rows. A dedicated parser is needed to convert hunks into row pairs for rendering.

### Destructive deletes

Deleting untracked files from disk is irreversible inside the app. Confirmation text must be explicit and path-specific.

### Error quality

Push, amend, and branch creation can fail for many normal reasons such as authentication, branch conflicts, or detached HEAD. The UI must surface stderr text clearly.

## Testing Strategy

SwiftPM-covered unit tests should validate:

- porcelain parsing into scoped staged and unstaged entries
- rename, delete, and untracked handling
- staged-outside-scope detection
- push command selection with and without upstream
- amend message loading
- unified diff parsing into side-by-side rows

App-only verification should cover:

- selection and refresh behavior in the view
- context menu confirmation flows
- disabled-state logic for commit and amend
- diff updates after stage, unstage, discard, commit, amend, push, and branch creation

## Rollout

1. Add the testable working-tree models and service.
2. Extend git process execution so stderr reaches the UI.
3. Replace the Git commit stub with a real `MakeCommitView`.
4. Add manual QA against a temporary repository with mixed staged and unstaged files, an untracked file, an amend flow, and a no-upstream push flow.
