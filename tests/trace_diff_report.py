"""Print how the client bot's recorded positions differ between the host log and the client log.

Usage: python3 -I trace_diff_report.py HOST_LOG CLIENT_LOG
Prints one TRACE_DIFF line: the number of (bot, tick) pairs in which the two recordings of the client's
bot (every peer id above 1) differ by more than 0.01 px, the largest difference, the first
and last such tick, and the ticks. Always exits 0; it reports, it does not judge.
"""
import re
import sys

FIELD = re.compile(r"(\w+)=(\S+)")


def read(path):
    rows = {}
    for line in open(path, errors="replace"):
        if line.startswith("TRACE "):
            f = dict(FIELD.findall(line))
            if int(f["peer"]) > 1:
                rows[(int(f["peer"]), int(f["tick"]))] = (float(f["x"]), float(f["y"]))
    return rows


def main():
    host, client = read(sys.argv[1]), read(sys.argv[2])
    ticks, worst = [], 0.0
    for tick in sorted(set(host) & set(client)):
        dx, dy = client[tick][0] - host[tick][0], client[tick][1] - host[tick][1]
        d = (dx * dx + dy * dy) ** 0.5
        if d > 0.01:
            ticks.append(tick)
            worst = max(worst, d)
    print("TRACE_DIFF ticks=%d max_px=%.3f first=%s last=%s list=%s" % (
        len(ticks), worst, ticks[0][1] if ticks else "-", ticks[-1][1] if ticks else "-", [t[1] for t in ticks]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
