"""Compare what a client received and showed for bots with what the host finally sent.

Usage: python3 -I display_report.py HOST_LOG CLIENT_LOG
HOST_LOG has TRUTH lines (tests/test_host_late_input.gd): the last state the host sent for each
bot and tick. CLIENT_LOG has RECEIVED lines (every state that changed the client's history for a
bot, with the client tick it arrived at; a repeat of a state already held is not a line) and DISPLAY lines (the client's own bot after every rollback loop, keyed by the
client tick) from tests/test_client_display.gd. For every bot peer prints a RECEIVED_WRONG line
(states received that are not the host's final one for that tick) and, for the client's own bot,
a DISPLAY_WRONG line: how many there are, the largest distance from the host's final state in
pixels, and the ticks. A state differs when it is more than 0.01 px away. Always exits 0.
"""
import re
import sys

FIELD = re.compile(r"(\w+)=(\S+)")


def rows(path, kind):
    result = []
    for line in open(path, errors="replace"):
        if line.startswith(kind + " "):
            result.append({k: float(v) for k, v in FIELD.findall(line)})
    return result


def main():
    truth = {(int(r["peer"]), int(r["tick"])): (r["x"], r["y"]) for r in rows(sys.argv[1], "TRUTH")}

    def distance(r):
        t = truth.get((int(r["peer"]), int(r["tick"])))
        if t is None:
            return None
        return ((r["x"] - t[0]) ** 2 + (r["y"] - t[1]) ** 2) ** 0.5

    for kind, label in (("RECEIVED", "RECEIVED_WRONG"), ("DISPLAY", "DISPLAY_WRONG")):
        by_peer = {}
        for r in rows(sys.argv[2], kind):
            by_peer.setdefault(int(r["peer"]), []).append(r)
        for peer in sorted(by_peer):
            if peer < 2 and kind == "RECEIVED" and peer == 0:
                continue
            wrong, worst, total = [], 0.0, 0
            for r in by_peer[peer]:
                d = distance(r)
                if d is None:
                    continue
                total += 1
                if d > 0.01:
                    wrong.append(int(r["tick"]))
                    worst = max(worst, d)
            print("%s peer=%d of=%d wrong=%d max_px=%.3f ticks=%s" % (label, peer, total, len(wrong), worst, sorted(set(wrong))))
    # What a client sees of each bot's stream of states: ticks it received no new state for between
    # its first and its last (a repeat of a held state is not a RECEIVED line), and the biggest step between the states of two consecutive
    # received ticks against the typical step.
    by_peer = {}
    for r in rows(sys.argv[2], "RECEIVED"):
        by_peer.setdefault(int(r["peer"]), {})[int(r["tick"])] = (r["x"], r["y"])
    for peer in sorted(by_peer):
        if peer < 2:
            continue
        states = by_peer[peer]
        ticks = sorted(states)
        if not ticks:
            continue
        missing = [t for t in range(ticks[0], ticks[-1] + 1) if t not in states]
        steps = [(((states[b][0] - states[a][0]) ** 2 + (states[b][1] - states[a][1]) ** 2) ** 0.5) / (b - a)
                 for a, b in zip(ticks, ticks[1:])]
        jumps = [(((states[b][0] - states[a][0]) ** 2 + (states[b][1] - states[a][1]) ** 2) ** 0.5)
                 for a, b in zip(ticks, ticks[1:]) if b - a > 1]
        typical = sorted(steps)[len(steps) // 2] if steps else 0.0
        print("RECEIVED_GAPS peer=%d received=%d missing=%d ticks=%s typical_step_px=%.3f largest_jump_across_a_gap_px=%.3f" % (
            peer, len(ticks), len(missing), missing, typical, max(jumps) if jumps else 0.0))
    # The stream as the client lived it: every time the newest tick it had a state for moved on
    # (in the order the states arrived), how many client ticks passed since the last such
    # event, how many ticks the newest one advanced, and how far the shown position jumped.
    arrivals = {}
    for r in rows(sys.argv[2], "RECEIVED"):
        arrivals.setdefault(int(r["peer"]), []).append(r)
    for peer in sorted(arrivals):
        if peer < 2:
            continue
        # One event per client tick at which a newer state arrived: the newest tick then known.
        events, newest, last_now = [], -1, None
        for r in arrivals[peer]:
            if int(r["tick"]) <= newest:
                continue
            newest = int(r["tick"])
            if last_now == int(r["now"]):
                events[-1] = (int(r["now"]), newest, (r["x"], r["y"]))
            else:
                events.append((int(r["now"]), newest, (r["x"], r["y"])))
                last_now = int(r["now"])
        if len(events) < 3:
            continue
        silence = [b[0] - a[0] for a, b in zip(events, events[1:])]
        advance = [b[1] - a[1] for a, b in zip(events, events[1:])]
        jump = [((b[2][0] - a[2][0]) ** 2 + (b[2][1] - a[2][1]) ** 2) ** 0.5 for a, b in zip(events, events[1:])]
        worst = max(range(len(silence)), key=lambda i: (silence[i], jump[i]))
        print("RECEIVED_STREAM peer=%d events=%d typical_client_ticks_between=%d typical_step_px=%.3f longest_silence_client_ticks=%d then_advanced_ticks=%d then_jumped_px=%.3f" % (
            peer, len(events), sorted(silence)[len(silence) // 2], sorted(jump)[len(jump) // 2], silence[worst], advance[worst], jump[worst]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
