#!/usr/bin/env bash
# `make dev`: build the debug app, launch it, and stream its logs here. Ctrl-C quits Clippy.
#
# Clippy is launched through LaunchServices (`open`), not by running the binary directly.
# Run directly, the terminal app (e.g. VS Code) becomes Clippy's "responsible process", and
# macOS then checks the TERMINAL's Accessibility permission, so pasting silently fails.
set -euo pipefail
cd "$(dirname "$0")/.."

pkill -x Clippy 2>/dev/null || true
scripts/build-app.sh debug

LOG="$PWD/build/dev.log"
: > "$LOG"
open -n -W --stdout "$LOG" --stderr "$LOG" build/debug/Clippy.app &
OPEN_PID=$!
tail -n +1 -f "$LOG" &
TAIL_PID=$!

cleanup() { pkill -x Clippy 2>/dev/null || true; kill "$TAIL_PID" "$OPEN_PID" 2>/dev/null || true; }
trap 'cleanup; exit 0' INT TERM
echo "==> Clippy running (logs below, Ctrl-C to quit)"
wait "$OPEN_PID" || true
kill "$TAIL_PID" 2>/dev/null || true
