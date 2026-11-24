"""Compare the client bot's recorded ticks between the host log and the client log.

Usage: python3 -I compare_traces.py HOST_LOG CLIENT_LOG [--settled TICKS]
Exit code: 0 pass, 1 fail, 2 inconclusive (not a pass).

A tick is compared only when all of these hold:
  - the client's value for it came from re-simulating from a state received
    from the server: either one step (auth=1) or a short run of consecutive
    ticks that started from such a state (root);
  - the host really simulated every tick of that run (sim=1);
  - the input the host used on every tick of the run equals the input the
    client sent.
Positions on those ticks must agree to within TOLERANCE pixels.
A measured disagreement on comparable ticks is a failure, whatever else happened. Without
one, a host stall, a client stall, or too few comparable ticks is inconclusive, because
client prediction may then differ for reasons that are not a bug.

With simulated latency the client rarely re-simulates a tick from a state it has just
received, so the rule above finds nothing to compare. --settled TICKS then replaces it:
every client tick that is at least TICKS older than the client's last one is compared,
provided the host really simulated it and used the same input on that tick. By then the
host's corrections have arrived, so the client's final value must equal the host's.
"""
import re
import sys

TOLERANCE = 0.01          # pixels
MIN_QUALIFIED = 0.8       # fraction of candidate ticks that must be comparable
MIN_MOVE = 200.0          # pixels the client bot must travel
FIELD = re.compile(r"(\w+)=(\S+)")


def read(path):
    rows, stall, text = {}, None, open(path, errors="replace").read()
    for line in text.splitlines():
        if line.startswith("TRACE "):
            f = dict(FIELD.findall(line))
            if f["peer"] != "1":
                rows[int(f["tick"])] = f
        elif line.startswith("STALL "):
            f = dict(FIELD.findall(line))
            stall = int(f["frames"]) + int(f["floor_jumps"])
    logged = "stalled" in text.lower()
    return rows, stall, logged


def inputs(f):
    return tuple(f[k] for k in ("mx", "my", "ax", "ay", "jet", "dash"))


def neutral_dash(f):
    return f["dash"] == "1" and float(f["mx"]) == 0.0 and float(f["my"]) == 0.0


def main():
    settled = int(sys.argv[sys.argv.index("--settled") + 1]) if "--settled" in sys.argv else None
    host, host_stall, host_logged = read(sys.argv[1])
    client, client_stall, client_logged = read(sys.argv[2])
    if not host or not client:
        print("FAIL: no TRACE rows for the client bot")
        return 1

    active = [t for t, f in client.items()
              if float(f["mx"]) != 0.0 or float(f["my"]) != 0.0 or f["jet"] == "1" or f["dash"] == "1"]
    if not active:
        print("FAIL: the client sent no scripted input")
        return 1
    candidates = [t for t in range(min(active), max(active) + 1) if t in client and client[t]["sim"] == "1"]
    if settled is not None:
        candidates = [t for t in candidates if t <= max(client) - settled]
    qualified, strict, host_lacked, mismatched, worst, neutral = [], 0, 0, 0, 0.0, 0

    def same_inputs(first, last):
        # The host really simulated every tick of the run and used what the client sent.
        for u in range(first, last + 1):
            h, c = host.get(u), client.get(u)
            if h is None or c is None or h["sim"] != "1" or inputs(c) != inputs(h):
                return False
        return True

    for t in candidates:
        c = client[t]
        h = host.get(t)
        if h is None or h["sim"] != "1":
            host_lacked += 1
            continue
        if settled is not None:
            # Settled mode: the client's final value for this tick, same input on this tick.
            if not same_inputs(t, t):
                mismatched += 1
                continue
        else:
            root = int(c["root"])
            if root < 0:
                continue
            # One-step: the tick started from a received server state. Run: it started
            # from one a few ticks earlier and every input in between was identical.
            if not same_inputs(root + 1, t):
                mismatched += 1
                continue
        qualified.append(t)
        strict += c["auth"] == "1"
        err = ((float(c["x"]) - float(h["x"])) ** 2 + (float(c["y"]) - float(h["y"])) ** 2) ** 0.5
        worst = max(worst, err)
        neutral += neutral_dash(c)

    xs = [(float(f["x"]), float(f["y"])) for f in client.values()]
    first = xs[0]
    travelled = max(((x - first[0]) ** 2 + (y - first[1]) ** 2) ** 0.5 for x, y in xs)
    share = len(qualified) / max(len(candidates), 1)
    print("candidate ticks %d, compared %d (%.0f%%; %d of them one step from a received state), host lacked input for %d, host/client input differed on %d"
          % (len(candidates), len(qualified), share * 100, strict, host_lacked, mismatched))
    print("worst position difference on compared ticks %.4f px, client bot travelled %.1f px, neutral-stick dash ticks compared %d"
          % (worst, travelled, neutral))
    print("stall evidence: host stalled-frames+floor-jumps=%s logged=%s, client stalled-frames+floor-jumps=%s logged=%s"
          % (host_stall, host_logged, client_stall, client_logged))

    if travelled < MIN_MOVE:
        print("FAIL: the client bot did not move enough")
        return 1
    if worst > TOLERANCE:
        late = [t for t in qualified if (((float(client[t]["x"]) - float(host[t]["x"])) ** 2 + (float(client[t]["y"]) - float(host[t]["y"])) ** 2) ** 0.5) > TOLERANCE]
        print("FAIL: host and client positions disagree on ticks with identical input, first at tick %d" % late[0])
        return 1
    if host_stall or client_stall or host_logged or client_logged:
        print("INCONCLUSIVE: a stall was seen; prediction may differ for reasons that are not a bug")
        return 2
    if share < MIN_QUALIFIED or neutral == 0:
        print("INCONCLUSIVE: too few comparable ticks (need %.0f%% and a neutral-stick dash)" % (MIN_QUALIFIED * 100))
        return 2
    print("PASS")
    return 0


sys.exit(main())
