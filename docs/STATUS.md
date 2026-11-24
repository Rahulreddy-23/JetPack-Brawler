# Status

Current stage: Prototype, phase 1. Gate not passed.

## Phase 1 tasks

- [x] 1.1 Project, config resource, netfox, grey-box Smelter, synced movement, touch and
      keyboard input, host and join-by-IP, Android debug export. Merged to `main`
      (`5135ef6`). Not yet played on a phone.
- [x] Modules built and reviewed, merged (`cbcb8e4`), not yet wired into the game: combat
      maths, hazard, impact effects, hit-test geometry.
- [x] 1.1b-G fixes accepted from the geminiceo audit in the game scripts. Merged (`cf94537`).
- [x] Experiment E1. Host-decided hits are idempotent; clients kept wrong values with
      netfox diff states on. See `docs/ARCHITECTURE.md`, "E1 results".
- [ ] 1.1b-N netfox hardening. Built; second fix round in progress after review: netfox
      skips ticks on frames slower than one tick, diff states merge onto the client's guess,
      and one cheap host freeze remains.
- [ ] Fifth-player test fails about 1 run in 9; fix in progress.
- [x] A Foundation and contracts. Reviewed, merged (`afc2eee`). No gameplay rule yet; the
      game still plays as movement only.
- [ ] B Combat core, hazard wiring, dummy, push window (in progress).
- [ ] C Weapons, melee, pickups (in progress).
- [ ] D World objects and gadgets (in progress).
- [ ] E Presentation: effects wired to state counters (in progress).
- [ ] F Input and HUD for fire, melee, gadget, swap (in progress).
- [ ] Device checkpoint 2 (Rahul): the knockback sandbox, 10 minutes of play.
- [ ] 1.6 Dabba fight, built last.
- [ ] Phase review and `docs/reviews/phase-1-handoff.md`.

## Gate

Rahul decides. Test: flying around the map and knocking a dummy bot into the hazard is fun
for 10 minutes, and movement syncs between two phones on one hotspot.
