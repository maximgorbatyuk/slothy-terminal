#!/bin/bash
set -e

source "$(dirname "$0")/lib/colors.sh"

# Update GhosttyKit.xcframework from local Ghostty source
# Usage: ./scripts/update-ghostty.sh [--tag <version>] [--ghostty-dir <path>]
#
# Examples:
#   ./scripts/update-ghostty.sh                        # build from main
#   ./scripts/update-ghostty.sh --tag v1.2.0           # build from a specific tag
#   ./scripts/update-ghostty.sh --ghostty-dir /opt/ghostty

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
GHOSTTY_DIR="${GHOSTTY_DIR:-$HOME/projects/ghostty}"
TAG=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --tag)
      TAG="$2"
      shift 2
      ;;
    --ghostty-dir)
      GHOSTTY_DIR="$2"
      shift 2
      ;;
    -h|--help)
      info "Usage: ./scripts/update-ghostty.sh [OPTIONS]"
      info ""
      info "Options:"
      info "  --tag <version>       Checkout a specific Ghostty tag (e.g. v1.2.0)"
      info "  --ghostty-dir <path>  Path to Ghostty source (default: ~/projects/ghostty)"
      info "  -h, --help            Show this help"
      info ""
      info "Environment variables:"
      info "  GHOSTTY_DIR           Same as --ghostty-dir"
      exit 0
      ;;
    *)
      err "Unknown option: $1"
      info "Run with --help for usage"
      exit 1
      ;;
  esac
done

header "GhosttyKit.xcframework Update"
info "  Ghostty source: $GHOSTTY_DIR"
info "  Target project: $PROJECT_DIR"
if [ -n "$TAG" ]; then
  info "  Checkout tag:   $TAG"
else
  info "  Branch:         main (latest)"
fi

# --- Step 1: Check prerequisites ---

step "[1/6] Checking prerequisites"

if ! command -v zig &>/dev/null; then
  err "zig not found. Install with: brew install zig"
  exit 1
fi
info "  zig: $(zig version)"

if ! command -v xcodebuild &>/dev/null; then
  err "xcodebuild not found. Install Xcode CLI tools: xcode-select --install"
  exit 1
fi
info "  xcodebuild: $(xcodebuild -version | head -1)"

if [ ! -d "$GHOSTTY_DIR" ]; then
  err "Ghostty source not found at $GHOSTTY_DIR"
  info ""
  info "Clone it first:"
  info "  git clone https://github.com/ghostty-org/ghostty.git $GHOSTTY_DIR"
  info ""
  info "Or specify a custom path:"
  info "  ./scripts/update-ghostty.sh --ghostty-dir /path/to/ghostty"
  exit 1
fi

if [ ! -f "$GHOSTTY_DIR/build.zig" ]; then
  err "$GHOSTTY_DIR does not look like a Ghostty repo (no build.zig)"
  exit 1
fi

# --- Step 2: Pull latest Ghostty source ---

step "[2/6] Updating Ghostty source"
cd "$GHOSTTY_DIR"

git fetch --all --tags --force 2>&1 | dim_lines

if [ -n "$TAG" ]; then
  info "  Checking out tag: $TAG"
  git checkout "$TAG" 2>&1 | dim_lines
else
  info "  Checking out main branch..."
  git checkout main 2>&1 | dim_lines
  git pull 2>&1 | dim_lines
fi

GHOSTTY_COMMIT=$(git rev-parse --short HEAD)
GHOSTTY_DESC=$(git describe --tags --always 2>/dev/null || echo "$GHOSTTY_COMMIT")
ok "Ghostty version: $GHOSTTY_DESC ($GHOSTTY_COMMIT)"

# --- Step 3: Build xcframework ---

step "[3/6] Building GhosttyKit.xcframework"
info "  This may take 2-3 minutes..."

cd "$GHOSTTY_DIR"

if ! zig build -Dapp-runtime=none -Demit-xcframework -Dxcframework-target=native 2>&1 | dim_lines; then
  err "BUILD FAILED. Common fixes:"
  info "  - Metal Toolchain: xcodebuild -downloadComponent MetalToolchain"
  info "  - Zig version: check $GHOSTTY_DIR/build.zig.zon for minimum_zig_version"
  info "  - Xcode CLI tools: xcode-select --install"
  exit 1
fi

XCFRAMEWORK_SRC="$GHOSTTY_DIR/macos/GhosttyKit.xcframework"
if [ ! -d "$XCFRAMEWORK_SRC" ]; then
  err "Build succeeded but xcframework not found at $XCFRAMEWORK_SRC"
  exit 1
fi

ok "Build succeeded"

# --- Step 4: Copy xcframework into project ---

step "[4/6] Copying xcframework into project"

XCFRAMEWORK_DST="$PROJECT_DIR/GhosttyKit.xcframework"

if [ -d "$XCFRAMEWORK_DST" ]; then
  rm -rf "$XCFRAMEWORK_DST"
  info "  Removed old xcframework"
fi

cp -R "$XCFRAMEWORK_SRC" "$XCFRAMEWORK_DST"

FRAMEWORK_SIZE=$(du -sh "$XCFRAMEWORK_DST" | cut -f1)
ok "Copied ($FRAMEWORK_SIZE)"

# --- Step 5: Verify builds ---

step "[5/6] Running verification builds"
cd "$PROJECT_DIR"

info "  [5a] SwiftPM build..."
if swift build 2>&1 | dim_lines; then
  ok "SwiftPM build: PASSED"
else
  warn "SwiftPM build: FAILED"
  info "  (This may be unrelated to GhosttyKit — SwiftPM target excludes Ghostty code)"
fi

info "  [5b] Xcode build..."
if xcodebuild -project SlothyTerminal.xcodeproj \
    -scheme SlothyTerminal \
    -configuration Debug \
    build \
    CODE_SIGNING_ALLOWED=NO \
    2>&1 | dim_lines; then
  XCODE_RESULT="PASSED"
else
  XCODE_RESULT="FAILED"
fi

if [ "$XCODE_RESULT" = "PASSED" ]; then
  ok "Xcode build: PASSED"
else
  err "Xcode build: FAILED"
  info ""
  info "  The Xcode build failed — likely due to Ghostty API changes."
  info "  Files to update:"
  info "    - SlothyTerminal/Terminal/GhosttyApp.swift"
  info "    - SlothyTerminal/Terminal/GhosttySurfaceView.swift"
  info ""
  info "  Reference implementation:"
  info "    $GHOSTTY_DIR/macos/Sources/Ghostty/"
  info ""
  info "  See docs/release.md 'Updating Embedded Libghostty' for details."
  exit 1
fi

info "  [5c] SwiftPM tests..."
if swift test 2>&1 | dim_lines; then
  ok "SwiftPM tests: PASSED"
else
  warn "SwiftPM tests: FAILED"
fi

# --- Step 6: Done ---

header "Update Complete"
info "  Ghostty version: $GHOSTTY_DESC ($GHOSTTY_COMMIT)"
info "  xcframework:     $XCFRAMEWORK_DST"
info "  Size:            $FRAMEWORK_SIZE"
info ""
info "  Next steps:"
info "    1. Run the app and smoke test (see docs/release.md)"
info "    2. Commit the update:"
info "       git add GhosttyKit.xcframework SlothyTerminal/Terminal/"
info "       git commit -m \"chore: update GhosttyKit.xcframework to Ghostty $GHOSTTY_DESC\""
