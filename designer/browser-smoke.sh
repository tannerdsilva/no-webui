#!/usr/bin/env bash
# designer/browser-smoke.sh — browser-level deployment smoke gate.
#
# Wraps designer/browser-smoke.mjs. Requires node + playwright on PATH
# (playwright's Chromium is expected to be installed: npx playwright install).
# Builds the WebUISmokeTest server, loads the deployed page in headless
# Chromium, and asserts the real-layout invariants (left-anchored fills,
# label placement, self-containment, no console errors). Writes a screenshot
# to .smoke/browser.png. Exits non-zero on failure.

set -u
cd "$(dirname "$0")" || exit 1
exec node browser-smoke.mjs "$@"
