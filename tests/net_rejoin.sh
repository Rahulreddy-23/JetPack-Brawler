#!/usr/bin/env bash
# Leave-and-start-again checks:
#  1. a client joins a host, leaves, joins the same host again; its bot must
#     spawn both times;
#  2. a host starts, leaves, starts again; its bot must spawn both times.
# Exit code 0 = pass. Fails on any SCRIPT ERROR. Never leaves processes running.
set -u

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${PORT:-24997}"
TMP="$(mktemp -d)"
PIDS=()

cleanup() {
	for pid in "${PIDS[@]:-}"; do [ -n "$pid" ] && kill "$pid" 2>/dev/null; done
	sleep 0.3
	for pid in "${PIDS[@]:-}"; do [ -n "$pid" ] && kill -9 "$pid" 2>/dev/null; done
}
trap cleanup EXIT

check_log() { # name
	if grep -q "SCRIPT ERROR\|^ERROR" "$TMP/$1.log"; then
		echo "FAIL: errors in $1 log"; grep -h "SCRIPT ERROR\|^ERROR" "$TMP/$1.log" | head; exit 1
	fi
}

"$GODOT" --headless --path "$ROOT" -- --host --port="$PORT" --quit-after=60 >"$TMP/host.log" 2>&1 &
PIDS+=("$!")
for _ in $(seq 1 200); do grep -q "^LISTENING" "$TMP/host.log" 2>/dev/null && break; sleep 0.1; done

"$GODOT" --headless --path "$ROOT" res://tests/test_rejoin.tscn -- --mode=client --address=127.0.0.1 --port="$PORT" >"$TMP/client.log" 2>&1
CLIENT_STATUS=$?
grep "^PASS\|^FAIL" "$TMP/client.log"
check_log client
[ "$CLIENT_STATUS" -eq 0 ] || { echo "FAIL: client leave-and-rejoin"; exit 1; }

"$GODOT" --headless --path "$ROOT" res://tests/test_rejoin.tscn -- --mode=host --port="$((PORT + 1))" >"$TMP/host2.log" 2>&1
HOST_STATUS=$?
grep "^PASS\|^FAIL" "$TMP/host2.log"
check_log host2
[ "$HOST_STATUS" -eq 0 ] || { echo "FAIL: host leave-and-host-again"; exit 1; }
check_log host
echo "PASS"
