#!/usr/bin/env bash
# Two-process test with diff states switched on in the host process. The host runs
# tests/test_host_diffs.tscn, which checks how often each bot, the client's included,
# gets a full state; the client is a headless autopilot client.
# Usage: tests/net_diffs.sh   (set GODOT=/path/to/Godot to override)
# Exit code 0 = pass, 1 = fail. Never leaves processes running.
set -u

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${PORT:-24995}"
TMP="$(mktemp -d)"
PIDS=()

cleanup() {
	for pid in "${PIDS[@]:-}"; do
		[ -n "$pid" ] && kill "$pid" 2>/dev/null
	done
	sleep 0.3
	for pid in "${PIDS[@]:-}"; do
		[ -n "$pid" ] && kill -9 "$pid" 2>/dev/null
		[ -n "$pid" ] && wait "$pid" 2>/dev/null
	done
}
trap cleanup EXIT

wait_exit() {
	local pid="$1" limit=$(( $2 * 10 )) i=0
	while kill -0 "$pid" 2>/dev/null; do
		i=$(( i + 1 ))
		[ "$i" -ge "$limit" ] && return 1
		sleep 0.1
	done
	return 0
}

"$GODOT" --headless --path "$ROOT" res://tests/test_host_diffs.tscn -- --host --port="$PORT" --quit-after=40 >"$TMP/host.log" 2>&1 &
HOST_PID=$!
PIDS+=("$HOST_PID")

for _ in $(seq 1 200); do
	grep -q "^LISTENING" "$TMP/host.log" 2>/dev/null && break
	sleep 0.1
done
if ! grep -q "^LISTENING" "$TMP/host.log"; then
	echo "FAIL: host did not start listening"; cat "$TMP/host.log"; exit 1
fi

"$GODOT" --headless --path "$ROOT" -- --join=127.0.0.1 --port="$PORT" --autopilot --quit-after=14 >"$TMP/client.log" 2>&1 &
CLIENT_PID=$!
PIDS+=("$CLIENT_PID")

wait_exit "$CLIENT_PID" 40 || { echo "FAIL: client did not exit in time"; exit 1; }
wait_exit "$HOST_PID" 60 || { echo "FAIL: host did not exit in time"; tail -20 "$TMP/host.log"; exit 1; }
wait "$HOST_PID"
STATUS=$?

grep "^PASS\|^FAIL\|failures" "$TMP/host.log"
if grep -q "SCRIPT ERROR" "$TMP/host.log" "$TMP/client.log"; then
	echo "FAIL: script errors in logs"; grep -h "SCRIPT ERROR" "$TMP/host.log" "$TMP/client.log" | head; exit 1
fi
if [ "$STATUS" -ne 0 ]; then echo "FAIL: host test exit $STATUS"; echo "logs kept in $TMP"; trap - EXIT; cleanup; fi
exit "$STATUS"
