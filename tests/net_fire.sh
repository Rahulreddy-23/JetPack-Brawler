#!/usr/bin/env bash
# Two-process test of the fire path: a client holds the rivet gun's fire input for exactly
# five shots at a bot of the host (see tests/test_fire_net.gd). Passes when host and client
# agree on the shot count and the last shot tick, the last shot tick is the one the input
# schedule gives, and for every fire tick the host's hit list names the host's bot, once.
# The host re-simulates every fire tick, so each is processed at least twice; the passes and the
# recorded history must agree on shots_fired, ammo, last_shot_tick and the hit list.
# SIM_LATENCY_MS=75 runs it through the latency simulator on both sides (the proxy listens
# on PORT + 1, so keep that port free too).
# Exit code 0 = pass, 1 = fail. Never leaves processes running.
set -u

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${PORT:-24998}"
TMP="$(mktemp -d)"
PIDS=()
SIM_ARGS=()
[ -n "${SIM_LATENCY_MS:-}" ] && SIM_ARGS+=("--sim-latency-ms=$SIM_LATENCY_MS")
[ -n "${SIM_LOSS:-}" ] && SIM_ARGS+=("--sim-loss=$SIM_LOSS")

cleanup() {
	for pid in "${PIDS[@]:-}"; do [ -n "$pid" ] && kill "$pid" 2>/dev/null; done
	sleep 0.3
	for pid in "${PIDS[@]:-}"; do [ -n "$pid" ] && kill -9 "$pid" 2>/dev/null; done
}
trap cleanup EXIT

wait_exit() { # pid, seconds
	local pid="$1" limit=$(( $2 * 10 )) i=0
	while kill -0 "$pid" 2>/dev/null; do
		i=$(( i + 1 ))
		[ "$i" -ge "$limit" ] && return 1
		sleep 0.1
	done
	return 0
}

fail() { echo "FAIL: $1"; echo "logs kept in $TMP"; trap - EXIT; cleanup; exit 1; }

"$GODOT" --headless --path "$ROOT" res://tests/test_fire_net.tscn -- --host --port="$PORT" ${SIM_ARGS[@]+"${SIM_ARGS[@]}"} >"$TMP/host.log" 2>&1 &
HOST_PID=$!
PIDS+=("$HOST_PID")
for _ in $(seq 1 200); do grep -q "^LISTENING" "$TMP/host.log" 2>/dev/null && break; sleep 0.1; done
grep -q "^LISTENING" "$TMP/host.log" || fail "the host did not start listening"

"$GODOT" --headless --path "$ROOT" res://tests/test_fire_net.tscn -- --join=127.0.0.1 --port="$PORT" ${SIM_ARGS[@]+"${SIM_ARGS[@]}"} >"$TMP/client.log" 2>&1 &
CLIENT_PID=$!
PIDS+=("$CLIENT_PID")
wait_exit "$CLIENT_PID" 60 || fail "the client did not finish in time"
wait_exit "$HOST_PID" 40 || fail "the host did not finish in time"

if grep -q "SCRIPT ERROR\|^ERROR\|^FAIL" "$TMP/host.log" "$TMP/client.log"; then
	grep -h "SCRIPT ERROR\|^ERROR\|^FAIL" "$TMP/host.log" "$TMP/client.log" | head -5
	fail "errors in the logs"
fi

HOST_RESULT="$(grep "^FIRE_RESULT role=host" "$TMP/host.log")"
CLIENT_RESULT="$(grep "^FIRE_RESULT role=client" "$TMP/client.log")"
echo "$HOST_RESULT"; echo "$CLIENT_RESULT"
[ -n "$HOST_RESULT" ] && [ -n "$CLIENT_RESULT" ] || fail "a side did not report"
field() { echo "$1" | sed -n "s/.* $2=\([-0-9]*\).*/\1/p"; }

SHOTS=5
[ "$(field "$HOST_RESULT" shots)" = "$SHOTS" ] || fail "the host counts $(field "$HOST_RESULT" shots) shots, not $SHOTS"
[ "$(field "$CLIENT_RESULT" shots)" = "$SHOTS" ] || fail "the client counts $(field "$CLIENT_RESULT" shots) shots, not $SHOTS"
[ "$(field "$HOST_RESULT" last_shot)" = "$(field "$CLIENT_RESULT" last_shot)" ] || fail "last_shot_tick differs: host $(field "$HOST_RESULT" last_shot), client $(field "$CLIENT_RESULT" last_shot)"
[ "$(field "$HOST_RESULT" last_shot)" = "$(field "$CLIENT_RESULT" expect_last)" ] || fail "last_shot_tick $(field "$HOST_RESULT" last_shot) is not the scheduled $(field "$CLIENT_RESULT" expect_last)"

FIRST="$(field "$CLIENT_RESULT" first)"
INTERVAL="$(field "$CLIENT_RESULT" interval)"
HIT_LINES="$(grep "^FIRE_HIT" "$TMP/host.log")"
echo "$HIT_LINES"
[ "$(echo "$HIT_LINES" | grep -c .)" = "$SHOTS" ] || fail "the host has $(echo "$HIT_LINES" | grep -c .) fire ticks, not $SHOTS"
for k in $(seq 0 $(( SHOTS - 1 ))); do
	WANT=$(( FIRST + k * INTERVAL ))
	echo "$HIT_LINES" | grep -q "^FIRE_HIT tick=$WANT victims=1 count=1 " || fail "fire tick $WANT: the host's hit list does not name exactly the host's bot"
done
# Every fire tick must have been processed at least twice, with the same result each time.
MIN_PASSES="$(echo "$HIT_LINES" | sed -n 's/.*passes=\([0-9]*\).*/\1/p' | sort -n | head -1)"
echo "fewest passes of one fire tick on the host: $MIN_PASSES"
[ "$MIN_PASSES" -ge 2 ] || fail "a fire tick was processed only once on the host (the re-simulation did not happen)"
CHECK="$(grep "^FIRE_CHECK" "$TMP/host.log")"
echo "$CHECK"
[ "$(field "$CHECK" pass_mismatches)" = "0" ] || fail "a fire tick gave different results on different passes"
[ "$(field "$CHECK" settled)" = "$SHOTS" ] || fail "only $(field "$CHECK" settled) fire ticks were found in the recorded history"
[ "$(field "$CHECK" settled_mismatches)" = "0" ] || fail "the recorded history of a fire tick differs from what the passes produced"
echo "PASS"
