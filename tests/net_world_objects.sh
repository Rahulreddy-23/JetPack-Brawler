#!/usr/bin/env bash
# Two-process test of world objects at simulated latency (default 75 ms one way). A headless
# host and a headless client (127.0.0.1, both through the latency proxy, which listens on
# PORT + 1) run tests/test_net_objects.tscn. The client's bot throws one Cooker Bomb; both
# sides then print where and when they saw the slot active, exploded and inactive. The test
# passes when the explosion tick and position are equal on both sides, the slot is active
# and then inactive on the same ticks, the fuse is exactly 90 ticks, and launches and blasts
# each rose exactly once on both sides.
# Usage: PORT=26040 SIM_LATENCY_MS=75 tests/net_world_objects.sh   (SIM_LOSS=5 adds 5 percent packet loss)
# Exit code 0 = pass, 1 = fail. Never leaves processes running.
set -u

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${PORT:-24996}"
LATENCY="${SIM_LATENCY_MS:-75}"
SIM_ARGS=("--sim-latency-ms=$LATENCY")
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

"$GODOT" --headless --path "$ROOT" res://tests/test_net_objects.tscn -- --host --port="$PORT" "${SIM_ARGS[@]}" >"$TMP/host.log" 2>&1 &
HOST_PID=$!
PIDS+=("$HOST_PID")
for _ in $(seq 1 200); do grep -q "^LISTENING" "$TMP/host.log" 2>/dev/null && break; sleep 0.1; done
if ! grep -q "^LISTENING" "$TMP/host.log"; then echo "FAIL: host did not start listening"; cat "$TMP/host.log"; exit 1; fi

"$GODOT" --headless --path "$ROOT" res://tests/test_net_objects.tscn -- --join=127.0.0.1 --port="$PORT" "${SIM_ARGS[@]}" >"$TMP/client.log" 2>&1 &
CLIENT_PID=$!
PIDS+=("$CLIENT_PID")

wait_exit "$CLIENT_PID" 45 || { echo "FAIL: client did not exit in time"; tail -5 "$TMP/client.log"; exit 1; }
wait_exit "$HOST_PID" 45 || { echo "FAIL: host did not exit in time"; tail -5 "$TMP/host.log"; exit 1; }

grep -h "^OBJTRACE\|^OBJRESULT\|^RESIM" "$TMP/host.log" "$TMP/client.log"
if grep -q "SCRIPT ERROR\|^ERROR\|^FAIL" "$TMP/host.log" "$TMP/client.log"; then
	echo "FAIL: errors in logs"; grep -h "SCRIPT ERROR\|^ERROR\|^FAIL" "$TMP/host.log" "$TMP/client.log" | head; echo "logs kept in $TMP"; trap - EXIT; cleanup; exit 1
fi

HOST_LINE="$(grep -h "^OBJRESULT" "$TMP/host.log")"
CLIENT_LINE="$(grep -h "^OBJRESULT" "$TMP/client.log")"
field() { echo "$1" | tr ' ' '\n' | sed -n "s/^$2=//p"; }
STATUS=0
fail() { echo "FAIL: $1"; STATUS=1; }

[ -n "$HOST_LINE" ] && [ -n "$CLIENT_LINE" ] || { echo "FAIL: a side printed no result"; echo "logs kept in $TMP"; trap - EXIT; cleanup; exit 1; }

for name in on_tick off_tick explode_tick spawn_tick x y launches blasts; do
	[ "$(field "$HOST_LINE" $name)" = "$(field "$CLIENT_LINE" $name)" ] || fail "$name differs: host $(field "$HOST_LINE" $name), client $(field "$CLIENT_LINE" $name)"
done
for side in host client; do
	LINE="$HOST_LINE"; [ "$side" = "client" ] && LINE="$CLIENT_LINE"
	SPAWN="$(field "$LINE" spawn_tick)"; EXPLODE="$(field "$LINE" explode_tick)"
	ON="$(field "$LINE" on_tick)"; OFF="$(field "$LINE" off_tick)"
	[ "$EXPLODE" -eq $(( SPAWN + 90 )) ] 2>/dev/null || fail "$side: explode_tick $EXPLODE is not spawn_tick $SPAWN + 90"
	[ "$ON" -eq $(( SPAWN + 1 )) ] 2>/dev/null || fail "$side: slot became active at $ON, expected $(( SPAWN + 1 ))"
	[ "$OFF" -eq $(( EXPLODE + 1 )) ] 2>/dev/null || fail "$side: slot became inactive at $OFF, expected $(( EXPLODE + 1 ))"
	[ "$(field "$LINE" holes)" = "0" ] || fail "$side: the slot was inactive for some tick between launch and blast"
	[ "$(field "$LINE" launches)" = "1" ] && [ "$(field "$LINE" blasts)" = "1" ] || fail "$side: launches and blasts should each be 1"
	[ "$(field "$LINE" launch_rises)" = "1" ] || fail "$side: launches rose $(field "$LINE" launch_rises) times, expected 1"
	[ "$(field "$LINE" blast_rises)" = "1" ] || fail "$side: blasts rose $(field "$LINE" blast_rises) times, expected 1"
	[ "$(field "$LINE" drops)" = "0" ] || fail "$side: a counter dropped $(field "$LINE" drops) times"
done
# The host ran the launch tick and the explosion tick again; every pass left the same state.
SPAWN="$(field "$HOST_LINE" spawn_tick)"; EXPLODE="$(field "$HOST_LINE" explode_tick)"
for TICK in "$SPAWN" "$EXPLODE"; do
	RESIM="$(grep "^RESIM tick=$TICK " "$TMP/host.log")"
	if [ -z "$RESIM" ]; then fail "the host recorded no passes of tick $TICK"; continue; fi
	[ "$(field "$RESIM" passes)" -ge 2 ] 2>/dev/null || fail "tick $TICK was processed only $(field "$RESIM" passes) time on the host (the re-simulation did not happen)"
	[ "$(field "$RESIM" states)" = "1" ] || fail "tick $TICK gave $(field "$RESIM" states) different slot states on different passes"
done
LAUNCH_STATE="$(grep "^RESIM tick=$SPAWN " "$TMP/host.log" | sed 's/.* state=//')"
[ "$LAUNCH_STATE" = "launches=1,blasts=0,spawn=$SPAWN,explode=-1,active=1" ] || fail "the launch tick left the state $LAUNCH_STATE on every pass, expected one launch"
EXPLODE_STATE="$(grep "^RESIM tick=$EXPLODE " "$TMP/host.log" | sed 's/.* state=//')"
[ "$EXPLODE_STATE" = "launches=1,blasts=1,spawn=$SPAWN,explode=$EXPLODE,active=0" ] || fail "the explosion tick left the state $EXPLODE_STATE on every pass, expected one blast"
if [ "$STATUS" -ne 0 ]; then echo "logs kept in $TMP"; trap - EXIT; cleanup; exit 1; fi
echo "PASS: host and client agree on the launch, the fuse, the explosion tick and position, saw each counter rise once, and a re-simulated launch and blast changed nothing"
exit 0
