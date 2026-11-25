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
- [x] When a burst of a client's input packets was late, the host sent states for that bot
      that were one step behind, for every player (dev finding D-10; upstream netfox
      behaviour). Fixed in netfox patch 15 after two versions and three reviews: the host
      never builds on a skipped tick and never invents input; it waits up to 12 ticks
      (400 ms) for a missing input, then treats that tick as one where the bot did not
      act, and refuses input older than that. Cost, to judge on phones: a lost input or
      the end of a pause holds that bot still for everyone else for up to 400 ms, then
      it jumps.
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
- [x] From the authority audit: the host accepted input up to 2 seconds late and replayed
      the match from there. Bounded at 12 ticks by netfox patch 15. Its other finding,
      three log lines any device could flood, is fixed in patch 16.
- [x] One 4-byte packet crashed the host (geminiceo G-28, confirmed): the engine allocated a
      length taken from the packet before checking the bytes left, and every synchronised
      value went through the same call. Fixed in netfox patch 16 with a sweep of every read
      that takes a length from a packet, bounds on join packets, and limits on three log
      floods. Reviewed twice; approved for play with friends. The last stall the review
      named (malformed fixed-size values, about 1,000 log lines per packet) is fixed too.
      One more stall of the same kind was found afterwards by the external reviewer (a
      subject named by full name in a snapshot frame, G-31) and is fixed too. With no
      per-peer packet rate limit and the engine's own network layer unexamined, the game
      is not yet fit for strangers. Builds up to 21:01 on 25 Nov have the crash.
- [ ] In patch 15, the scan for an expired input gap returns the first remote player's
      instead of the earliest across players (geminiceo G-32). No effect with two phones;
      with three or more, one gap is resolved a loop late. Fix in progress.
- [ ] Device checkpoint 1 (Rahul): sticks, jetpack and dash on two phones over a hotspot.
      Script `docs/reviews/device-checkpoint-1.md`; build of 26 Nov at `1d75eaf`; not yet run.
- [x] B Combat core, hazard wiring, dummy, push window. Reviewed, merged (`a170e4b`).
- [x] C Weapons, melee, pickups. Reviewed, merged (`2ad983e`).
- [x] D World objects and gadgets. Reviewed twice, merged with its follow-ups and the
      ordering fix from the last review (the cycle clean-up runs before that tick's shots).
- [x] E Presentation: effects from state counters, first sight from the host's real state,
      and a health bar that shows only while a bot's health changes. Reviewed, merged.
      Nothing in it can be judged without a phone.
- [x] F Input and HUD for fire, melee, gadget, swap. Reviewed, merged (`5f92739`).
- [x] Full test suite on `main` with A to F, netfox patches 1 to 16, the reviewer fixes and
      the push-distance correction: 59 of 59 (Mac, headless; nothing on a phone).
- [ ] Device checkpoint 2 (Rahul): the knockback sandbox, 10 minutes of play. The build of
      26 Nov at `1d75eaf` has every phase 1 fix so far. Script
      `docs/reviews/device-checkpoint-2.md`; not yet run.
- [ ] 1.6 Dabba fight, built last.
- [ ] Phase review and `docs/reviews/phase-1-handoff.md` (started: both audits
      are in; their fixes are in progress).

## Resume here (26 Nov 2026, after the 00:55 branch check; usage limit reached)

`main` is clean at `8bccd39` and pushed. The APK in `builds/` is from `1d75eaf` (26 Nov,
00:04). Reviewer branches last reviewed: `dev` up to `076b37a` (last reviewer commit
`09018a2`), `geminiceo` at `6bd7477`; nothing new at 00:55. No agent is running. The
10-minute branch check was stopped; set it up again on resume.

Not merged: the patch 15 follow-up, branch `worktree-agent-abdc8cb18a9ad9d79` at `37e21bf`.
It contains `main` and changes 7 files (`addons/NETFOX_PATCHES.md`,
`addons/netfox/servers/rollback-simulation-server.gd`, `scripts/dev/smoke_probe.gd`,
`tests/net_late_input.sh`, `tests/net_smoke.sh`, `tests/test_hole_rule.gd`,
`tests/test_host_late_input.gd`). What it does, by the implementer's report, not yet
verified by me or the reviewer:

- fixes G-32 (earliest expired gap across all remote players);
- fixes a defect in the merged patch 15: with 75 ms latency the host refused an honest
  client's first input in 2 of 3 runs, because a just-spawned bot's seeded state looked
  like a carry-over. The build of 00:04 has this defect;
- honest test runs now assert zero refused inputs;
- implementer's suite: 59 pass.

Known and not fixed in it: under 150 ms jitter a join whose first input is 7 ticks late
can send one state and replace it (3.2 px), about 1 or 2 of 36 runs, cause not found;
`late_input` fails about 1 run in 5 with "the hold made no hole" (test design).

Order to resume: (1) send `git diff main 37e21bf -- addons scripts tests` with the task
statement to the code reviewer; (2) verify its findings; (3) merge onto `main`, run the
full suite; (4) commit, push, mark G-32 merged here and in the findings file; (5) rebuild
the APK and update the build lines in both device-checkpoint scripts.

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
5. Done and on `main`: dev finding D-10, netfox patch 15.

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
