#!/usr/bin/env bash
# Two-process test of one late client input. The host runs tests/test_host_late_input.tscn;
# the simulator on the host holds the client's packets of one short window an extra
# HOLD_MS (so later packets overtake them and the host lacks the input of one tick for a
# while); the client is a headless autopilot client. The host reports the states it sent for
# a tick and later replaced; afterwards the client bot's recorded positions are compared
# with the host's.
# Usage: HOLD_MS=233 tests/net_late_input.sh
#   HOLD_MS         extra delay of the held packets (default 233: the hole's input arrives
#                   about 3 ticks after the packets that overtook it; 0 holds nothing)
#   HOLD_AT_MS      window start after the first client packet (default 4500)
#   HOLD_WINDOW_MS  window length (default 150, four to five input packets at 30 ticks per second;
#                   input_redundancy is 4, so fewer packets hide nothing)
#   EXPECT_REFUSED  1 for a hold past the input allowance (600): the hole's input must be
#                   refused and the bot not simulated on its tick; no sent state is replaced;
#                   the owner's client may show its bot wrong only from the hole's tick to at most
#                   the allowance plus input_redundancy after it (expiry plus one transit), and TRACE_DIFF
#                   must not differ later than that
#   PAUSE_MS        stops the client (SIGSTOP) for this long, about 3 s after it joined, instead of
#                   holding packets (use HOLD_MS=0): the host must not simulate the bot on any tick
#                   it has no input for, the bot must not move across them, and the same bound as
#                   EXPECT_REFUSED applies afterwards
#   EXPECT_SILENT   1 with LATENCY_MS=600: every input of the client is later than the allowance. The host
#                   must refuse them all and never simulate the bot, warn about the peer (once a
#                   second at most) and count the refusals; the client, which does simulate its bot, moves
#   OBSERVER        1 starts a second, idle client after the first one, which reports what it
#                   received for the first client's bot (a third player's view)
#   JITTER_MS       adds the simulator's random delay (up to this many ms, both directions); the
#                   INPUT_LAG line then shows how late inputs arrive (use HOLD_MS=0)
#   LATENCY_MS      the simulator's delay in each direction (one way); above 400 ms every input of the
#                   client is later than the allowance
#   TICK_LOG        1 prints the host tick by tick around the hole (TICKLOG lines)
#   KEEP_LOGS       1 keeps the logs even when the test passes
#   PORT            host port (the simulator uses PORT + 1)
# Exit code 0 = no state was replaced and the client never showed its own bot wrong, 1 = the
# fault or a failure.
# Never leaves processes running. The numbers are printed either way.
set -u

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${PORT:-24994}"
HOLD_MS="${HOLD_MS:-233}"
HOLD_AT_MS="${HOLD_AT_MS:-4500}"
HOLD_WINDOW_MS="${HOLD_WINDOW_MS:-150}"
OBSERVER="${OBSERVER:-0}"
EXPECT_REFUSED="${EXPECT_REFUSED:-0}"
PAUSE_MS="${PAUSE_MS:-0}"
EXPECT_SILENT="${EXPECT_SILENT:-0}"
HOST_EXTRA=()
[ "${TICK_LOG:-0}" = "1" ] && HOST_EXTRA+=(--tick-log)
[ "$EXPECT_REFUSED" = "1" ] && HOST_EXTRA+=(--expect-refused)
[ "$EXPECT_SILENT" = "1" ] && HOST_EXTRA+=(--expect-silent)
if [ "$PAUSE_MS" -gt 0 ]; then
	HOST_EXTRA+=(--expect-pause)
	EXPECT_REFUSED=1
fi
TMP="$(mktemp -d)"
PIDS=()
SIM_ARGS=(--sim-hold-ms="$HOLD_MS" --sim-hold-at-ms="$HOLD_AT_MS" --sim-hold-window-ms="$HOLD_WINDOW_MS")
[ -n "${JITTER_MS:-}" ] && SIM_ARGS+=(--sim-jitter-ms="$JITTER_MS")
[ -n "${LATENCY_MS:-}" ] && SIM_ARGS+=(--sim-latency-ms="$LATENCY_MS")

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

"$GODOT" --headless --path "$ROOT" res://tests/test_host_late_input.tscn -- --host --port="$PORT" --trace --quit-after=40 "${SIM_ARGS[@]}" "${HOST_EXTRA[@]:-}" >"$TMP/host.log" 2>&1 &
HOST_PID=$!
PIDS+=("$HOST_PID")

