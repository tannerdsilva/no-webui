#!/usr/bin/env bash
# designer/smoke.sh — end-to-end deployment smoke gate.
#
# Builds the WebUISmokeTest server, starts it on :9123, then proves the
# design-system assets actually shipped to a browser are lossless:
#   1. the CSS/JS the server exposes are byte-identical to designer/assets/
#   2. the rendered page is self-contained (no external asset refs)
#   3. every visual fix survives into the deployed page
# Exits non-zero on the first failure. Safe to run repeatedly.
#
# Usage: designer/smoke.sh

set -u

cd "$(dirname "$0")/.." || exit 1
PKG_ROOT="$(pwd)"
PORT=9123
BASE="http://127.0.0.1:${PORT}"
WORK="$(mktemp -d)"
SERVER_PID=""

PASS=0
FAIL=0

note() { printf '  %s %s\n' "$1" "$2"; }
ok()   { PASS=$((PASS+1)); note "PASS" "$1"; }
bad()  { FAIL=$((FAIL+1)); note "FAIL" "$1"; }

cleanup() {
  [ -n "${SERVER_PID}" ] && kill "${SERVER_PID}" 2>/dev/null && wait "${SERVER_PID}" 2>/dev/null
  rm -rf "${WORK}"
}
trap cleanup EXIT

echo "=== designer smoke test ==="
echo "building WebUISmokeTest ..."
if ! swift build 2>&1 | tail -3; then
  bad "swift build"
  exit 1
fi
ok "swift build"

BIN="$(swift build --show-bin-path)/WebUISmokeTest"

if lsof -nP -iTCP:${PORT} -sTCP:LISTEN >/dev/null 2>&1; then
  bad "port :${PORT} is already in use — stop the other server (e.g. designer/demo.sh) and re-run"
  exit 1
fi

echo "starting server on :${PORT} ..."
"${BIN}" >"${WORK}/server.log" 2>&1 &
SERVER_PID=$!

ready=0
for _ in $(seq 1 40); do
  if curl -fsS -o /dev/null "${BASE}/" 2>/dev/null; then ready=1; break; fi
  if ! kill -0 "${SERVER_PID}" 2>/dev/null; then break; fi
  sleep 0.25
done
if [ "${ready}" -ne 1 ] || ! kill -0 "${SERVER_PID}" 2>/dev/null; then
  bad "server did not become ready on :${PORT} (see ${WORK}/server.log)"
  cat "${WORK}/server.log" 2>/dev/null | tail -5
  exit 1
fi
ok "server ready (${SERVER_PID})"

echo "--- integrity: served asset bytes vs designer/assets source ---"
curl -fsS "${BASE}/__assets/css" -o "${WORK}/css.served"
curl -fsS "${BASE}/__assets/js"  -o "${WORK}/js.served"
SRC_CSS="${PKG_ROOT}/designer/assets/design-system.css"
SRC_JS="${PKG_ROOT}/designer/assets/webui-runtime.js"

if cmp -s "${SRC_CSS}" "${WORK}/css.served"; then
  ok "css served bytes == source ($(wc -c < "${WORK}/css.served" | tr -d ' ') bytes)"
else
  bad "css served bytes DIFFER from source"
  diff "${SRC_CSS}" "${WORK}/css.served" | head -20
fi

if cmp -s "${SRC_JS}" "${WORK}/js.served"; then
  ok "js served bytes == source ($(wc -c < "${WORK}/js.served" | tr -d ' ') bytes)"
else
  bad "js served bytes DIFFER from source"
  diff "${SRC_JS}" "${WORK}/js.served" | head -20
fi

echo "--- page structure ---"
curl -fsS "${BASE}/" -o "${WORK}/page.html"
PAGE="${WORK}/page.html"

has_sig() {
  local sig="$1" label="$2"
  if grep -qF -- "${sig}" "${PAGE}"; then ok "fix present: ${label}"; else bad "fix MISSING: ${label}"; fi
}
has_sig 'color-mix(in srgb, var(--color-neutral-200) 45%, var(--color-bg))' 'progress groove color'
has_sig 'box-shadow: inset 0 1px 2px rgba(15, 23, 42, 0.12)' 'progress groove inset shadow'
has_sig 'flex-direction: row' 'progress left-anchor (row)'
has_sig 'grid-area: 1 / 1' 'zstack overlap'
has_sig 'align-self: stretch' 'block-component stretch'
has_sig 'margin-top: 1.75rem' 'progress label lane'
has_sig 'role="progressbar"' 'progressbars rendered'
has_sig 'counter-value' 'interactive counter rendered'
has_sig 'echo-out__text' 'live input echo rendered'
has_sig 'button button--primary' 'primary button rendered'

echo "--- self-containment ---"
if grep -qE '<script[^>]+src="http|<link[^>]+href="http' "${PAGE}"; then
  bad "page references external http assets (not self-contained)"
else
  ok "no external http asset references"
fi
if grep -q 'http-equiv="Content-Security-Policy"' "${PAGE}"; then
  ok "CSP meta present"
else
  bad "CSP meta missing"
fi

echo
echo "=== summary: ${PASS} passed, ${FAIL} failed ==="
if [ "${FAIL}" -eq 0 ]; then
  echo "SMOKE PASS"
  exit 0
else
  echo "SMOKE FAIL"
  exit 1
fi
