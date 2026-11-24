# Decisions

Decisions Rahul made after the GDD was written. Where this file and `docs/GDD.md` differ,
this file wins.

## 24 Nov 2026

1. Phase split of the prototype (the GDD's phase diagram was not available):
   - Phase 1: project and netfox setup; synced movement (run, jetpack, dash, wall-jump) with
     touch sticks and join-by-IP on one network; knockback with 4 weapons, melee, 2 gadgets,
     a dummy bot and one hazard map; the Dabba fight.
   - Phase 2: rounds, scoring, Chaos Cards, 4 players, bots, Classic Brawl, hotspot discovery
     with a code fallback. Ends at the hotspot playtest gate.
2. Prototype content:
   - Map: Smelter.
   - Weapons: rivet gun, bolt thrower, scrap blaster, festival rocket tube.
   - Gadgets: Cooker Bomb, Spring Plate.
   - Chaos Cards: Moon Boots, Glass Cannon, Free Fuel, Ice Rink.
3. Round timing: a 3-second countdown before round 1 only. Between rounds: 2-second replay,
   5-second card pick, 1-second start (about 8 seconds). The GDD's "under 5 seconds between
   rounds" line does not apply.
4. Device testing: Rahul has two Android phones and a cable. Android debug export is set up
   in the first task.

## Lead's calls (not Rahul's decisions; correct them if wrong)

- Phase 1 uses grey-box shapes only. No art is bought or imported.
- Solo play runs as a host with no clients, so there is one movement code path.