for _ in $(seq 1 200); do
	grep -q "^LISTENING" "$TMP/host.log" 2>/dev/null && break
	sleep 0.1
done
if ! grep -q "^LISTENING" "$TMP/host.log"; then
	echo "FAIL: host did not start listening"; cat "$TMP/host.log"; exit 1
fi

"$GODOT" --headless --path "$ROOT" res://tests/test_client_display.tscn -- --join=127.0.0.1 --port="$PORT" --autopilot --autopilot-wiggle --trace --quit-after=14 "${SIM_ARGS[@]}" >"$TMP/client.log" 2>&1 &
CLIENT_PID=$!
PIDS+=("$CLIENT_PID")

if [ "$PAUSE_MS" -gt 0 ]; then
	for _ in $(seq 1 300); do
		grep -q "^CLIENT_JOINED" "$TMP/host.log" 2>/dev/null && break
		sleep 0.1
	done
	sleep 3
	kill -STOP "$CLIENT_PID"
	sleep "$(python3 -c "print($PAUSE_MS / 1000)")"
	kill -CONT "$CLIENT_PID"
fi

if [ "$OBSERVER" = "1" ]; then
	sleep 2
	"$GODOT" --headless --path "$ROOT" res://tests/test_client_display.tscn -- --join=127.0.0.1 --port="$PORT" --quit-after=11 "${SIM_ARGS[@]}" >"$TMP/observer.log" 2>&1 &
	OBSERVER_PID=$!
	PIDS+=("$OBSERVER_PID")
	wait_exit "$OBSERVER_PID" 40 || { echo "FAIL: observer did not exit in time"; exit 1; }
fi
wait_exit "$CLIENT_PID" 40 || { echo "FAIL: client did not exit in time"; exit 1; }
wait_exit "$HOST_PID" 60 || { echo "FAIL: host did not exit in time"; tail -20 "$TMP/host.log"; exit 1; }
wait "$HOST_PID"
STATUS=$?

echo "hold: ${HOLD_MS} ms, window ${HOLD_WINDOW_MS} ms at ${HOLD_AT_MS} ms"
grep "^INPUT_LAG\|^SILENT\|^PAUSE\|^STALE_STATES\|^JOIN_START\|^JOIN_REORDERED\|^HOLE_LATENESS\|^TICKLOG\|^REFUSED\|^PASS\|^FAIL" "$TMP/host.log"
echo "subjects of the rollback state whose first state sent for a tick was later replaced:"
grep "^SUBJECT_REPLACED" "$TMP/host.log" | grep -v "first_state_replaced_on=0" || echo "  none besides the client bot above" 
if [ "$EXPECT_SILENT" = "1" ]; then
	# What each side sees: the host never moves the bot (sim=0 on every tick), the client does.
	WARNINGS="$(grep -c '^\[WRN\].*Refusing input' "$TMP/host.log")"
	echo "WARNINGS_ABOUT_THE_PEER count=$WARNINGS (at most one a second)"
	if [ "$WARNINGS" -lt 1 ] || [ "$WARNINGS" -gt 14 ]; then echo "FAIL: $WARNINGS warnings about the refused peer, expected 1 to 14 in about 10 seconds"; STATUS=1; fi
	python3 -I - "$TMP/host.log" "$TMP/client.log" <<'PYEOF' || STATUS=1
import re, sys
def positions(path):
    rows = []
    for line in open(path, errors="replace"):
        if line.startswith("TRACE "):
            f = dict(re.findall(r"(\w+)=(\S+)", line))
            if f["peer"] not in ("0", "1"):
                rows.append((int(f["tick"]), float(f["x"]), float(f["y"]), f["sim"]))
    return rows
host, client = positions(sys.argv[1]), positions(sys.argv[2])
def travelled(rows):
    return max(((x - rows[0][1]) ** 2 + (y - rows[0][2]) ** 2) ** 0.5 for _, x, y, _ in rows) if rows else 0.0
simulated = sum(1 for r in host if r[3] == "1")
print("SEEN host_bot_travelled_px=%.1f host_ticks_simulated=%d client_own_bot_travelled_px=%.1f" % (travelled(host), simulated, travelled(client)))
if simulated or travelled(host) > 1.0 or travelled(client) < 100.0:
    print("FAIL: expected a frozen bot on the host and a moving one on its owner's client"); sys.exit(1)
PYEOF
	if [ "$STATUS" -ne 0 ] || [ "${KEEP_LOGS:-0}" = "1" ]; then echo "logs kept in $TMP"; trap - EXIT; cleanup; fi
	exit "$STATUS"
