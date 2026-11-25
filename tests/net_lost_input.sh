#!/usr/bin/env bash
# Two-process test of an input that is lost for good. The simulator on the host drops every
# client packet of one short window, so the input of one or two ticks never reaches the host
# (every packet carries the last input_redundancy ticks, so the window must cover that many
# packets). The host test (tests/test_host_lost_input.tscn) checks that the client's bot is
# held back for at most the input allowance (3 * input_redundancy) + a few ticks and then goes on; afterwards the
# client bot's recorded positions are compared with the host's on the ticks that have settled
# after the hole.
# Usage: DROP_MS=140 tests/net_lost_input.sh
#   DROP_MS     window length (default 140: four or five input packets at 30 ticks per second)
#   DROP_AT_MS  window start after the first client packet (default 4500)
#   SETTLE      ticks after the last lost input from which host and client must agree (default 20: the allowance, 12, plus 8)
#   PORT        host port (the simulator uses PORT + 1)
# Exit code 0 = pass, 1 = fail. Never leaves processes running.
set -u

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${PORT:-24993}"
DROP_MS="${DROP_MS:-140}"
DROP_AT_MS="${DROP_AT_MS:-4500}"
SETTLE="${SETTLE:-20}"
TMP="$(mktemp -d)"
PIDS=()
SIM_ARGS=(--sim-drop-ms="$DROP_MS" --sim-hold-at-ms="$DROP_AT_MS")

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

"$GODOT" --headless --path "$ROOT" res://tests/test_host_lost_input.tscn -- --host --port="$PORT" --trace --quit-after=40 "${SIM_ARGS[@]}" >"$TMP/host.log" 2>&1 &
HOST_PID=$!
PIDS+=("$HOST_PID")

for _ in $(seq 1 200); do
	grep -q "^LISTENING" "$TMP/host.log" 2>/dev/null && break
	sleep 0.1
done
if ! grep -q "^LISTENING" "$TMP/host.log"; then
	echo "FAIL: host did not start listening"; cat "$TMP/host.log"; exit 1
fi

"$GODOT" --headless --path "$ROOT" -- --join=127.0.0.1 --port="$PORT" --autopilot --trace --quit-after=14 "${SIM_ARGS[@]}" >"$TMP/client.log" 2>&1 &
CLIENT_PID=$!
PIDS+=("$CLIENT_PID")

wait_exit "$CLIENT_PID" 40 || { echo "FAIL: client did not exit in time"; exit 1; }
wait_exit "$HOST_PID" 60 || { echo "FAIL: host did not exit in time"; tail -20 "$TMP/host.log"; exit 1; }
wait "$HOST_PID"
STATUS=$?

echo "drop: ${DROP_MS} ms window at ${DROP_AT_MS} ms"
grep "^LOST_INPUTS\|^HELD_BACK\|^PASS\|^FAIL" "$TMP/host.log"
python3 -I "$ROOT/tests/trace_diff_report.py" "$TMP/host.log" "$TMP/client.log" | tee "$TMP/trace.txt"

# Host and client must agree again from SETTLE ticks after the last lost input.
LAST_LOST="$(sed -n 's/^LOST_INPUTS ticks=\[\(.*\)\]/\1/p' "$TMP/host.log" | tr -d ' ' | awk -F, '{print $NF}')"
if [ -n "$LAST_LOST" ]; then
	LATE="$(sed -n 's/.*list=\[\(.*\)\]/\1/p' "$TMP/trace.txt" | tr -d ' ' | tr ',' '\n' | awk -v from="$((LAST_LOST + SETTLE))" '$1 != "" && $1 + 0 >= from' | head -3 | tr '\n' ' ')"
	if [ -n "$LATE" ]; then
		echo "FAIL: host and client positions differ at ticks $LATE, more than $SETTLE ticks after the last lost input ($LAST_LOST)"
		STATUS=1
	else
		echo "PASS host and client agree from $SETTLE ticks after the last lost input (tick $LAST_LOST)"
	fi
fi
if grep -q "SCRIPT ERROR" "$TMP/host.log" "$TMP/client.log"; then
	echo "FAIL: script errors in logs"; grep -h "SCRIPT ERROR" "$TMP/host.log" "$TMP/client.log" | head; exit 1
fi
if [ "$STATUS" -ne 0 ] || [ "${KEEP_LOGS:-0}" = "1" ]; then echo "logs kept in $TMP"; trap - EXIT; cleanup; fi
exit "$STATUS"
