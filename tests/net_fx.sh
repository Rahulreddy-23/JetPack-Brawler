#!/usr/bin/env bash
# Two-process test of the effects director's first sight (task E). The host gives the dummy and a
# world-object slot old counters before the client joins; the client must show nothing for them,
# and exactly one effect for each of three later increases. See tests/test_fx_net.gd.
# SIM_LATENCY_MS (default 75) is applied on both sides; the host's proxy listens on PORT + 1, so
# keep that port free too.
# Exit code 0 = pass, 1 = fail. Never leaves processes running.
set -u

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${PORT:-24960}"
TMP="$(mktemp -d)"
PIDS=()
SIM_ARGS=("--sim-latency-ms=${SIM_LATENCY_MS:-75}")

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

wait_exit() {
	local pid="$1" limit=$(( $2 * 10 )) i=0
	while kill -0 "$pid" 2>/dev/null; do
		i=$(( i + 1 ))
		[ "$i" -ge "$limit" ] && return 1
		sleep 0.1
	done
	return 0
}

"$GODOT" --headless --path "$ROOT" res://tests/test_fx_net.tscn -- --host --port="$PORT" "${SIM_ARGS[@]}" >"$TMP/host.log" 2>&1 &
HOST_PID=$!
PIDS+=("$HOST_PID")

for _ in $(seq 1 200); do
	grep -q "^LISTENING" "$TMP/host.log" 2>/dev/null && break
	sleep 0.1
done
if ! grep -q "^LISTENING" "$TMP/host.log"; then
	echo "FAIL: host did not start listening"; cat "$TMP/host.log"; exit 1
fi

"$GODOT" --headless --path "$ROOT" res://tests/test_fx_net.tscn -- --join=127.0.0.1 --port="$PORT" "${SIM_ARGS[@]}" >"$TMP/client.log" 2>&1 &
CLIENT_PID=$!
PIDS+=("$CLIENT_PID")

wait_exit "$CLIENT_PID" 70 || { echo "FAIL: client did not exit in time"; tail -5 "$TMP/client.log"; exit 1; }
wait_exit "$HOST_PID" 30 || { echo "FAIL: host did not exit in time"; tail -5 "$TMP/host.log"; exit 1; }

grep -h "^PASS\|^FAIL" "$TMP/host.log" "$TMP/client.log"
if grep -q "SCRIPT ERROR\|^ERROR\|^FAIL" "$TMP/host.log" "$TMP/client.log"; then
	echo "FAIL: errors or failed checks in the logs"; grep -h "SCRIPT ERROR\|^ERROR\|^FAIL" "$TMP/host.log" "$TMP/client.log" | head
	echo "logs kept in $TMP"; trap - EXIT; cleanup; exit 1
fi
grep -q "^0 failures" "$TMP/client.log" || { echo "FAIL: client did not finish its checks"; tail -5 "$TMP/client.log"; exit 1; }
echo "PASS"
