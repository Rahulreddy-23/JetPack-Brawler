#!/usr/bin/env bash
# Exports the game pack with the Android preset (which leaves out tests/*), then
# runs that pack headless as a host and checks the host bot spawns. This catches
# gameplay scripts that depend on files the export leaves out, which every run
# from source misses. Exit code 0 = pass. Never leaves processes running.
set -u

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PRESET="${PRESET:-Android Debug}"
TMP="$(mktemp -d)"
PACK="$TMP/game.pck"

"$GODOT" --headless --path "$ROOT" --export-pack "$PRESET" "$PACK" >"$TMP/export.log" 2>&1
if [ ! -s "$PACK" ] || grep -q "SCRIPT ERROR\|Parse Error" "$TMP/export.log"; then
	echo "FAIL: pack export failed"; tail -20 "$TMP/export.log"; exit 1
fi
echo "exported $(wc -c <"$PACK" | tr -d ' ') bytes"

"$GODOT" --headless --main-pack "$PACK" -- --host --port="${PORT:-24996}" --quit-after=3 >"$TMP/run.log" 2>&1 &
PID=$!
trap 'kill "$PID" 2>/dev/null' EXIT
for _ in $(seq 1 150); do
	kill -0 "$PID" 2>/dev/null || break
	sleep 0.1
done
if kill -0 "$PID" 2>/dev/null; then echo "FAIL: exported game did not exit"; exit 1; fi

if grep -q "SCRIPT ERROR\|Parse Error\|^ERROR" "$TMP/run.log"; then
	echo "FAIL: errors when running the exported pack"
	grep -B2 -A3 "SCRIPT ERROR\|Parse Error\|^ERROR" "$TMP/run.log" | head -30
	exit 1
fi
grep -q "^BOT_SPAWNED peer=1" "$TMP/run.log" || { echo "FAIL: the host bot did not spawn"; cat "$TMP/run.log"; exit 1; }
echo "PASS"
