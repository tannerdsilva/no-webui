#!/usr/bin/env bash
# designer/demo.sh — interactive demo launcher.
#
# Builds the full-stack demo server (if needed), opens it in your default
# browser, and runs the server in the FOREGROUND so you can watch the logs.
# Stop it with Ctrl+C.
#
# This is different from the smoke tests on purpose:
#   smoke tests  -> headless, exit on their own, print PASS/FAIL
#   demo         -> stays running, you open a browser and click around
#
# What you'll see (http://127.0.0.1:9123/):
#   - Counter card: click + / - / Reset. Each click round-trips over the
#     WebSocket to the Swift EventRouter and the DOM patches in place.
#   - Progress card: -10% / +10% re-render the bar server-side.
#   - Echo card: type in the input and watch the text echo back below it.
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

BIN=".build/debug/WebUISmokeTest"
PORT=9123
URL="http://127.0.0.1:${PORT}/"

echo "=== WebUI interactive demo ==="

if [ ! -x "${BIN}" ]; then
  echo "building WebUISmokeTest ..."
  swift build --target WebUISmokeTest
fi

if lsof -nP -iTCP:${PORT} -sTCP:LISTEN >/dev/null 2>&1; then
  echo "port ${PORT} is already in use — is a demo already running?"
  echo "open ${URL} in your browser, or: lsof -nP -iTCP:${PORT} -sTCP:LISTEN"
  exit 1
fi

echo "starting server (Ctrl+C to stop) ..."
"${BIN}" &
SERVER_PID=$!
trap 'kill "${SERVER_PID}" 2>/dev/null || true' INT TERM EXIT

for _ in $(seq 1 40); do
  if curl -fsS -o /dev/null "${URL}" 2>/dev/null; then break; fi
  sleep 0.25
done

echo
echo "  demo:    ${URL}"
echo "  ws:      ws://127.0.0.1:${PORT}/ws"
echo
open "${URL}" 2>/dev/null || echo "(could not auto-open a browser — open ${URL} yourself)"
echo "server running in the background of this shell — Ctrl+C stops it."
wait "${SERVER_PID}"
