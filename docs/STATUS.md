# Status

Current stage: Prototype, phase 1. Gate not passed.

## Phase 1 tasks

- [x] 1.1 Project, config resource, netfox, grey-box Smelter, synced movement, touch and
      keyboard input, host and join-by-IP, Android debug export. Merged to `main`
      (`5135ef6`). Not yet played on a phone.
- [x] Modules built and reviewed, merged (`cbcb8e4`), not yet wired into the game: combat
      maths, hazard, impact effects, hit-test geometry.
- [ ] 1.1b-N netfox hardening that does not hurt honest play (in progress).
- [ ] 1.1b-G fixes accepted from the geminiceo audit in the game scripts (in progress).
- [ ] Experiment E1: a host-decided hit survives re-simulation (in progress). Tasks B to F
      do not start until it passes.
- [ ] Device checkpoint 1 (Rahul): sticks, jetpack and dash on two phones over a hotspot.
- [ ] A Foundation and contracts (see `docs/ARCHITECTURE.md`).
- [ ] B Combat core, hazard wiring, dummy, push window.
- [ ] C Weapons, melee, pickups.
- [ ] D World objects and gadgets.
- [ ] E Presentation: effects wired to state counters.
- [ ] F Input and HUD for fire, melee, gadget, swap.
- [ ] Device checkpoint 2 (Rahul): the knockback sandbox, 10 minutes of play.
- [ ] 1.6 Dabba fight, built last.
- [ ] Phase review and `docs/reviews/phase-1-handoff.md`.

## Gate

Rahul decides. Test: flying around the map and knocking a dummy bot into the hazard is fun
for 10 minutes, and movement syncs between two phones on one hotspot.
