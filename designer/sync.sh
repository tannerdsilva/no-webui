#!/usr/bin/env bash
# designer-sync — build, test, and regenerate the showcase from designer/assets/.
#
# Why a script instead of a SwiftPM command plugin:
#   1. `swift package plugin` holds the package .build.lock for the entire
#      invocation, so any nested `swift build` / `swift test` /
#      `swift package ...` deadlocks on flock() of that same lock.
#   2. Command plugins run inside a macOS write-sandbox that can only write
#      to .build/plugins/... — copying the generated page into
#      designer/previews/ fails with EPERM ("Operation not permitted").
#
# This script runs in the shell: no lock nesting, no sandbox.
#
# Usage:
#   designer/sync.sh            # build + test + regenerate showcase
#   designer/sync.sh --no-test  # skip the test suite (quick iteration)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$REPO_ROOT"

run_tests=1
[[ "${1:-}" == "--no-test" ]] && run_tests=0

echo "=== WebUI Designer Sync ==="
echo "  designer/assets/ is the canonical source of truth — the build plugin"
echo "  reads from it directly. No copy step needed."
echo ""

echo "  Building..."
swift build

if [[ "$run_tests" -eq 1 ]]; then
  echo ""
  echo "  Testing..."
  swift test
fi

echo ""
echo "  Regenerating showcase → designer/previews/showcase.html ..."
.build/debug/WebUIShowcase --generate "$SCRIPT_DIR/previews/showcase.html"

echo ""
echo "=== Sync complete ==="
