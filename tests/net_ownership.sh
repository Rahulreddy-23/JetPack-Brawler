#!/usr/bin/env bash
# A phone that joined a game, left and then hosts must send its object slots' and pickup
# spots' state to its guests. Three processes: a first host H (PORT); a relay that joins H,
# leaves and hosts itself (PORT + 1); a guest that joins the relay and waits for a value
# written into a slot and a spot on the relay to arrive.
# Exit code 0 = pass. Fails on any SCRIPT ERROR. Never leaves processes running.
set -u

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${PORT:-24994}"
TMP="$(mktemp -d)"
PIDS=()

cleanup() {
	for pid in "${PIDS[@]:-}"; do [ -n "$pid" ] && kill "$pid" 2>/dev/null; done
	sleep 0.3
	for pid in "${PIDS[@]:-}"; do [ -n "$pid" ] && kill -9 "$pid" 2>/dev/null; done
}
trap cleanup EXIT

"$GODOT" --headless --path "$ROOT" -- --host --port="$PORT" --quit-after=60 >"$TMP/first_host.log" 2>&1 &
PIDS+=("$!")
for _ in $(seq 1 200); do grep -q "^LISTENING" "$TMP/first_host.log" 2>/dev/null && break; sleep 0.1; done

"$GODOT" --headless --path "$ROOT" res://tests/test_ownership.tscn -- --mode=relay --address=127.0.0.1 --port="$PORT" --host-port="$((PORT + 1))" >"$TMP/relay.log" 2>&1 &
PIDS+=("$!")
for _ in $(seq 1 300); do grep -q "^RELAY_HOSTING\|^FAIL" "$TMP/relay.log" 2>/dev/null && break; sleep 0.1; done
if ! grep -q "^RELAY_HOSTING" "$TMP/relay.log"; then
	echo "FAIL: the relay did not come up as a host"; cat "$TMP/relay.log" | tail -5; exit 1
fi

"$GODOT" --headless --path "$ROOT" res://tests/test_ownership.tscn -- --mode=check --address=127.0.0.1 --port="$((PORT + 1))" >"$TMP/guest.log" 2>&1
STATUS=$?
grep "^PASS\|^FAIL" "$TMP/guest.log"
for log in first_host relay guest; do
	if grep -q "SCRIPT ERROR" "$TMP/$log.log"; then
		echo "FAIL: script errors in $log log"; grep -h "SCRIPT ERROR" "$TMP/$log.log" | head; exit 1
	fi
done
if [ "$STATUS" -ne 0 ]; then echo "FAIL: guest status $STATUS"; exit 1; fi
echo "PASS"
