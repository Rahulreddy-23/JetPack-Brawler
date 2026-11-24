#!/usr/bin/env bash
# A full host turns away the same kind of player many times in a row. Each rejected
# player must see "Match full" before the host's notice window ends and never get a
# bot, and the host log must stay free of ERROR lines (netfox failed to send to a peer
# the host was disconnecting). Exit code 0 = pass. Never leaves processes running.
set -u

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${PORT:-24995}"
ROUNDS="${ROUNDS:-15}"
TMP="$(mktemp -d)"
PIDS=()

cleanup() {
	for pid in "${PIDS[@]:-}"; do [ -n "$pid" ] && kill "$pid" 2>/dev/null; done
	sleep 0.3
	for pid in "${PIDS[@]:-}"; do [ -n "$pid" ] && kill -9 "$pid" 2>/dev/null; done
}
trap cleanup EXIT

run() { # name, quit-after, extra args...
	local name="$1" quit="$2"; shift 2
	"$GODOT" --headless --path "$ROOT" -- --port="$PORT" --quit-after="$quit" "$@" >"$TMP/$name.log" 2>&1 &
	PIDS+=("$!")
}

run host $(( ROUNDS * 2 + 25 )) --host
for _ in $(seq 1 200); do grep -q "^LISTENING" "$TMP/host.log" 2>/dev/null && break; sleep 0.1; done
for n in 1 2 3; do run "c$n" $(( ROUNDS * 2 + 20 )) --join=127.0.0.1; sleep 0.5; done
sleep 3

"$GODOT" --headless --path "$ROOT" res://tests/test_reject_client.tscn -- --port="$PORT" --rounds="$ROUNDS" >"$TMP/reject.log" 2>&1
STATUS=$?
grep "^FAIL" "$TMP/reject.log"
echo "$(grep -c '^PASS round' "$TMP/reject.log") of $ROUNDS rounds passed"
grep "rounds ended by" "$TMP/reject.log"
sleep 1

if grep -q "SCRIPT ERROR\|^ERROR" "$TMP"/*.log; then echo "FAIL: errors in logs"; grep -H -B2 -A8 "SCRIPT ERROR\|^ERROR" "$TMP"/*.log | head -30; exit 1; fi
[ "$STATUS" -eq 0 ] || { echo "FAIL: rejected client checks (exit $STATUS)"; exit 1; }
# The dummy (peer 0) is not a player and does not count against the match limit.
BOTS=$(grep "^BOT_SPAWNED" "$TMP/host.log" | grep -vc "peer=0$")
[ "$BOTS" -eq 4 ] || { echo "FAIL: host spawned $BOTS bots, expected 4"; exit 1; }
for n in 1 2 3; do grep -q "SESSION_ENDED" "$TMP/c$n.log" && { echo "FAIL: client $n was dropped"; exit 1; }; done
echo "PASS"
