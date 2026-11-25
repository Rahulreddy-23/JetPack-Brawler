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
- [x] 1.1b-N netfox hardening. Reviewed, merged (`c69179c`): every tick of a slow frame is
      simulated, a diff is laid over the host's last state, each subject gets a full state
      at least once per interval, and effects can ask whether the host's state has arrived.
      Diff states stay off. Two follow-ups (mutation table rows, three negative tests) are
      in progress.
- [x] Fifth-player test failed about 1 run in 9; fixed and merged.
- [x] Client input packets dropped by ENet's throttle under load. Reviewed, merged: the
      throttle is held at its maximum on every connection. Shown on the Mac under CPU load
      only; real Wi-Fi between phones is untested.
- [x] A Foundation and contracts. Reviewed, merged (`afc2eee`). No gameplay rule yet; the
      game still plays as movement only.
- [ ] When a burst of a client's input packets is late, the host sends states for that bot
      that are one step behind, for every player (dev finding D-10). It is upstream netfox
      behaviour. Cause found and reproduced on demand; fix in progress as netfox patch 15.
- [ ] Device checkpoint 1 (Rahul): sticks, jetpack and dash on two phones over a hotspot.
      Build and script are ready (`docs/reviews/device-checkpoint-1.md`); not yet run.
- [x] B Combat core, hazard wiring, dummy, push window. Reviewed, merged (`a170e4b`).
- [x] C Weapons, melee, pickups. Reviewed, merged (`2ad983e`).
- [ ] D World objects and gadgets. Merged; the fix round still needs its independent review.
- [ ] E Presentation: effects wired to state counters. Reviewed and fixed; waits on the
      netfox branch for its client-side first-sight check.
- [x] F Input and HUD for fire, melee, gadget, swap. Reviewed, merged (`5f92739`).
- [x] Full test suite on `main` with B, C and F together: 48 of 48 pass with the netfox, throttle and task D changes
      (Mac, headless; nothing on a phone).
- [ ] Device checkpoint 2 (Rahul): the knockback sandbox, 10 minutes of play.
- [ ] 1.6 Dabba fight, built last.
- [ ] Phase review and `docs/reviews/phase-1-handoff.md`.

## Where work stands (25 Nov 2026, morning)

On `main`, reviewed and pushed: movement, foundation, combat core (B), weapons (C), world
objects and gadgets (D), input and HUD (F), netfox hardening (patches 1 to 13 and their
follow-ups), the ENet throttle fix, reviewer findings D-1 to D-9 and D-11. Last full suite
on `main`: 48 of 48 at `f479130`; only the tests touched by each later change were run
since.

In progress, each on its own branch, none on `main`:

1. Task D follow-ups (`worktree-agent-aaec92fe475a64453`): a bot in front of a wall is
   tested before the wall, the gadget cycle reset moves before the tick's blasts, two tests
   tightened. From the independent review of D's fix round and geminiceo G-21, G-22.
2. Pickup session and cycle resets, rocket muzzle, curved flick (a new implementer branch):
   geminiceo G-15, G-17, G-19, G-23.
3. Done and on `main` (`a73b845`): rate limit on netfox's oversized-packet warning, patch
   14 (geminiceo G-24).
4. Task E (effects), branch `worktree-agent-a0ba5c0a664836773`: last step, plus a health bar
   above every bot (product owner decision, see `docs/DECISIONS.md`).
5. Dev finding D-10 (`worktree-agent-abdc8cb18a9ad9d79`): cause found, fix in progress as
   netfox patch 15.

Then: an independent review of each fix round, merge, the full suite on everything, the
debug APK into `builds/`, and the build line in `docs/reviews/device-checkpoint-2.md`
(drafted). After that Rahul's device checkpoints, task 1.6 (Dabba), the phase review and
the handoff.

Reviewer branches last reviewed: `dev` at `782da7b`, `geminiceo` at `2afecfe`. The
10-minute check is a session-only schedule; set it up again in a new session.

Open with Rahul: whether to report the netfox defects to its maintainers (a public action).

## Gate

Rahul decides. Test: flying around the map and knocking a dummy bot into the hazard is fun
for 10 minutes, and movement syncs between two phones on one hotspot.
