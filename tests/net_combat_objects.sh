#!/usr/bin/env bash
# End-to-end blast test with the real combat rules, two processes (see tests/test_combat_objects.gd).
# A client stands next to the dummy and throws its Cooker Bomb (WEAPON=bomb, the default) or fires
# the rocket tube at it (WEAPON=rocket). Passes when, on host and client alike:
#  - the bomb explodes 90 ticks after its launch (the rocket within ten ticks of its launch), on
#    the same tick on both sides;
#  - the dummy's health falls by exactly the blast damage for its distance from the blast, and
#    the thrower's by the self-damage share when it was in range, the distances taken from the
#    positions the history recorded and the numbers from the config;
#  - hits_taken of the dummy rose once, blasts of the slot once, and the dummy's last attacker
#    is the client;
#  - the dummy was pushed away from the blast, and its position on settled ticks after the blast
#    is the same on both sides.
# SIM_LATENCY_MS (default 75) and SIM_LOSS run it through the latency simulator on both sides
# (the proxy listens on PORT + 1, so keep that port free too).
# Usage: PORT=26070 WEAPON=rocket SIM_LATENCY_MS=75 SIM_LOSS=5 tests/net_combat_objects.sh
# Exit code 0 = pass, 1 = fail. Never leaves processes running.
set -u

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${PORT:-24995}"
WEAPON="${WEAPON:-bomb}"
SIM_ARGS=("--sim-latency-ms=${SIM_LATENCY_MS:-75}")
[ -n "${SIM_LOSS:-}" ] && SIM_ARGS+=("--sim-loss=$SIM_LOSS")
TMP="$(mktemp -d)"
PIDS=()

cleanup() {
	for pid in "${PIDS[@]:-}"; do [ -n "$pid" ] && kill "$pid" 2>/dev/null; done
	sleep 0.3
	for pid in "${PIDS[@]:-}"; do [ -n "$pid" ] && kill -9 "$pid" 2>/dev/null; done
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

fail() { echo "FAIL: $1"; echo "logs kept in $TMP"; trap - EXIT; cleanup; exit 1; }

"$GODOT" --headless --path "$ROOT" res://tests/test_combat_objects.tscn -- --host --port="$PORT" --weapon="$WEAPON" "${SIM_ARGS[@]}" >"$TMP/host.log" 2>&1 &
HOST_PID=$!
PIDS+=("$HOST_PID")
for _ in $(seq 1 200); do grep -q "^LISTENING" "$TMP/host.log" 2>/dev/null && break; sleep 0.1; done
grep -q "^LISTENING" "$TMP/host.log" || fail "the host did not start listening"

"$GODOT" --headless --path "$ROOT" res://tests/test_combat_objects.tscn -- --join=127.0.0.1 --port="$PORT" --weapon="$WEAPON" "${SIM_ARGS[@]}" >"$TMP/client.log" 2>&1 &
CLIENT_PID=$!
PIDS+=("$CLIENT_PID")
wait_exit "$CLIENT_PID" 70 || fail "the client did not finish in time"
wait_exit "$HOST_PID" 40 || fail "the host did not finish in time"

if grep -q "SCRIPT ERROR\|^ERROR\|^FAIL" "$TMP/host.log" "$TMP/client.log"; then
	grep -h "SCRIPT ERROR\|^ERROR\|^FAIL" "$TMP/host.log" "$TMP/client.log" | head -5
	fail "errors in the logs"
fi
grep -h "^COMBAT_RESULT" "$TMP/host.log" "$TMP/client.log"
python3 -I "$ROOT/tests/check_combat_objects.py" "$TMP/host.log" "$TMP/client.log" "$WEAPON" || fail "see above"
echo "PASS"
