---
name: prepare-macos-release
description: Prepare a SlothyTerminal release by drafting the CHANGELOG.md entry and the appcast.xml <item> template from commits since the last tag. Stops before any destructive action — does not invoke ./scripts/release.sh, does not bump versions, does not push. Use when the user says "prepare a release", "draft the changelog for next release", or "set up the appcast entry for VERSION".
---

# prepare-macos-release

## What this skill does

Prepare the two hand-written artifacts that `./scripts/release.sh` requires to exist before it will run:

1. A `## [VERSION]` block in `CHANGELOG.md` — developer-facing, dense, file:line cited.
2. An `<item>` block in `appcast.xml` — end-user-facing, HTML prose, with the three required placeholders (`BUILD_NUMBER`, `SIGNATURE_HERE`, `FILE_SIZE_IN_BYTES`).

Then **stop** and tell the user the next command to run themselves: `./scripts/release.sh [VERSION]`.

## What this skill must NOT do

- Do **not** run `./scripts/release.sh`, `./scripts/build-release.sh`, or anything that signs / notarizes / pushes / tags. AGENTS.md lists these as requiring explicit confirmation.
- Do **not** edit `project.pbxproj` (`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`) — `release.sh` does that.
- Do **not** fill in the three appcast placeholders (`BUILD_NUMBER`, `SIGNATURE_HERE`, `FILE_SIZE_IN_BYTES`). `release.sh` substitutes them after building, signing, and stat'ing the DMG. Leaving them as literal strings is a precondition the script verifies.
- Do **not** commit. The user reviews both files first; `release.sh` will sweep up uncommitted changes with its own "Commit before release VERSION" step.

## Phase 1 — Determine the version

The skill is invoked as `/prepare-macos-release [VERSION]`. The argument is **optional**.

### Case A: VERSION argument provided (e.g. `/prepare-macos-release 2026.3.10`)

**Use the argument exactly as given. Do NOT guess, do NOT auto-bump, do NOT ask for confirmation.** The user has already chosen the version.

Validate the format only — it must match `YYYY.N.M` (e.g. `2026.3.10`):

```bash
echo "$VERSION" | grep -Eq '^[0-9]{4}\.[0-9]+\.[0-9]+$'
```

If the format is invalid, stop and tell the user. Do not silently "fix" it.

### Case B: no argument provided

Auto-derive the next patch version from `MARKETING_VERSION` in the Xcode project:

```bash
grep -m1 "MARKETING_VERSION" SlothyTerminal.xcodeproj/project.pbxproj | sed 's/.*= \(.*\);/\1/' | tr -d ' '
```

Parse the result as `YYYY.N.M` and increment the last segment by 1:

- `2026.3.9` → `2026.3.10`
- `2026.3.10` → `2026.3.11`
- `2026.4.0` → `2026.4.1`

State the derived version to the user in one line ("Auto-deriving next version: 2026.3.9 → 2026.3.10") and proceed without waiting for confirmation. The user can interrupt if it's wrong.

If the current `MARKETING_VERSION` doesn't match `YYYY.N.M` (e.g. someone set it to `2026.3` or `2026.3.9-beta`), stop and ask the user to pass an explicit version — the auto-bump is only safe for the standard pattern.

### Find the diff range (both cases)

```bash
git tag --list 'v*' --sort=-v:refname | head -1
```

## Phase 2 — Collect the change set

Diff range is `LAST_TAG..HEAD` (e.g. `v2026.3.9..HEAD`). Collect:

```bash
git log v2026.3.9..HEAD --pretty=format:'%h %s' --no-merges
git diff v2026.3.9..HEAD --stat
git diff v2026.3.9..HEAD -- '*.swift' '*.plist' 'Package.swift'
```

Read the actual diff for any file that's substantial (> ~50 lines changed) so the bullet you write reflects the real change, not the commit message. Commit messages in this repo are often one word ("Fix", "+", "Adjustments") and cannot be trusted as a source of truth for the changelog.

## Phase 3 — Draft the CHANGELOG.md entry

Open `CHANGELOG.md` and prepend a new block immediately after the title header (line 4). Section ordering, bottom-to-top: `## [previous]` stays where it is.

### Block structure

```markdown
## [VERSION] - YYYY-MM-DD

### Added
- ...

### Changed
- ...

### Fixed
- ...

### Removed
- ...

### Security
- ...

### Notes
- ...
```

**Only include sections that actually have entries.** Skip empty sections — past releases are inconsistent on this and the inconsistency is fine.

### The voice — match the existing CHANGELOG

Re-read the last 2–3 release blocks in `CHANGELOG.md` before writing. The voice is non-negotiable and very specific:

- **Lead each bullet with a bolded noun phrase** describing the thing that changed. Examples from prior releases:
  - `**Finder Services menu entries: "New SlothyTerminal Tab Here" and "New SlothyTerminal Window Here".**`
  - `**`AppState.createWorkspaceAndTerminalTab(directory:)`**`
  - `**App-wide migration of `.font(...)` call sites to `.appFont(...)`.**`
- **Explain the *why*, not just the *what*.** Cite the prior behaviour, the bug it caused, the alternative considered. Past entries name specific incidents (e.g. "the previous endpoint reports zeros for accounts on Cursor's token-based billing model").
- **End every bullet with file:line citations in parens.** Multiple files separated by commas. Line numbers should be approximate ranges (e.g. `:23-83`) for blocks, single line for a one-liner. Example: `(SlothyTerminal/Info.plist:23-83, SlothyTerminal/Services/FinderServicesProvider.swift)`
- **Bullets are long and dense.** Multi-sentence prose, not telegraph style. A single bullet often runs 4–8 sentences and includes a tradeoff.
- Use backticks for code identifiers, file paths, and config keys.
- Past tense for what changed; present tense for current behaviour.

