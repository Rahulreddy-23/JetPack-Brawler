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

## Where work stands (written 24 Nov 2026 23:30, before a usage-limit pause)

Read this first when resuming. `main` on GitHub is at the commit that carries this note.

On `main`, reviewed and pushed: movement, foundation, combat core (B), weapons (C), input and
HUD (F), netfox hardening (patches 1 to 13), the ENet throttle fix, reviewer findings D-1 to
D-9, and the geminiceo follow-up (G-13, G-14). Last full suite on `main`: 48 of 48 with task D merged.

Not on `main` yet, in the order to finish them:

1. Task D (world objects, gadgets) is on `main`: suite 48 of 48 with it merged. Its first
   review found nothing blocking, but the fix round (`0889988..a3ffc82` on branch
   `worktree-agent-aaec92fe475a64453`) has had no independent review: that review was
   stopped before it reported, at Rahul's request before the pause. Run it again from the
   beginning and act on what it finds.
2. Netfox follow-ups, branch `worktree-agent-abdc8cb18a9ad9d79` at `1632338`: mutation table
   rows, four negative checks, and `has_authoritative_state` now takes a `Variant` and
   returns false for a freed node. Read by the lead, looks right; merge after D.
3. Task E (effects), branch `worktree-agent-a0ba5c0a664836773` at `b435e4d`. Its last step
   (merge `main`, wire `EffectsDirector.host_state_check` to `has_authoritative_state`,
   remove the catch-up limit) was stopped part-way, at Rahul's request before the pause.
   Its worktree holds an unfinished merge of `main` (conflict in `config/tuning.tres` not
   resolved) and uncommitted edits in `scripts/fx/`; nothing from the last step is
   committed. Resume the same implementer or redo the step; it had reached the mutation
   checks. Then verify and merge.
4. Full suite on `main` with everything merged, rebuild the debug APK into `builds/`, update
   `docs/reviews/device-checkpoint-1.md` or write the checkpoint 2 script.
5. Rahul: device checkpoints 1 and 2. Then task 1.6 (Dabba), the phase review and the
   handoff.

Reviewer branches last reviewed: `dev` at `beaf6cb` (later commits only merge `main`),
`geminiceo` at `60fabd3`. The 10-minute check of those branches was a session-only schedule
and was cancelled before the pause; set it up again when work resumes.

Open with Rahul: whether to report the netfox defects to its maintainers (a public action).

## Gate

Rahul decides. Test: flying around the map and knocking a dummy bot into the hazard is fun
for 10 minutes, and movement syncs between two phones on one hotspot.
