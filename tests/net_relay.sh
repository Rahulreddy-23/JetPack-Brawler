#!/usr/bin/env bash
# Checks that a client cannot send an RPC straight to another client: the host
# relays nothing between clients. A "control" ping from the sender to the host must
# arrive (so the RPC path works), the "direct" ping to the other client must not.
# Exit code 0 = pass. Never leaves processes running.
set -u

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${PORT:-24996}"
TMP="$(mktemp -d)"
PIDS=()

cleanup() {
	for pid in "${PIDS[@]:-}"; do [ -n "$pid" ] && kill "$pid" 2>/dev/null; done
	sleep 0.3
	for pid in "${PIDS[@]:-}"; do [ -n "$pid" ] && kill -9 "$pid" 2>/dev/null; done
}
trap cleanup EXIT

start() { # name, args...
	local name="$1"; shift
	"$GODOT" --headless --path "$ROOT" res://tests/test_relay.tscn -- --port="$PORT" "$@" >"$TMP/$name.log" 2>&1 &
	PIDS+=("$!")
}

start host --role=host --seconds=14
for _ in $(seq 1 200); do grep -q "^LISTENING" "$TMP/host.log" 2>/dev/null && break; sleep 0.1; done
start target --role=target --seconds=12
TARGET_ID=""
for _ in $(seq 1 200); do
	TARGET_ID="$(sed -n 's/^ID //p' "$TMP/target.log" | head -1)"
	[ -n "$TARGET_ID" ] && break; sleep 0.1
done
[ -n "$TARGET_ID" ] || { echo "FAIL: target client never connected"; exit 1; }
start sender --role=sender --target="$TARGET_ID" --seconds=10
sleep 11

grep -q "^GOT control from" "$TMP/host.log" || { echo "FAIL: the control ping did not reach the host (RPC path broken)"; exit 1; }
if grep -q "^GOT direct" "$TMP/target.log"; then echo "FAIL: a client RPC reached another client"; exit 1; fi
echo "PASS"
