#!/usr/bin/env bash
# Two-process combat test at simulated latency (task B). A host and a client run the main scene
# with a shortened hazard (tests/test_combat_net.gd). Every bot idles on the floor: the hazard
# must knock each one out on the same tick on both sides with the same ko_serial and respawn
# tick, and the dummy must exist on both with the same position. See compare_combat_net.py.
# SIM_LATENCY_MS (default 75) and SIM_LOSS are applied on both sides; the host's proxy listens on
# PORT + 1, so keep that port free too.
# Exit code 0 = pass, 1 = fail. Never leaves processes running.
set -u

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${PORT:-24970}"
TMP="$(mktemp -d)"
PIDS=()
SIM_ARGS=("--sim-latency-ms=${SIM_LATENCY_MS:-75}")
[ -n "${SIM_LOSS:-}" ] && SIM_ARGS+=("--sim-loss=$SIM_LOSS")

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

"$GODOT" --headless --path "$ROOT" res://tests/test_combat_net.tscn -- --host --port="$PORT" "${SIM_ARGS[@]}" >"$TMP/host.log" 2>&1 &
HOST_PID=$!
PIDS+=("$HOST_PID")

for _ in $(seq 1 200); do
	grep -q "^LISTENING" "$TMP/host.log" 2>/dev/null && break
	sleep 0.1
done
if ! grep -q "^LISTENING" "$TMP/host.log"; then
	echo "FAIL: host did not start listening"; cat "$TMP/host.log"; exit 1
fi

"$GODOT" --headless --path "$ROOT" res://tests/test_combat_net.tscn -- --join=127.0.0.1 --port="$PORT" "${SIM_ARGS[@]}" >"$TMP/client.log" 2>&1 &
CLIENT_PID=$!
PIDS+=("$CLIENT_PID")

wait_exit "$CLIENT_PID" 80 || { echo "FAIL: client did not exit in time"; tail -5 "$TMP/client.log"; exit 1; }
wait_exit "$HOST_PID" 40 || { echo "FAIL: host did not exit in time"; tail -5 "$TMP/host.log"; exit 1; }

if grep -q "SCRIPT ERROR\|^ERROR\|^FAIL" "$TMP/host.log" "$TMP/client.log"; then
	echo "FAIL: errors in logs"; grep -h "SCRIPT ERROR\|^ERROR\|^FAIL" "$TMP/host.log" "$TMP/client.log" | head; exit 1
fi

python3 -I "$ROOT/tests/compare_combat_net.py" "$TMP/host.log" "$TMP/client.log"
STATUS=$?
if [ "$STATUS" -ne 0 ]; then echo "logs kept in $TMP"; trap - EXIT; cleanup; fi
exit "$STATUS"
