"""Checks the COMBAT_RESULT lines of tests/net_combat_objects.sh. Usage: host.log client.log weapon.
Exit 0 when every check passes, 1 otherwise; every failed check is printed."""
import sys

DAMAGE_TOLERANCE = 0.01
POSITION_TOLERANCE = 0.5
BOMB_FUSE_TICKS = 90
ROCKET_MAX_FLIGHT_TICKS = 10
MIN_PUSH_PX = 10.0


def read(path):
    for line in open(path):
        if line.startswith("COMBAT_RESULT"):
            return dict(part.split("=", 1) for part in line.split()[1:])
    return None


def main():
    host_path, client_path, weapon = sys.argv[1:4]
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
            check(0 <= explode - spawn <= ROCKET_MAX_FLIGHT_TICKS, "%s: the rocket exploded %d ticks after its launch" % (role, explode - spawn))
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
        moved = float(r["dummy_x1"]) - float(r["dummy_x45"])
        check(moved >= MIN_PUSH_PX, "%s: the dummy moved only %.2f px to the left in 45 ticks" % (role, moved))
    host, client = sides["host"], sides["client"]
    for key in ("spawn", "explode", "client_peer", "blasts", "dummy_hit_rises", "attacker"):
        check(host[key] == client[key], "%s differs: host %s, client %s" % (key, host[key], client[key]))
    for key in ("dummy_hp", "client_hp"):
        check(abs(float(host[key]) - float(client[key])) <= DAMAGE_TOLERANCE, "%s differs: host %s, client %s" % (key, host[key], client[key]))
    for key in ("slot_x", "slot_y"):
        check(abs(float(host[key]) - float(client[key])) <= POSITION_TOLERANCE, "%s differs: host %s, client %s" % (key, host[key], client[key]))
    for offset in (1, 10, 20, 30, 45):
        for axis in ("x", "y"):
            key = "dummy_%s%d" % (axis, offset)
            check(abs(float(host[key]) - float(client[key])) <= POSITION_TOLERANCE, "%s differs: host %s, client %s" % (key, host[key], client[key]))
    if failures:
        print("\n".join("FAIL: " + f for f in failures))
        return 1
    return 0


sys.exit(main())