fi
python3 -I "$ROOT/tests/trace_diff_report.py" "$TMP/host.log" "$TMP/client.log" | tee "$TMP/trace.txt"
python3 -I "$ROOT/tests/display_report.py" "$TMP/host.log" "$TMP/client.log" | tee "$TMP/display.txt"
if [ "$EXPECT_REFUSED" = "1" ]; then
	# Bounded by code: the client simulated the expired tick and the host did not; the host's
	# states for the ticks after it are sent once the hole expires, ALLOWANCE ticks after it.
	if ! python3 -I - "$TMP/host.log" "$TMP/display.txt" "$TMP/trace.txt" <<'PYEOF'
import re, sys
host = open(sys.argv[1]).read()
display = open(sys.argv[2]).read()
trace = open(sys.argv[3]).read()
m = re.search(r"^REFUSED missing_ticks=\[([0-9, ]*)\].*allowance=(\d+) redundancy=(\d+)", host, re.M)
if not m or not m.group(1).strip():
    print("FAIL: no refused tick in the host log"); sys.exit(1)
missing = [int(x) for x in m.group(1).split(",")]
allowance = int(m.group(2))
redundancy = int(m.group(3))
# The host's states for the ticks after the hole are sent when it expires (allowance + 1 ticks
# after it); they reach the client one transit later, which input_redundancy ticks cover.
lo, hi = min(missing), max(missing) + allowance + redundancy
bad = False
w = re.search(r"^DISPLAY_WRONG .*ticks=\[([0-9, ]*)\]", display, re.M)
shown = [int(x) for x in w.group(1).split(",")] if w and w.group(1).strip() else []
print("REFUSED_BOUND window=[%d, %d] display_wrong_ticks=%d outside=%s" % (lo, hi, len(shown), [t for t in shown if t < lo or t > hi]))
if any(t < lo or t > hi for t in shown):
    bad = True
t = re.search(r"^TRACE_DIFF .*last=(-?\d+)", trace, re.M)
if t and int(t.group(1)) > hi:
    print("FAIL: host and client still differ at tick %s, past %d" % (t.group(1), hi)); bad = True
sys.exit(1 if bad else 0)
PYEOF
	then
		echo "FAIL: the client's wrong display of its own bot is not bounded by the allowance"
		STATUS=1
	fi
elif grep -q "^DISPLAY_WRONG .* wrong=[1-9]" "$TMP/display.txt"; then
	# Input of the first ticks that arrives after later input at the join is refused by the
	# host, and the owner's client, which simulated them, shows its bot wrong for those ticks
	# once: not a fault of the hold being tested, so those ticks (up to two after the first
	# input stored) are not counted when the host reports JOIN_REORDERED.
	FIRST_INPUT="$(sed -n 's/^JOIN_REORDERED refused=[0-9]* first_input_tick=\([0-9]*\).*/\1/p' "$TMP/host.log")"
	LIMIT="${FIRST_INPUT:--1}"
	LIMIT=$(( LIMIT + 2 ))
	if ! python3 -I - "$TMP/display.txt" "$LIMIT" <<'PYEOF'
import re, sys
limit = int(sys.argv[2])
m = re.search(r"^DISPLAY_WRONG .*ticks=\[([0-9, ]*)\]", open(sys.argv[1]).read(), re.M)
ticks = [int(x) for x in m.group(1).split(",")] if m and m.group(1).strip() else []
late = [t for t in ticks if t > limit]
sys.exit(1 if late else 0)
PYEOF
	then
		echo "FAIL: the client showed its own bot where the host never had it"
		STATUS=1
	else
		echo "NOTE: the client showed its bot wrong only on the join ticks the host refused (JOIN_REORDERED)"
	fi
fi
if [ "$OBSERVER" = "1" ]; then
	echo "observer (third player):"
	python3 -I "$ROOT/tests/display_report.py" "$TMP/host.log" "$TMP/observer.log" | grep "^RECEIVED_WRONG\|^RECEIVED_STREAM"
fi
if grep -q "SCRIPT ERROR" "$TMP/host.log" "$TMP/client.log"; then
	echo "FAIL: script errors in logs"; grep -h "SCRIPT ERROR" "$TMP/host.log" "$TMP/client.log" | head; exit 1
fi
if [ "$STATUS" -ne 0 ] || [ "${KEEP_LOGS:-0}" = "1" ]; then echo "logs kept in $TMP"; trap - EXIT; cleanup; fi
exit "$STATUS"
