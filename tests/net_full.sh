#!/usr/bin/env bash
# Checks that the server refuses a fifth player: one host plus three clients
# fill the match (4 bots); a fourth client must not get a bot and must be sent
# back to the menu at once with a "Match full" message. Exit code 0 = pass. Never leaves processes running.
set -u

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${PORT:-24998}"
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

wait_all() {
	local limit=$(( $1 * 10 )) i=0
	for pid in "${PIDS[@]}"; do
		while kill -0 "$pid" 2>/dev/null; do
			i=$(( i + 1 )); [ "$i" -ge "$limit" ] && return 1; sleep 0.1
		done
	done
}

run host 25 --host --trace
for _ in $(seq 1 200); do grep -q "^LISTENING" "$TMP/host.log" 2>/dev/null && break; sleep 0.1; done
for n in 1 2 3; do run "c$n" 22 --join=127.0.0.1; sleep 0.5; done
sleep 2
run c4 8 --join=127.0.0.1

wait_all 60 || { echo "FAIL: processes did not exit in time"; exit 1; }

BOTS=$(grep -c "^FINAL" "$TMP/host.log")
echo "host saw $BOTS bots"
grep -h "SESSION_ENDED" "$TMP/c4.log" "$TMP/c1.log" "$TMP/c2.log" "$TMP/c3.log" | sed 's/^/client message: /'
if grep -q "SCRIPT ERROR\|^ERROR" "$TMP"/*.log; then echo "FAIL: script errors"; grep -H -B3 "SCRIPT ERROR\|^ERROR" "$TMP"/*.log | head -20; exit 1; fi
[ "$BOTS" -eq 4 ] || { echo "FAIL: expected exactly 4 bots"; exit 1; }
grep -q "SESSION_ENDED Match full" "$TMP/c4.log" || { echo "FAIL: fifth player was not told the match is full within 8 s"; exit 1; }
for n in 1 2 3; do grep -q "SESSION_ENDED" "$TMP/c$n.log" && { echo "FAIL: client $n was dropped"; exit 1; }; done
echo "PASS"
