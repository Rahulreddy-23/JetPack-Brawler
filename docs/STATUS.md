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
      behaviour. Cause found and reproduced on demand. Netfox patch 15: the first version
      was rejected in review (it replayed a paused player's last input); a second version
      that never invents input is in progress.
- [x] `net_blast_bomb_loss` failed about 3 runs in 16. Cause: the test read the one tick
      after the blast, and under loss the client can hold its own guess for that tick until
      the next state arrives. The game was right. The check now reads the first tick whose
      value came from the host and fails if that takes more than 4 ticks; 0 failures in 80.
- [x] Pushes are distances, as the design says: a push of P moves a grounded bot P bot
      heights, low health doubles the distance, and hits on separate ticks add as
      distances (30 bolts: 3.08 bot heights; the design's total is 3). Reviewed twice,
      merged. Known and written down: in the air pushes carry about five times as far and
      repeated hits still build up (a bolt magazine moves a hovering bot about 27 bot
      heights); to be judged on phones. Builds up to 16:59 on 25 Nov have the old weak
      pushes.
- [ ] From the authority audit: the host accepts input up to 2 seconds late and replays the
      match from there (being bounded with netfox patch 15), and three more log lines can
      be flooded by any connected device (netfox patch 16, in progress).
- [ ] `net_fx` fails about 1 run in 10 on `main`: one check reads the client's nodes a loop
      before the host's state is copied onto them. Probably the test's wait, not the
      effects; with the effects implementer.
- [ ] One 4-byte identity packet crashes the host (geminiceo G-28, confirmed). Fix in
      progress in netfox patch 16. Every build so far has it.
- [ ] Device checkpoint 1 (Rahul): sticks, jetpack and dash on two phones over a hotspot.
      Script `docs/reviews/device-checkpoint-1.md`; build of 25 Nov at `b90d525`; not yet run.
- [x] B Combat core, hazard wiring, dummy, push window. Reviewed, merged (`a170e4b`).
- [x] C Weapons, melee, pickups. Reviewed, merged (`2ad983e`).
- [x] D World objects and gadgets. Reviewed twice, merged with its follow-ups and the
      ordering fix from the last review (the cycle clean-up runs before that tick's shots).
- [x] E Presentation: effects from state counters, first sight from the host's real state,
      and a health bar that shows only while a bot's health changes. Reviewed, merged.
      Nothing in it can be judged without a phone.
- [x] F Input and HUD for fire, melee, gadget, swap. Reviewed, merged (`5f92739`).
- [x] Full test suite on `main` with A to F, netfox patches 1 to 14, the reviewer fixes and
      the push-distance correction: 52 of 52 (Mac, headless; nothing on a phone).
- [ ] Device checkpoint 2 (Rahul): the knockback sandbox, 10 minutes of play on a build with
      corrected push distances. Script `docs/reviews/device-checkpoint-2.md`; not yet run.
- [ ] 1.6 Dabba fight, built last.
- [ ] Phase review and `docs/reviews/phase-1-handoff.md` (started: both audits
      are in; their fixes are in progress).

## Where work stands (25 Nov 2026, morning)

On `main`, reviewed and pushed: movement, foundation, combat core (B), weapons (C), world
objects and gadgets (D), input and HUD (F), netfox hardening (patches 1 to 13 and their
follow-ups), the ENet throttle fix, reviewer findings D-1 to D-9 and D-11. Last full suite
on `main`: 48 of 48 at `f479130`; only the tests touched by each later change were run
since.

In progress, each on its own branch, none on `main`:

1. Done and on `main`: task D's follow-ups (a bot in front of a wall is hit before the wall,
   the object cycle clean-up, tighter end-to-end tests) and the ordering fix from their
   review.
2. Done and on `main` (`4bd6e34`): pickup session and cycle resets, rocket muzzle, curved
   flick (geminiceo G-15, G-17, G-19, G-23).
3. Done and on `main` (`a73b845`): rate limit on netfox's oversized-packet warning, patch
   14 (geminiceo G-24).
4. Done and on `main`: task E (effects) with the health bar that shows only while a bot's
   health changes (Rahul's decision, see `docs/DECISIONS.md`).
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
