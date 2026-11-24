#!/usr/bin/env bash
# Two-process network smoke test on one machine. Starts a headless host and a
# headless client (127.0.0.1) that plays a fixed scripted input sequence, then
# compares the client bot's per-tick positions as recorded by each process, on
# ticks where both sides used the same input and the client's value came from
# a re-simulation of one step from a state received from the host.
# Usage: tests/net_smoke.sh       (set GODOT=/path/to/Godot to override)
# Exit code 0 = pass, 1 = fail, 2 = inconclusive (a stall was seen or too few
# ticks were comparable; this is NOT a pass). Never leaves processes running.
set -u

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${PORT:-24999}"
TMP="$(mktemp -d)"
PIDS=()

cleanup() {
	for pid in "${PIDS[@]:-}"; do
		[ -n "$pid" ] && kill "$pid" 2>/dev/null
	done
	sleep 0.3
	for pid in "${PIDS[@]:-}"; do
		[ -n "$pid" ] && kill -9 "$pid" 2>/dev/null
	done
}
trap cleanup EXIT

# Wait up to $2 seconds for process $1 to exit. Returns 1 on timeout.
wait_exit() {
	local pid="$1" limit=$(( $2 * 10 )) i=0
	while kill -0 "$pid" 2>/dev/null; do
		i=$(( i + 1 ))
		[ "$i" -ge "$limit" ] && return 1
		sleep 0.1
	done
	return 0
}

"$GODOT" --headless --path "$ROOT" -- --host --port="$PORT" --trace --quit-after=16 >"$TMP/host.log" 2>&1 &
HOST_PID=$!
PIDS+=("$HOST_PID")

for _ in $(seq 1 200); do
	grep -q "^LISTENING" "$TMP/host.log" 2>/dev/null && break
	sleep 0.1
done
if ! grep -q "^LISTENING" "$TMP/host.log"; then
	echo "FAIL: host did not start listening"; cat "$TMP/host.log"; exit 1
fi

"$GODOT" --headless --path "$ROOT" -- --join=127.0.0.1 --port="$PORT" --autopilot --trace --quit-after=12 >"$TMP/client.log" 2>&1 &
CLIENT_PID=$!
PIDS+=("$CLIENT_PID")

wait_exit "$CLIENT_PID" 40 || { echo "FAIL: client did not exit in time"; exit 1; }
wait_exit "$HOST_PID" 40 || { echo "FAIL: host did not exit in time"; exit 1; }

echo "--- client final ---"; grep "^FINAL" "$TMP/client.log"
echo "--- host final ---";   grep "^FINAL" "$TMP/host.log"

echo "--- how far ahead of its own tick each side received snapshots ---"; grep -h "^LEAD" "$TMP/host.log" "$TMP/client.log"
echo "--- measured clock sync ---"; grep -h "^CLOCK" "$TMP/host.log" "$TMP/client.log"

# Errors in either log fail the test (netfox warnings are allowed).
if grep -q "SCRIPT ERROR\|^ERROR" "$TMP/host.log" "$TMP/client.log"; then
	echo "FAIL: errors in logs"; grep -h "SCRIPT ERROR\|^ERROR" "$TMP/host.log" "$TMP/client.log" | head; exit 1
fi

# Compare the client bot (every peer id except the host's 1) tick by tick, only
# on ticks where the comparison is meaningful. See compare_traces.py.
python3 -I "$ROOT/tests/compare_traces.py" "$TMP/host.log" "$TMP/client.log"
STATUS=$?
if [ "$STATUS" -ne 0 ]; then echo "logs kept in $TMP"; trap - EXIT; cleanup; fi
exit "$STATUS"
