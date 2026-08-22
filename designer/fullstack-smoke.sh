#!/usr/bin/env bash
# designer/fullstack-smoke.sh — full-stack deployment smoke gate.
#
# The "full" smoke test: builds and DEPLOYS the real stack (NIO HTTP + WebSocket
# upgrade + Swift EventRouter + interactive WebUI views), then drives live
# events over a real WebSocket and asserts the server patches the DOM via
# FragmentUpdate. Proves the whole event stack deploys and works end-to-end.
#
# Exits non-zero on the first failure. Safe to run repeatedly (kills its own
# server on the way out).
#
# Usage: designer/fullstack-smoke.sh

set -u

cd "$(dirname "$0")/.." || exit 1
PORT=9123
BASE="http://127.0.0.1:${PORT}"
BIN=""

PASS=0
FAIL=0
ok() { PASS=$((PASS+1)); printf '  PASS %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }

cleanup() {
  [ -n "${BIN}" ] && kill "${BIN}" 2>/dev/null
  wait 2>/dev/null
}
trap cleanup EXIT

echo "=== full-stack smoke test ==="
echo "building WebUISmokeTest ..."
BUILD_OUT="$(swift build --target WebUISmokeTest 2>&1)"
BUILD_RC=$?
if [ "${BUILD_RC}" -ne 0 ]; then
  printf '%s\n' "${BUILD_OUT}" | tail -20
  bad "swift build WebUISmokeTest"
  exit 1
fi
ok "swift build WebUISmokeTest"

BINPATH="$(swift build --show-bin-path)/WebUISmokeTest"
if lsof -nP -iTCP:${PORT} -sTCP:LISTEN >/dev/null 2>&1; then
  bad "port :${PORT} is already in use — stop the other server (e.g. designer/demo.sh) and re-run"
  exit 1
fi
"${BINPATH}" >/tmp/webui-fullstack-server.log 2>&1 &
BIN=$!

ready=0
for _ in $(seq 1 60); do
  if curl -fsS -o /dev/null "${BASE}/" 2>/dev/null; then ready=1; break; fi
  if ! kill -0 "${BIN}" 2>/dev/null; then break; fi
  sleep 0.25
done
if [ "${ready}" -ne 1 ] || ! kill -0 "${BIN}" 2>/dev/null; then
  bad "server did not become ready on :${PORT} (see /tmp/webui-fullstack-server.log)"
  tail -5 /tmp/webui-fullstack-server.log 2>/dev/null
  exit 1
fi
ok "full-stack server ready (${BIN})"

echo "--- live deployment: page + WS round-trips ---"
if node "$(dirname "$0")/fullstack-smoke.mjs"; then
  ok "fullstack-smoke.mjs (WS handshake + event round-trips)"
else
  bad "fullstack-smoke.mjs reported failures"
fi

echo
echo "=== summary: ${PASS} passed, ${FAIL} failed ==="
if [ "${FAIL}" -eq 0 ]; then
  echo "FULL-STACK SMOKE PASS"
  exit 0
else
  echo "FULL-STACK SMOKE FAIL"
  exit 1
fi
