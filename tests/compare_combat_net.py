"""Compare what the host and the client recorded for every bot in tests/test_combat_net.gd.

Usage: python3 -I compare_combat_net.py HOST_LOG CLIENT_LOG
Exit code 0 pass, 1 fail.

Each process prints EV lines (every change of knocked_out, ko_serial or cycle_index of a bot, per
tick), a LAST line (its last recorded tick), a ROUND line and a DUMMY line. Only events at least
SETTLED ticks older than the earlier of the two last ticks are compared, so a correction that is
still on its way cannot fail the run. For every bot the two lists must be equal, and equal to what
the phase 1 test cycle predicts:
  1. a knockout (serial 1) on the tick HazardMath predicts, with health 0, cycle 0, and a respawn
     tick at the start of the next cycle (a bot knocked out once the hazard has started waits);
  2. the cycle reset on the first tick of the next cycle: back in the game with full health and
     cycle_index 1 (only the cycle reset writes cycle_index);
  3. the next knockout (serial 2) one cycle after the first, cycle 1, waiting for cycle 2.
"""
import re
import sys

SETTLED = 20
FIELD = re.compile(r"(\w+)=(\S+)")


def read(path):
    events, last, rnd, dummy = {}, None, None, None
    for line in open(path, errors="replace").read().splitlines():
        f = dict(FIELD.findall(line))
        if line.startswith("EV "):
            events.setdefault(int(f["peer"]), []).append(
                (int(f["tick"]), int(f["serial"]), int(f["out"]), int(f["respawn"]), int(f["cycle"]), int(f["health"])))
        elif line.startswith("LAST "):
            last = int(f["tick"])
        elif line.startswith("ROUND "):
            rnd = {k: int(v) for k, v in f.items()}
        elif line.startswith("DUMMY ") and "x" in f:
            dummy = (int(f["tick"]), float(f["x"]), float(f["y"]))
    return events, last, rnd, dummy


def main():
    host, host_last, host_round, host_dummy = read(sys.argv[1])
    client, client_last, client_round, client_dummy = read(sys.argv[2])
    ok = True

    def fail(message):
        nonlocal ok
        ok = False
        print("FAIL: " + message)

    if host_last is None or client_last is None or host_round is None or client_round is None:
        print("FAIL: a process printed no report")
        return 1
    if host_round != client_round:
        fail("host and client disagree on the round: %s vs %s" % (host_round, client_round))
    limit = min(host_last, client_last) - SETTLED
    peers = sorted(set(host) | set(client))
    if 0 not in peers or len(peers) < 3:
        fail("expected the host bot, a client bot and the dummy (peer 0), got peers %s" % peers)
    for peer in peers:
        h = [e for e in host.get(peer, []) if e[0] <= limit]
        c = [e for e in client.get(peer, []) if e[0] <= limit]
        print("peer %d: host %d events, client %d events (up to tick %d): %s" % (peer, len(h), len(c), limit, h))
        if h != c:
            fail("peer %d events differ:\n  host   %s\n  client %s" % (peer, h, c))
        if not h:
            fail("peer %d: no events" % peer)
            continue
        start, cycle, first, health = host_round["start"], host_round["cycle"], host_round["expect_first_ko"], host_round["max_health"]
        expected = [
            (first, 1, 1, start + cycle, 0, 0),
            (start + cycle + 1, 1, 0, start + cycle, 1, health),
            (first + cycle, 2, 1, start + cycle * 2, 1, 0),
        ]
        if h != expected:
            fail("peer %d: events differ from the test cycle:\n  got      %s\n  expected %s" % (peer, h, expected))
    if host_dummy is None or client_dummy is None:
        fail("the dummy has no position on one side: host %s client %s" % (host_dummy, client_dummy))
    elif host_dummy != client_dummy:
        fail("dummy position differs: host %s client %s" % (host_dummy, client_dummy))
    print("dummy position host %s client %s" % (host_dummy, client_dummy))
    print("PASS" if ok else "FAIL")
    return 0 if ok else 1


sys.exit(main())
