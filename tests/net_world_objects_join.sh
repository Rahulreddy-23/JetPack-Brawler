#!/usr/bin/env bash
# A phone that joins while a Spring Plate is already on the map must get it. A headless host
# (tests/test_net_join.tscn) tosses a plate with its own bot; once the host log says so, a
# headless joiner connects (both through the latency proxy, which listens on PORT + 1) and
# prints what it sees of the plate slot. The test passes when the joiner sees the plate
# active, landed, and equal to the host's view in every field.
# Usage: PORT=26044 SIM_LATENCY_MS=75 tests/net_world_objects_join.sh
# Exit code 0 = pass, 1 = fail. Never leaves processes running.
set -u

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${PORT:-24997}"
LATENCY="${SIM_LATENCY_MS:-75}"
TMP="$(mktemp -d)"
PIDS=()

cleanup() {
	for pid in "${PIDS[@]:-}"; do [ -n "$pid" ] && kill "$pid" 2>/dev/null; done
	sleep 0.3
	for pid in "${PIDS[@]:-}"; do [ -n "$pid" ] && kill -9 "$pid" 2>/dev/null; done
}
trap cleanup EXIT

keep_logs() {
	echo "logs kept in $TMP"
	trap - EXIT
	cleanup
}

wait_exit() {
	local pid="$1" limit=$(( $2 * 10 )) i=0
	while kill -0 "$pid" 2>/dev/null; do
		i=$(( i + 1 ))
		[ "$i" -ge "$limit" ] && return 1
		sleep 0.1
	done
	return 0
}

"$GODOT" --headless --path "$ROOT" res://tests/test_net_join.tscn -- --host --port="$PORT" --sim-latency-ms="$LATENCY" >"$TMP/host.log" 2>&1 &
HOST_PID=$!
PIDS+=("$HOST_PID")
for _ in $(seq 1 200); do grep -q "^LISTENING" "$TMP/host.log" 2>/dev/null && break; sleep 0.1; done
if ! grep -q "^LISTENING" "$TMP/host.log"; then echo "FAIL: host did not start listening"; cat "$TMP/host.log"; exit 1; fi
for _ in $(seq 1 300); do grep -q "^PLATE_THROWN" "$TMP/host.log" 2>/dev/null && break; sleep 0.1; done
if ! grep -q "^PLATE_THROWN" "$TMP/host.log"; then echo "FAIL: the host never threw the plate"; tail -5 "$TMP/host.log"; keep_logs; exit 1; fi

"$GODOT" --headless --path "$ROOT" res://tests/test_net_join.tscn -- --join=127.0.0.1 --port="$PORT" --sim-latency-ms="$LATENCY" >"$TMP/joiner.log" 2>&1 &
JOINER_PID=$!
PIDS+=("$JOINER_PID")

wait_exit "$JOINER_PID" 50 || { echo "FAIL: joiner did not exit in time"; tail -5 "$TMP/joiner.log"; keep_logs; exit 1; }
wait_exit "$HOST_PID" 30 || { echo "FAIL: host did not exit in time"; tail -5 "$TMP/host.log"; keep_logs; exit 1; }

grep -h "^JOINRESULT" "$TMP/host.log" "$TMP/joiner.log"
if grep -q "SCRIPT ERROR\|^ERROR\|^FAIL" "$TMP/host.log" "$TMP/joiner.log"; then
	echo "FAIL: errors in logs"; grep -h "SCRIPT ERROR\|^ERROR\|^FAIL" "$TMP/host.log" "$TMP/joiner.log" | head; keep_logs; exit 1
fi
if grep -q "Refusing identity packet" "$TMP/host.log" "$TMP/joiner.log"; then
	echo "FAIL: an identity packet was refused"; grep -h "Refusing identity packet" "$TMP/host.log" "$TMP/joiner.log" | head -3; keep_logs; exit 1
fi
HOST_LINE="$(grep -h "^JOINRESULT" "$TMP/host.log")"
JOINER_LINE="$(grep -h "^JOINRESULT" "$TMP/joiner.log")"
if [ -z "$HOST_LINE" ] || [ -z "$JOINER_LINE" ]; then echo "FAIL: a side printed no result"; keep_logs; exit 1; fi
field() { echo "$1" | tr ' ' '\n' | sed -n "s/^$2=//p"; }
STATUS=0
for name in active kind landed launches spawn_tick arm_tick owner x y; do
	if [ "$(field "$HOST_LINE" $name)" != "$(field "$JOINER_LINE" $name)" ]; then
		echo "FAIL: $name differs: host $(field "$HOST_LINE" $name), joiner $(field "$JOINER_LINE" $name)"; STATUS=1
	fi
done
if [ "$(field "$JOINER_LINE" active)" != "1" ] || [ "$(field "$JOINER_LINE" landed)" != "1" ] || [ "$(field "$JOINER_LINE" kind)" != "2" ]; then
	echo "FAIL: the joiner does not see an active, landed plate"; STATUS=1
fi
if [ "$STATUS" -ne 0 ]; then keep_logs; exit 1; fi
echo "PASS: a client that joined after the plate was thrown sees the same active plate as the host"
exit 0
