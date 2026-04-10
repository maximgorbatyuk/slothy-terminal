#!/bin/bash
set -e

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
      echo "Usage: ./scripts/update-ghostty.sh [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --tag <version>       Checkout a specific Ghostty tag (e.g. v1.2.0)"
      echo "  --ghostty-dir <path>  Path to Ghostty source (default: ~/projects/ghostty)"
      echo "  -h, --help            Show this help"
      echo ""
      echo "Environment variables:"
      echo "  GHOSTTY_DIR           Same as --ghostty-dir"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Run with --help for usage"
      exit 1
      ;;
  esac
done

echo "==========================================="
echo "  GhosttyKit.xcframework Update"
echo "==========================================="
echo ""
echo "  Ghostty source: $GHOSTTY_DIR"
echo "  Target project: $PROJECT_DIR"
if [ -n "$TAG" ]; then
  echo "  Checkout tag:   $TAG"
else
  echo "  Branch:         main (latest)"
fi
echo ""

# --- Step 1: Check prerequisites ---

echo "[1/6] Checking prerequisites..."

if ! command -v zig &>/dev/null; then
  echo "ERROR: zig not found. Install with: brew install zig"
  exit 1
fi
echo "  zig: $(zig version)"

if ! command -v xcodebuild &>/dev/null; then
  echo "ERROR: xcodebuild not found. Install Xcode CLI tools: xcode-select --install"
  exit 1
fi
echo "  xcodebuild: $(xcodebuild -version | head -1)"

if [ ! -d "$GHOSTTY_DIR" ]; then
  echo ""
  echo "ERROR: Ghostty source not found at $GHOSTTY_DIR"
  echo ""
  echo "Clone it first:"
  echo "  git clone https://github.com/ghostty-org/ghostty.git $GHOSTTY_DIR"
  echo ""
  echo "Or specify a custom path:"
  echo "  ./scripts/update-ghostty.sh --ghostty-dir /path/to/ghostty"
  exit 1
fi

if [ ! -f "$GHOSTTY_DIR/build.zig" ]; then
  echo "ERROR: $GHOSTTY_DIR does not look like a Ghostty repo (no build.zig)"
  exit 1
fi

echo ""

# --- Step 2: Pull latest Ghostty source ---

echo "[2/6] Updating Ghostty source..."
cd "$GHOSTTY_DIR"

git fetch --all --tags --force

if [ -n "$TAG" ]; then
  echo "  Checking out tag: $TAG"
  git checkout "$TAG"
else
  echo "  Checking out main branch..."
  git checkout main
  git pull
fi

GHOSTTY_COMMIT=$(git rev-parse --short HEAD)
GHOSTTY_DESC=$(git describe --tags --always 2>/dev/null || echo "$GHOSTTY_COMMIT")
echo "  Ghostty version: $GHOSTTY_DESC ($GHOSTTY_COMMIT)"
echo ""

# --- Step 3: Build xcframework ---

echo "[3/6] Building GhosttyKit.xcframework..."
echo "  This may take 2-3 minutes..."
echo ""

cd "$GHOSTTY_DIR"

if ! zig build -Dapp-runtime=none -Demit-xcframework -Dxcframework-target=native 2>&1; then
  echo ""
  echo "BUILD FAILED. Common fixes:"
  echo "  - Metal Toolchain: xcodebuild -downloadComponent MetalToolchain"
  echo "  - Zig version: check $GHOSTTY_DIR/build.zig.zon for minimum_zig_version"
  echo "  - Xcode CLI tools: xcode-select --install"
  exit 1
fi

XCFRAMEWORK_SRC="$GHOSTTY_DIR/macos/GhosttyKit.xcframework"
if [ ! -d "$XCFRAMEWORK_SRC" ]; then
  echo "ERROR: Build succeeded but xcframework not found at $XCFRAMEWORK_SRC"
  exit 1
fi

echo ""
echo "  Build succeeded"
echo ""

# --- Step 4: Copy xcframework into project ---

echo "[4/6] Copying xcframework into project..."

XCFRAMEWORK_DST="$PROJECT_DIR/GhosttyKit.xcframework"

if [ -d "$XCFRAMEWORK_DST" ]; then
  rm -rf "$XCFRAMEWORK_DST"
  echo "  Removed old xcframework"
fi

cp -R "$XCFRAMEWORK_SRC" "$XCFRAMEWORK_DST"

FRAMEWORK_SIZE=$(du -sh "$XCFRAMEWORK_DST" | cut -f1)
echo "  Copied ($FRAMEWORK_SIZE)"
echo ""

# --- Step 5: Verify builds ---

echo "[5/6] Running verification builds..."
cd "$PROJECT_DIR"

echo ""
echo "  [5a] SwiftPM build..."
if swift build 2>&1; then
  echo "  SwiftPM build: PASSED"
else
  echo "  SwiftPM build: FAILED"
  echo "  (This may be unrelated to GhosttyKit — SwiftPM target excludes Ghostty code)"
fi

echo ""
echo "  [5b] Xcode build..."
if xcodebuild -project SlothyTerminal.xcodeproj \
    -scheme SlothyTerminal \
    -configuration Debug \
    build \
    CODE_SIGNING_ALLOWED=NO \
    2>&1 | tail -5; then
  XCODE_RESULT="PASSED"
else
  XCODE_RESULT="FAILED"
fi

echo ""
echo "  Xcode build: $XCODE_RESULT"

if [ "$XCODE_RESULT" = "FAILED" ]; then
  echo ""
  echo "  The Xcode build failed — likely due to Ghostty API changes."
  echo "  Files to update:"
  echo "    - SlothyTerminal/Terminal/GhosttyApp.swift"
  echo "    - SlothyTerminal/Terminal/GhosttySurfaceView.swift"
  echo ""
  echo "  Reference implementation:"
  echo "    $GHOSTTY_DIR/macos/Sources/Ghostty/"
  echo ""
  echo "  See docs/RELEASE.md 'Updating Embedded Libghostty' for details."
  exit 1
fi

echo ""
echo "  [5c] SwiftPM tests..."
if swift test 2>&1; then
  echo "  SwiftPM tests: PASSED"
else
  echo "  SwiftPM tests: FAILED"
fi

echo ""

# --- Step 6: Done ---

echo "==========================================="
echo "  Update Complete"
echo "==========================================="
echo ""
echo "  Ghostty version: $GHOSTTY_DESC ($GHOSTTY_COMMIT)"
echo "  xcframework:     $XCFRAMEWORK_DST"
echo "  Size:            $FRAMEWORK_SIZE"
echo ""
echo "  Next steps:"
echo "    1. Run the app and smoke test (see docs/RELEASE.md)"
echo "    2. Commit the update:"
echo "       git add GhosttyKit.xcframework SlothyTerminal/Terminal/"
echo "       git commit -m \"chore: update GhosttyKit.xcframework to Ghostty $GHOSTTY_DESC\""
echo ""