### What goes in which section

- `### Added` — new files, new types, new public API, new settings, new menu items. The thing didn't exist before this release.
- `### Changed` — existing behaviour now does something different. Always say what it did before.
- `### Fixed` — a bug is resolved. Name the symptom and the root cause.
- `### Removed` — code or features deleted. Say what called sites were updated.
- `### Security` — anything touching credentials, PII, signing, sandbox boundaries.
- `### Notes` — caveats, follow-ups, things future-you needs to know but aren't user-visible behaviour. Often where you put "verified manually with X".

### Test additions

If the diff includes new `*Tests.swift` files, add a bullet under `### Added` for each test file, named in the same style: `**`FooTests`** — unit coverage for X. (`SlothyTerminalTests/FooTests.swift`)`.

## Phase 4 — Draft the appcast.xml `<item>` block

Open `appcast.xml`. The first `<item>` block in the file is the **template comment** (wrapped in `<!-- ... -->`). Real entries start after the closing `-->`. Insert the new entry immediately after `<channel>` opens / before the most recent real `<item>`, so newest is on top — match the existing ordering.

### Required structure (placeholders intact)

```xml
    <item>
      <title>Version VERSION</title>
      <pubDate>RFC822_DATE</pubDate>
      <sparkle:version>BUILD_NUMBER</sparkle:version>
      <sparkle:shortVersionString>VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
      <description><![CDATA[
        <h2>What's New</h2>
        <h3>Section heading</h3>
        <ul>
          <li>Plain-language bullet</li>
        </ul>
      ]]></description>
      <enclosure
        url="https://github.com/maximgorbatyuk/slothy-terminal/releases/download/vVERSION/SlothyTerminal-VERSION.dmg"
        type="application/octet-stream"
        sparkle:edSignature="SIGNATURE_HERE"
        length="FILE_SIZE_IN_BYTES"
      />
    </item>
```

**Substitute only:**
- `VERSION` → the version string (3 places: `<title>`, `<sparkle:shortVersionString>`, two `vVERSION` / `VERSION` substitutions in the `url`).
- `RFC822_DATE` → today's date in RFC 822 format with `+0000` timezone, e.g. `Sat, 02 May 2026 18:00:00 +0000`. Use the user's locale-independent `date` output:

```bash
LC_ALL=C date -u +"%a, %d %b %Y %H:%M:%S +0000"
```

**Leave intact** (the script substitutes these later):
- `BUILD_NUMBER` (literal string — `release.sh` reads `CURRENT_PROJECT_VERSION` and replaces).
- `SIGNATURE_HERE` (literal string — Sparkle EdDSA signature, computed after build).
- `FILE_SIZE_IN_BYTES` (literal string — `stat -f%z` on the DMG, computed after build).

`release.sh` has a preflight check that verifies the entry contains `SIGNATURE_HERE` before running. If you accidentally substitute it, the script will refuse to run.

### The voice — match the existing appcast

Re-read the last 2–3 `<description>` blocks. This voice is **deliberately different** from CHANGELOG:

- **End-user audience.** No file paths, no Swift type names, no `@Observable`, no line numbers.
- **Group with `<h3>` sub-headings** when there's more than one theme. Example past headings: "Open SlothyTerminal from Finder", "App font picker", "Cursor usage".
- **`<ul>` of plain-English bullets**, 1–2 sentences each. Use `<strong>` for UI element names ("the **App Font** section", "right-click → **Services**").
- Skip internal refactors, test additions, dependency bumps, and code-cleanup-only changes. If a CHANGELOG entry has no user-visible effect, it does **not** appear here.
- Skip `### Notes` entirely — those are developer notes.

## Phase 5 — Hand off

After both files are saved, **stop** and tell the user:

1. Review `CHANGELOG.md` and `appcast.xml`.
2. When ready: `./scripts/release.sh VERSION` (the script will commit any pending changes, bump versions, build, sign, notarize, fill in the three placeholders, push, merge to main, and create the GitHub release).

Do not run the script yourself, even if the user seems to want you to — AGENTS.md flags this as needing explicit confirmation, every time.

## Verification before handing off

Before declaring done, run:

```bash
# Real (non-comment) item must contain SIGNATURE_HERE — release.sh's preflight checks this.
awk '/^    <item>/,/<\/item>/' appcast.xml | grep -c SIGNATURE_HERE

# CHANGELOG must contain [VERSION] — release.sh's preflight checks this.
grep -c "\[VERSION\]" CHANGELOG.md
```

Both should be `>= 1`. If either is `0`, the release script will refuse to run — fix before handing off.

## Common mistakes to avoid

- Substituting `BUILD_NUMBER` / `SIGNATURE_HERE` / `FILE_SIZE_IN_BYTES` with real values, or with `0` / empty string. They must remain as the exact literal placeholder strings.
- Writing the CHANGELOG voice in the appcast (file paths, type names) or vice versa.
- Putting the new `<item>` after `</channel>` or inside the template comment block. It must be a sibling of existing real items, newest first.
- Trusting commit subjects as the source of truth — read the diff.
- Leaving past tense / present tense inconsistent within a single bullet.
- Dating the changelog with a future date or a stale date — use today's local date, not the date of the last commit.
