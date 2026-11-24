"""Compare the client bot's recorded ticks between the host log and the client log.

Usage: python3 -I compare_traces.py HOST_LOG CLIENT_LOG
Exit code: 0 pass, 1 fail, 2 inconclusive (not a pass).

A tick is compared only when all of these hold:
  - the client's row for it was a one-step re-simulation that started from a
    state received from the server (auth=1) and was really simulated (sim=1);
  - the host really simulated that tick with client input (sim=1);
  - the input the host used equals the input the client sent.
Positions on those ticks must agree to within TOLERANCE pixels.
A host stall, a client stall, or too few comparable ticks is inconclusive,
because client prediction may then differ for reasons that are not a bug.
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
    qualified, host_lacked, mismatched, worst, neutral = [], 0, 0, 0.0, 0
    for t in candidates:
        c = client[t]
        h = host.get(t)
        if h is None or h["sim"] != "1":
            host_lacked += 1
            continue
        if c["auth"] != "1":
            continue
        if inputs(c) != inputs(h):
            mismatched += 1
            continue
        qualified.append(t)
        err = ((float(c["x"]) - float(h["x"])) ** 2 + (float(c["y"]) - float(h["y"])) ** 2) ** 0.5
        worst = max(worst, err)
        neutral += neutral_dash(c)

    xs = [(float(f["x"]), float(f["y"])) for f in client.values()]
    first = xs[0]
    travelled = max(((x - first[0]) ** 2 + (y - first[1]) ** 2) ** 0.5 for x, y in xs)
    share = len(qualified) / max(len(candidates), 1)
    print("candidate ticks %d, compared %d (%.0f%%), host lacked input for %d, host/client input differed on %d"
          % (len(candidates), len(qualified), share * 100, host_lacked, mismatched))
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
