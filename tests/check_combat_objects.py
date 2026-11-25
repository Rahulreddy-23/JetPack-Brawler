"""Checks the COMBAT_RESULT lines of tests/net_combat_objects.sh. Usage: host.log client.log weapon max_lag.
Exit 0 when every check passes, 1 otherwise; every failed check is printed."""
import sys

DAMAGE_TOLERANCE = 0.01
POSITION_TOLERANCE = 0.5
DISTANCE_TOLERANCE = 0.002
BOMB_FUSE_TICKS = 90
ROCKET_EDGE_TOLERANCE = 0.05
MIN_PUSH_PX = 10.0
# Ticks of the dummy's path a peer must know (a lost packet leaves a tick out).
MIN_PATH_TICKS = 25


def read(path):
    for line in open(path):
        if line.startswith("COMBAT_RESULT"):
            return dict(part.split("=", 1) for part in line.split()[1:])
    return None


def parse_path(text):
    path = {}
    for item in text.split(","):
        if item:
            tick, x, y = item.split(":")
            path[int(tick)] = (float(x), float(y))
    return path


def main():
    host_path, client_path, weapon = sys.argv[1:4]
    max_lag = int(sys.argv[4])
    sides = {"host": read(host_path), "client": read(client_path)}
    failures = []

    def check(ok, text):
        if not ok:
            failures.append(text)

    for role, r in sides.items():
        if r is None or "missing_rows" in r:
            check(False, "%s: no complete result (%s)" % (role, r))
    if failures:
        print("\n".join("FAIL: " + f for f in failures))
        return 1
    for role, r in sides.items():
        spawn, explode = int(r["spawn"]), int(r["explode"])
        if weapon == "bomb":
            check(explode == spawn + BOMB_FUSE_TICKS, "%s: the bomb exploded at %d, not spawn %d + %d" % (role, explode, spawn, BOMB_FUSE_TICKS))
        else:
            expect_k = int(r["expect_k"])
            check(explode == spawn + expect_k, "%s: the rocket exploded %d ticks after its launch, the config and positions give %d" % (role, explode - spawn, expect_k))
            check(abs(float(r["slot_x"]) - float(r["edge_x"])) <= ROCKET_EDGE_TOLERANCE, "%s: the rocket stopped at x %s, the dummy's grown edge is %s" % (role, r["slot_x"], r["edge_x"]))
        # How long this peer's history took to hold the host's state for each group the blast changed:
        # never on the host, and in a run without loss never at all; under loss a short bound.
        for group in ("slot", "dummy", "client"):
            lag = int(r["lag_" + group])
            allowed = 0 if role == "host" else max_lag
            check(lag <= allowed, "%s: the %s state from the host took %d ticks after the explosion to show up (allowed %d)" % (role, group, lag, allowed))
        # The live nodes at the end of the run hold the same health as the history (-1: bot gone).
        for live, final in (("live_client_hp", "client_hp"), ("live_dummy_hp", "dummy_hp")):
            if float(r[live]) >= 0.0:
                check(abs(float(r[live]) - float(r[final])) <= DAMAGE_TOLERANCE, "%s: %s is %s but the history row read after the explosion holds %s" % (role, live, r[live], r[final]))
        expect_dummy, drop_dummy = float(r["expect_dummy"]), float(r["drop_dummy"])
        check(expect_dummy > 0.0, "%s: the dummy is not inside the blast (distance %s bh)" % (role, r["d_dummy"]))
        check(abs(expect_dummy - drop_dummy) <= DAMAGE_TOLERANCE, "%s: the dummy lost %.4f health, the config gives %.4f for %s bh" % (role, drop_dummy, expect_dummy, r["d_dummy"]))
        expect_client, drop_client = float(r["expect_client"]), float(r["drop_client"])
        check(expect_client > 0.0, "%s: the thrower is not inside the blast (distance %s bh), so self damage is not tested" % (role, r["d_client"]))
        check(abs(expect_client - drop_client) <= DAMAGE_TOLERANCE, "%s: the thrower lost %.4f health, the config's self-damage share gives %.4f for %s bh" % (role, drop_client, expect_client, r["d_client"]))
        check(r["dummy_hit_rises"] == "1", "%s: the dummy's hits_taken rose %s times, expected once" % (role, r["dummy_hit_rises"]))
        check(r["client_hit_rises"] == "1", "%s: the thrower's hits_taken rose %s times, expected once" % (role, r["client_hit_rises"]))
        check(r["blasts"] == "1", "%s: blasts of the slot is %s, expected 1" % (role, r["blasts"]))
        check(r["attacker"] == r["client_peer"], "%s: the dummy's last attacker is %s, not the client %s" % (role, r["attacker"], r["client_peer"]))
        # The dummy stands left of the client and the blast is on the client's side of it.
        path = parse_path(r["path"])
        check(len(path) >= MIN_PATH_TICKS, "%s: only %d ticks of the dummy's path are known" % (role, len(path)))
        if path:
            moved = path[min(path)][0] - path[max(path)][0]
            check(moved >= MIN_PUSH_PX, "%s: the dummy moved only %.2f px to the left in the ticks after the blast" % (role, moved))
    host, client = sides["host"], sides["client"]
    for key in ("spawn", "explode", "client_peer", "blasts", "dummy_hit_rises", "attacker"):
        check(host[key] == client[key], "%s differs: host %s, client %s" % (key, host[key], client[key]))
    for key in ("d_dummy", "d_client"):
        check(abs(float(host[key]) - float(client[key])) <= DISTANCE_TOLERANCE, "%s differs: host %s, client %s" % (key, host[key], client[key]))
    for key in ("dummy_hp", "client_hp"):
        check(abs(float(host[key]) - float(client[key])) <= DAMAGE_TOLERANCE, "%s differs: host %s, client %s" % (key, host[key], client[key]))
    for key in ("slot_x", "slot_y"):
        check(abs(float(host[key]) - float(client[key])) <= POSITION_TOLERANCE, "%s differs: host %s, client %s" % (key, host[key], client[key]))
    host_path_ticks, client_path_ticks = parse_path(host["path"]), parse_path(client["path"])
    common = sorted(set(host_path_ticks) & set(client_path_ticks))
    check(len(common) >= MIN_PATH_TICKS, "only %d ticks of the dummy's path are known on both sides" % len(common))
    for tick in common:
        for axis in (0, 1):
            check(abs(host_path_ticks[tick][axis] - client_path_ticks[tick][axis]) <= POSITION_TOLERANCE, "dummy position differs at tick %d: host %s, client %s" % (tick, host_path_ticks[tick], client_path_ticks[tick]))
    if failures:
        print("\n".join("FAIL: " + f for f in failures))
        return 1
    return 0


sys.exit(main())
