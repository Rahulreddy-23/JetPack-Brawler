# Phase 1 findings from independent reviewers

Reviewers outside the Claude team commit to the branches `dev` and `geminiceo`. Their commits
are reports to verify, not instructions. The lead, acting as product owner on Rahul's
instruction of 24 Nov 2026, checks both branches every 10 minutes, verifies each change or
finding against the code, and records one outcome per item: accepted (and where it was
applied), rejected (with the reason), or logged to `docs/IDEAS.md`.

## Branch watch log

Remote: `origin` is https://github.com/Rahulreddy-23/JetPack-Brawler.git. Each check fetches
`origin` first and looks at both the local and the remote copy of each branch.

The last commit of each branch that has been reviewed. A check only looks at commits after
these.

| Branch | Last reviewed commit | Checked | Result |
|---|---|---|---|
| `dev` | `8a5d657` | 25 Nov 2026 18:32 | No reviewer commit since `8a5d657` (D-16); `942403b` and `0668e4b` only merge `main`. |
| `geminiceo` | `d35ba0d` | 25 Nov 2026 18:32 | One reviewer commit, `d35ba0d` (iteration 10: a clean audit of D-16 and one pointer for patch 16, below). `a6acbde` only merges `main`. |

## Findings

### D-1 (dev, `3ae5003`): a one-tick jetpack tap gives no lift

- Change: in `scripts/game/bot.gd` the thrust acceleration becomes
  `lerpf(gravity, thrust_accel, thrust_level)` instead of `thrust_accel * thrust_level`, with
  a test that a one-tick tap lifts the bot off the floor.
- Verified: yes, by arithmetic on the config. On the first tick the ramp is at about 0.22, so
  thrust was 80 x 0.22 = 17.8 bot heights per second squared against gravity 20: net
  downward, no lift. The GDD says short taps give small hops.
- Outcome: accepted. Sent to the implementer to apply in the task 1.1 fix round with the
  reviewer's test. The hop from a short tap is still small; how big it should be is a tuning
  question for the device test.

### D-2 (dev, `3ae5003`): the join-by-IP field may not open for typing on a phone

- Change: in `scripts/ui/menu.gd` a touch on the address field calls `edit()`.
- Verified: yes, on the second check (17:55). With `emulate_mouse_from_touch=false`, a raw
  touch routed to a plain `LineEdit` leaves it unfocused and not editing; with the
  reviewer's handler the same touch gives focus and edit mode. (The lead's first probe
  failed to deliver touches because it did not pass local coordinates to `push_input`; the
  reviewer's test in D-3 showed the right call.)
- Outcome: accepted and applied in the task 1.1 fix round. Whether the on-screen keyboard
  then opens is still to be confirmed on a phone.

### D-3 (dev, `320df9b`): a headless test for touch editing of the address field

- Change: new `tests/test_menu_touch.gd`, which builds the menu, sends a raw touch to the
  address field through the viewport and requires focus and edit mode.
- Verified: yes. Run against the main checkout, which has the D-2 fix, it prints PASS and
  exits 0; the lead's own probe shows the same touch fails without the fix, so the test
  guards a real defect.
- Outcome: accepted. To be added to the test suite at the merge of task 1.1, with the
  suite's timeout and script-error check around it, since the test has no timeout of its
  own.

### D-4 (dev, `d91d4d0`): the device script should test aim, dash, aim with two thumbs

- Change: check 6 of `docs/reviews/device-checkpoint-1.md` now asks the tester to keep the
  left stick held and, with the right thumb only, aim, tap dash, then aim again, without
  releasing the left stick or using a third finger.
- Verified: yes, by the layout. The dash button sits on the right, above the aim stick, so
  the right thumb has to leave the aim stick to dash. Once firing exists (the aim stick held
  past its ring), dashing will interrupt firing. Whether that is comfortable is exactly what
  a phone test should answer before more buttons are added on that side.
- Outcome: accepted and cherry-picked onto `main`. If the answer on phones is "no", the dash
  button's position is a config change (`dash_button_offset_px`); moving dash to the left
  side would be a control-scheme change for Rahul.

### D-5 (dev, `78f7e99`): turn netfox diff states off in the project settings

- Change: one line in `project.godot` setting `netfox/rollback/enable_diff_states=false`.
- Verified: yes. It applies the decision already recorded after experiment E1
  (`docs/DECISIONS.md`), and the Opus reviewer of the netfox hardening confirmed the diff
  merge defect with a deterministic probe.
- Outcome: accepted. The same setting is in task A's branch and reaches `main` when task A
  is merged; not cherry-picked separately, to avoid a conflict with that merge.
- Open problem this exposes: task A measured that with diff states off the idle pool of
  world objects costs about 232 KB/s per player. Fixing the diff merge in netfox, so diff
  states can be turned back on, is now the preferred route.

### D-6 (dev, `62fa06a`): a push on a dashing bot would be erased

- Change: a note in task B's checks in `docs/ARCHITECTURE.md`: a non-bullet push applied
  during a dash must change movement on the next tick and survive the dash's exit, because
  `_tick_dash()` sets the velocity on every dash tick and again on exit.
- Verified: yes, in `scripts/game/bot.gd`. The dash writes `velocity` each tick and at exit,
  so a push written into `velocity` by the combat rules at the end of a tick is overwritten
  on the next. The ruling that blasts, melee and plates still affect a dashing bot would
  not have held.
- Outcome: accepted and cherry-picked. Rule added to the contract rulings: a non-bullet push
  on a dashing bot ends the dash. Sent to the task B implementer with the required test.

### D-7 (dev, `b7078a2`): the "match full" close could hit the wrong session or show the wrong message

- Change: in `scripts/net/session.gd` the rejected connection is remembered when the notice
  arrives, the deferred close acts only on that connection, and a host that drops the
  rejected player first still produces "Match full" instead of "The host went away"; three
  new checks in `tests/test_session_guard.gd`.
- Verified: yes. With the lead's previous version of `session.gd` the new test fails on two
  checks ("host disconnect after rejection keeps the match-full message" and "a deferred
  rejection leaves the new host active"); with the change it passes, and `net_full`,
  `net_reject` and `test_session_full` still pass. The defect was in the fix merged an hour
  earlier: the connection was captured when the deferred call ran, not when the notice
  arrived, so a player who was turned away and at once hosted could have had the new
  session closed.
- Outcome: accepted and cherry-picked onto `main`.

### D-8 (dev, `dfa59fc`): a quick flick on the aim stick did not fire

- Change: in the touch layer and `scripts/input/bot_input.gd`, crossing the fire ring records
  the aim at that moment, and the input gathered for the next network tick carries fire and
  that aim even if the finger has already lifted; the release position now updates the aim;
  a release outside the tap zone but inside the fire ring does neither melee nor fire. Six
  new checks in `tests/test_touch_input.gd`.
- Verified: yes. Fire was a level read once per network tick, so a drag past the ring and
  back off the screen between two ticks (under 33 ms, or longer at low frame rates) was
  never seen. With the lead's scripts from before the change and the reviewer's tests, the
  test fails on 6 checks, 5 of them the new ones; with the change all 293 pass, and the
  touch network, focus and HUD tests still pass.
- Outcome: accepted and cherry-picked onto `main`. Worth trying on a phone: a flick now
  fires exactly one shot.

### D-9 (dev, `beaf6cb`): scrap-blaster recoil was lost when firing during a dash

- Change: a new `Bot.finish_dash` gives the dash-exit velocity and ends the dash; the
  arsenal calls it before applying recoil when the shooter is dashing, and the combat rules'
  push now uses the same function instead of its own copy. Three new checks in
  `tests/test_weapons.gd`.
- Verified: yes. The dash code sets the velocity on every dash tick and again on exit, so
  recoil added mid-dash was overwritten: the GDD's "fire downward for an extra hop" did
  nothing during a dash. With the reviewer's test and the scripts from before the change the
  three new checks fail; with the change all 185 pass, and the movement (57) and combat
  rules (150) tests still pass.
- Outcome: accepted and cherry-picked onto `main`. It follows the existing ruling that a
  push ends a dash and that recoil is a push on the shooter. Consequence to know: firing the
  scrap blaster mid-dash cuts the dash short, so its bullet immunity ends on that tick.

### D-10 (dev, `2ce67fc`): an intermittent position mismatch under simulated jitter

- Report: one `SIM_JITTER_MS=150 tests/net_smoke.sh` run showed the client's bot 14.93 px
  from the host's on two ticks, with matching inputs and no stall; three reruns passed.
- Verified: yes, reproduced. 14 runs on `main` at `39339bc`: 13 passed with no difference,
  1 failed with 9.96 px at ticks 196 and 197. In that run the client's value for each of
  the two ticks is exactly one simulation step from the host's value two ticks earlier,
  and it is right again from the next tick. So the client was sent, and applied, two states
  for its own bot that were one tick behind the host's final history. No input was lost,
  no stall was logged and the throttle stayed at its maximum.
- Cause, found by investigation and reproduced on demand (branch
  `worktree-agent-abdc8cb18a9ad9d79`, `tests/net_late_input.sh`): it is plain upstream
  netfox, the same with an unpatched addon. When a client's input for one tick is missing,
  the host skips that bot for the tick and sends nothing, which is right. But it simulates
  the next tick as soon as that tick's own input is there, starting from the carried-over
  state, and sends the result as authoritative: one step behind. It does this for every
  following tick until the missing input arrives, then re-simulates and sends corrected
  states. Every player sees it: the owner's bot is pulled back, a third player sees a
  one-tick step backwards. If jitter delivers the stale version of a tick after the
  corrected one, the wrong value stays in the client's history, which is what the smoke
  test caught.
- How often: not on every late packet. Each packet carries the last 4 ticks of input, so a
  gap needs four or five packets in a row delayed or reordered, about 133 ms of burst.
  Measured with packets held on purpose: 4 to 8 stale states per gap and the bot shown up
  to 28.6 px wrong (57 px in three runs) for about as many frames as the gap lasted.
- Options measured: an input delay of 2 ticks made no difference. Letting the host predict
  with the last known input removed it but would repeat one-tick button presses (melee,
  swap, dash, gadget). Not building on a carried-over start state removed it in a prototype.
- Outcome: accepted. Fix in progress as netfox patch 15. First version (25 Nov): the host
  does not simulate a bot from a carried-over start state while the gap is open, and fills
  a gap that can no longer be filled with the last known input. Measured: no wrong states
  for inputs 1 to 6 ticks late, and the smoke test at 300 ms jitter went from 9 failures
  in 10 to none.
- That version was not merged. Its independent review found the fill wrong (the lead's
  design): a player who stops sending input for a second, for example with the app in the
  background, is treated like a lost packet, and on return the host replays the last input
  for the whole pause; the bot was driven about 390 px and burned a second of fuel. A
  one-tick press before a lost input was applied twice, a joining bot started 5 to 6 ticks
  late, and the fill could fire before a late input arrived.
- Second version, in progress: no input is ever invented. A gap the host has waited on for
  twice the redundancy window (8 ticks) is accepted as a tick on which the bot did not
  act, which is what netfox itself ends up with, and play continues from there. A tick
  before a bot's first input is not a gap. The smoke test's comparison rule is corrected
  in the same change.

### D-11 (dev, `782da7b`): a deflected rocket was checked against a path it never flew

- Change: the slot records where the rocket's move of this tick started
  (`rocket_step_start`, written at launch and at the start of every rocket step), and the
  contact sweep uses that point instead of rebuilding it from the end position and the
  velocity. One new check, two cases, in `tests/test_world_objects.gd`.
- Verified: yes. A melee deflect changes the rocket's velocity after it has moved for the
  tick, so "end minus one tick of velocity" pointed along the new direction: a bot beside
  the real path could be hit and a bot on it missed. With the reviewer's test and the
  scripts from before the change both cases fail; with the change all 253 checks pass, and
  the two-process object tests and the rocket blast tests at 75 ms, with and without 5%
  loss, still pass. The new field is not rollback state, which is safe here: only the host
  runs the contact rule, and the host rewrites the field on launch and on every step,
  re-simulated ones included, before the rule reads it.
- Outcome: accepted and cherry-picked onto `main`.

### D-12 (dev, `f5e09da`): the phone test script described the hit effects wrongly

- Change: in `docs/reviews/device-checkpoint-2.md`, a rivet hit is described as a flash
  only, and the hit freeze and screen shake are moved to the scrap blaster check.
- Verified against the effects code (task E, `scripts/fx/effects_director.gd`): every hit
  flashes the bot; the hit freeze needs a push of 1.5 or more, which the rivet gun (0.15)
  never reaches and a close scrap blast (6 pellets of 0.25) does; the screen shakes only
  when the player's own bot is hit, near a blast, and on a knockout. So the flash and the
  freeze are right as the reviewer wrote them, and the shake is not: shooting the dummy
  does not shake the shooter's screen.
- Outcome: accepted in part. The lead's draft was wrong on checks 1 and 2 and is corrected;
  the shake is asked about where it really happens (a knockout, a rocket at your own feet).

### D-13 (dev, `af6d2c8`): the aim line pointed one way and the action went another

- Change: one shared `Bot.input_aim_direction` gives the direction for the aim line, shots,
  melee and gadget throws: along the right stick while it is held past the dead zone,
  otherwise along the bot's facing. The arsenal and gadget code use it instead of their own
  copies, and the aim line no longer keeps the last aimed direction after the stick is
  released. One new check in `tests/test_movement.gd`, one changed in
  `tests/test_touch_net.gd`, and the phone test script asks about it.
- Verified: yes. Before the change the line kept the last aim while melee and gadgets fell
  back to the facing, so with the stick released a bomb could leave at right angles to the
  line. With the reviewer's test and the scripts from before, the new check fails; with the
  change the movement, weapons, world objects, combat rules, effects, touch and HUD tests
  and the two-process fire and smoke tests pass.
- Outcome: accepted and cherry-picked onto `main`. Where actions go is unchanged; only the
  line now tells the truth. Whether actions should instead keep the last aimed direction is
  a feel question for the phone test.

### D-14 (dev, `6bbcd11`): a shot's effect was drawn for the weapon held afterwards

- Change: the arsenal records the weapon that fired (`last_shot_weapon`, a new rollback state
  property on `Bot/Arsenal`), and the effects use it for the muzzle flash and the tracer
  instead of asking what the bot holds when the frame is drawn. One new test in
  `tests/test_fx_director.gd`; the state lists in three tests and in
  `docs/ARCHITECTURE.md` are updated.
- Verified: yes. A pickup is resolved after the arsenal's tick, so a bot that fires its last
  rocket standing on the bolt thrower's spot holds the bolt thrower by the time the shot is
  drawn, and the rocket got a tracer across the arena. The same happens whenever the frame
  shows a tick after the one that spent the weapon. With the change the effects, weapons and
  foundation tests pass (114, 197 and 122 checks); with the effects reading the held weapon
  again the new check fails; the two-process fire, effects, smoke and combat tests pass with
  the extra state property.
- Outcome: accepted and cherry-picked onto `main`. It adds one integer per bot to the state
  sent each tick. The debug APK of 16:14 does not have it.

### D-15 (dev, `6642a86`): the phone playtest should wait for the corrected knockback

- Change: documents only. `docs/reviews/device-checkpoint-2.md` and `docs/STATUS.md` now
  say that the current build is for the controls, sync and basic weapon and gadget checks,
  that the knockback and recoil parts of checks 2 to 6 and 10 need the push-distance
  correction, and that the 10-minute playtest behind the gate is to be run on a build that
  has it. The script also asks for the build's commit with the answers.
- Verified: it agrees with the phase audit's finding and with the lead's own warning in
  the script, and it is more exact about which checks are affected (the rocket's push in
  check 10 was missing from the warning).
- Outcome: accepted and cherry-picked onto `main`.

### D-16 (dev, `8a5d657`): a swing and a shot shared one direction

- Change: the arsenal records the direction of a melee swing in its own state property,
  `melee_dir`, instead of writing it into `shot_dir`. The swing's hits and its arc use
  `melee_dir`; the muzzle flash and tracer keep `shot_dir`. Two new checks in
  `tests/test_fx_director.gd`; the state lists in three tests and the architecture's state
  table are updated.
- Verified: yes. A swing on one tick and a shot on the next, aimed differently, left one
  direction for both by the time the frame was drawn, so the swing's arc was drawn along
  the shot, or the flash along the swing. On the tick itself the hits were right, because
  both were written on the same tick. With the change the effects, weapons, foundation and
  combat rules tests pass (116, 197, 122 and 150 checks) and the two-process fire, effects,
  smoke and combat tests pass; with the swing drawn from `shot_dir` again the two new
  checks fail.
- Outcome: accepted and cherry-picked onto `main`. It adds one direction per bot to the
  state sent each tick.

## geminiceo audit (`e66eee1`)

Status at 18:50: every finding was checked against the current code by an independent Opus
verifier (probes and, for the worst case, a real two-process run), then decided by the
product owner. The audit's code changes are not merged as they are: they were made on an
older copy of the code than `main`, and the verifier found that several of them are
redundant, break the network tests, or reject honest behaviour. Accepted fixes are being
ported onto `main` with a test that fails without each one, in tasks 1.1b-N (netfox) and
1.1b-G (game scripts).

On "critical" and "crash": the verifier probed Godot 4.7.2 and found that a script error or
failed `assert` inside a handler aborts that one function and the match continues; nothing
exits. The real high-severity items are the two that let one packet freeze the host (G-3b
and G-6).

| Id | Finding | Verified | Outcome |
|---|---|---|---|
| G-1 | Any peer can set the host's clock | Real, and already fixed on `main` by the sender check | Rejected as a change: the extra direction, type and loop-guard checks add nothing once the sender must be the server |
| G-2a | Future-tick bound of +64 still freezes the host | Real, already fixed on `main` with a tighter bound | Reviewer's bound rejected; ours kept and reworked in 1.1b-N so that it no longer drops honest inputs after a host hitch, with `input_delay` added |
| G-2b | `sanitize()` leaves `_auth_subjects` set | Real, harmless today | Accepted (1.1b-N) |
| G-2c | Empty snapshots are merged after sanitising | Real, low | Accepted (1.1b-N) |
| G-3a | Out-of-range property index in the sparse serializer | Reproduced: script error, handler aborts | Accepted (1.1b-N) |
| G-3b | Unbounded bitset decode | Reproduced end to end: one 300 KB packet froze the host for 2.26 s | Accepted, high priority (1.1b-N) |
| G-4 | Malformed ping or pong payload | Pong already covered; ping reproduced as an error with no state change | Accepted in part: a type check in the ping handler only (1.1b-N) |
| G-5 | Conflicting node ids trip an `assert` | Reproduced: aborts the function, no effect in release | Accepted if it stays a two-line change (1.1b-N) |
| G-6 | Zero-filled packet forces thousands of iterations; no packet size cap | Reproduced: 837 ms for 64 KB | Accepted, high priority, with a warning when a packet is dropped for size (1.1b-N) |
| G-7.1 | One suspended coroutine per peer that connects and never syncs | By reading; low | Deferred to before online play |
| G-7.2 | A stale bot's exit can erase its replacement | Real only for leave and re-host in one frame | Accepted in part: the identity check. `remove_child` rejected: it breaks the network tests with a script error in netfox's visibility filter |
| G-7.3 | netfox's server-state check only runs in `_process` | Real, not reachable from the UI | Deferred; only needed with G-7.5 as written |
| G-7.4 | A rejected fifth player can block a real one | By reading; low on a hotspot | Accepted, keeping our notice delay (1.1b-G) |
| G-7.5 | `host()` or `join()` while already active | Not reachable from the UI | Reviewer's fix rejected (calling `leave()` inside leaves the clock stopped); a guard returning an error accepted (1.1b-G) |
| G-8.1 | Touch controls on the menu take its touches | Not reproduced: buttons still receive touches | Accepted in part: hide the controls on the menu. Switching to `_unhandled_input` rejected as unnecessary |
| G-8.2 | An untracked drag republishes input | By reading; desktop dev flag only | Accepted (1.1b-G) |
| G-8.3 | Sticks stay pressed after the app loses focus | Reproduced: the next touch drove the wrong stick | Accepted, needed before the phone test (1.1b-G) |
| G-9 | Join address is unchecked | By reading; a name lookup can freeze the joiner's own phone | Accepted in part: valid IP only, and a length limit. Label clipping rejected (it can hide the address the joiner must type); port clamp rejected (it hides a bad flag) |
| G-10 | `_awaiting_samples` grows under packet loss | By reading: about 4,800 small entries in 20 minutes at total loss | Deferred |
| G-11.1 | A NaN shake strength corrupts the camera offset | By reading | Accepted, smaller: a finite check, applied by the lead when merging `effects/`. The camera validity check rejected (the shake is the camera's child) |
| G-11.2 | Knockout credit accepts a hit from a later tick | Real in `combat_ledger.gd`, which is being retired | Carried forward as a requirement on its replacement: credit only when 0 <= tick difference <= window |
| G-12 | HUD and touch controls redraw every frame | Not measured; negligible | Accepted as low priority, last item of 1.1b-G |

### geminiceo follow-up check (`60fabd3`)

Written against the lead's task 1.1 fix round as it stood at 18:38, before the fifth-player
fix and the netfox hardening merged. Each part was checked against `main` at `242e7b4`.

| Id | Finding | Verified against `main` | Outcome |
|---|---|---|---|
| G-13.1 | The capacity check counts every connected peer, so a rejected fifth peer blocks a real one for the notice window | No longer true: `Session._on_peer_join` counts `_accepted`, and a peer being turned away is not in it | Already fixed (G-7.4); no change |
| G-13.2 | During the 0.5 s notice window the rejected peer is still connected and can send commands | True by design: the window exists so the client can show "Match full" | No change. A connected peer that is not accepted can do no more than any hostile device on the hotspot, and the bounds on what one packet can cost (netfox patches 1 to 8 and 12) are now on `main` |
| G-13.3 | After the wait, the drop runs without checking the tree or that the same session is active | By reading: after a leave `get_peers()` is empty, so nothing is dropped. A wrong drop needs a re-host inside 0.5 s and a new peer drawing the same random 31-bit id | Rejected: not reachable in practice, and a session counter is more state than the case deserves |
| G-14.1 | The ping handler has no server check and casts an unchecked payload | The payload type check is on `main` (patch 7). The server check is not, and is not needed: relay is off, so a client only ever receives packets from the host | Already fixed in part (G-4); server check rejected |
| G-14.2 | The timestamp request handler has no server check | True. A client would answer the host with its own clock value, which changes nothing | Rejected, same reason as G-14.1 |
| G-14.3 | The set-timestamp handler does not check for a finite value or a second clock loop | True. Only the host can send it (sender check on `main`), and the host is trusted with the whole match. The second loop on a quick leave and rejoin before the first sync is real and already on the deferred list | Finite check rejected; the loop guard stays deferred to before online rooms |
| G-14.4 | `_awaiting_samples` leaks when pings are lost | Same as G-10 | Deferred (G-10) |

The reviewer's clean audit of `scripts/game/combat_geometry.gd` and `cast_result.gd` (NaN and
infinite inputs, zero-length segments, corner normals) is noted; no change follows from it.

### geminiceo iterations 2 and 3 (`ba1904c`, `2afecfe`)

Each finding was checked against `main` at `f479130` by an independent verifier, with a run
where one was cheap. The reviewer's own test suite gives 22 of 22 on its branch and 10
failures of 19 on `main`.

| Id | Finding | Verified against `main` | Outcome |
|---|---|---|---|
| G-15 | A bot flush against a wall fires its rocket from 16 px inside the wall | Partly: no tunnelling (the rocket explodes at once, by design), but the blast centre sits inside the wall, so self-damage is 32.7 instead of 36.0 | Accepted as is, low. Merged (`4bd6e34`) |
| G-16 | The reject timer has no tree or peer guard | Same as G-13.3; the reviewer reverted it | Rejected (already decided) |
| G-17 | The pickup cycle reset is missed when a stall skips the boundary tick | Confirmed by run: a spot stayed on cooldown up to 15 s into the next cycle | Accepted, low. Merged (`4bd6e34`), with the limit noted (the take tick is inferred from the respawn time) |
| G-18 | The HUD does not redraw on resize; divide by zero on maximum health | Not real: a Control redraws on resize, and the draw returns before the value is used | Rejected |
| G-19 | A flick that curves past the fire ring fires at the crossing angle | Confirmed by run | Accepted with a smaller fix: the reviewer's version gives an extra shot when the thumb is pulled back inside the ring between two ticks. Merged (`4bd6e34`) |
| G-20 | Reapply the 1.1b-N netfox hardening | Already on `main` as patches 1 to 13 | Already fixed |
| G-21a, b | A rocket that passes a bot and reaches a wall or its range in the same tick explodes past the bot | Confirmed by run; the blast lands at most one tick of travel past the bot (about 5 to 10 of 40 damage) | Accepted with a smaller fix on top of D-11. The independent review of task D found the same fault. Merged |
| G-21c | A deflected rocket is swept along its new velocity | Was real | Already fixed (D-11, the same code) |
| G-22 | The gadget cycle reset runs after blasts, plates and throws, and misses skipped ticks | Confirmed by run: a plate on a spawn point launches the fresh bot, a gadget thrown on the boundary tick is wiped, a stall leaves old plates | Accepted. Merged, with the ordering detail from its review (the clean-up also runs before that tick's shots) |
| G-23 | Pickups never reset between sessions | Confirmed by reading: after Leave then Host a spot can stay empty up to 45 s | Accepted, needed before the phone test. Merged (`4bd6e34`) |
| G-24 | The oversized-packet warning is not rate limited | Confirmed by run: 1000 packets printed 8003 log lines in 45 ms on the Mac; any device on the hotspot can do it | Accepted, as a new recorded netfox patch. Merged (`a73b845`, patch 14) |

The reviewer's `tests/test_security_audit.gd` is not taken as it is: several of its checks
pass on `main` without the fix they name, and two error out instead of failing. Each
accepted fix gets its own test that fails without it.

### geminiceo iteration 5 (`5dc5155`)

| Id | Finding | Verified | Outcome |
|---|---|---|---|
| G-25 | Root cause of D-10: the host marks a state authoritative although it was built on a carried-over start, and a reordered older version can overwrite the corrected one on the client | Agrees with our own investigation, which reproduced it on demand. Two details differ from what we measured: the redundancy is 4 ticks, not 3, and the snap is not one tick of about 10 px but 4 to 8 stale states and up to 28.6 px per gap | Accepted; it is D-10, and the fix in progress (netfox patch 15, bounded by the redundancy window) is the reviewer's first suggestion. The second, a per-peer send sequence so an older version of a tick cannot overwrite a newer one, is deferred to the work on diff states before online rooms |

The same commit reverts the reviewer's own HUD change (G-18, rejected) and reworks its flick
fix (G-19) so the aim is refreshed only while a crossing is still waiting for a tick. That
is the same condition our independent review asked for in our version; no change follows
for `main`. The reviewer advises not letting D-10 hold up the phone test: agreed, patch 15
runs alongside the build and does not block it.

### geminiceo iterations 6 and 7 (`4fa8884`, `8160914`)

| Id | Finding | Verified | Outcome |
|---|---|---|---|
| G-26 | Cause of the intermittent `net_blast_bomb_loss` failure: under loss the test read the client's own guess for the tick after the blast | Agrees with our own tick-by-tick evidence. The reviewer adds why the thrower's row is the fragile one: its state is sent once, after the client's input arrives, where the dummy's and the slot's go out twice | Already fixed on `main` (`b90d525`, `7c2da44`) by the same idea: read the first row that came from the host, with a bound. The reviewer's version of the test is not taken |
| G-27 | A flick that crosses the fire ring, curves while outside it and is pulled back inside before a tick fires at the crossing angle | Confirmed by run: the shot went to (1, 0) instead of up. Our fix refreshed the aim only at the lift, and only if the thumb was still outside the ring | Accepted, with the reviewer's rule: the aim follows the thumb from the crossing until a tick takes the shot. It replaces the lift-only refresh, and the earlier cases still hold (one shot for a flick, no extra shot after a pull-back or after a held shot, at four frame rates). One new check in `tests/test_touch_input.gd`, which fails without the change |

Iteration 7 audited task E and D-13 and found nothing: no network calls added, no writes
to simulation state, fixed-size effect pools, input still sanitised. Noted; no change.

Iteration 8 (`59afd33`) audited D-14, task D's follow-ups and the clean-up ordering and
found nothing. It lists G-27 as still open on its side; that fix has been on `main` since
`588a572`. Noted; no change. The reviewer could not run the two-process network tests in
its sandbox, so its audits are by reading plus the one-process tests.

### geminiceo iteration 9 (`5af3bfe`)

| Id | Finding | Verified | Outcome |
|---|---|---|---|
| G-28 | One 4-byte identity packet crashes the host: the engine's `get_utf8_string` allocates the declared length (2 GB) before checking how many bytes are left | Confirmed by run: a standalone probe on Godot 4.7.2 exits 138 (SIGBUS) on those four bytes. Any connected device can send it, before it is accepted | Accepted, highest priority. Fixed as part of netfox patch 16 (in progress), with a sweep of every other read whose length comes from the packet. Not in any build made so far |
| G-29 | A raw packet that is only the 3-byte prefix dispatches command 0 with an empty payload | By reading | Accepted, with G-28 |

The reviewer's commit is used as a reference, not cherry-picked: its files are being edited
for patch 16.

Iteration 10 (`d35ba0d`) audited D-16 and found nothing. It adds one pointer: two schema
serializers in `addons/netfox/schemas/network-schemas.gd` (arrays and dictionaries) read a
count from the packet unchecked. Neither is used by the game today. Passed to the patch 16
implementer for the decoder sweep that G-28 started.

A note for the architecture: `rocket_step_start` (D-11) is written during the rollback tick
without being registered state. That is safe because only the host reads it and rewrites
it before every read; `docs/ARCHITECTURE.md` records the exception.

The reviewer's test file is not taken as it is: against `main` it exits 1, three of its nine
checks assert nothing, and five findings have no check. Each accepted fix gets its own test
that fails without the fix.

Product advice in the audit's second part, decided by the product owner:

- "Do not build Dabba until the movement, knockback and hazard sandbox passes the 10-minute
  fun test on a real phone." Accepted. Task 1.6 (Dabba) moves to the end of phase 1, after a
  device checkpoint on tasks 1.2 to 1.5.
- "Verify touch controls on real phones before adding four more buttons." Accepted. A debug
  build and install steps go to Rahul as soon as task 1.1 is merged, before the input task
  of the next wave starts.
- "Ground braking may cancel pushes quickly; fix that feel in knockback playtesting."
  Accepted as a requirement on the combat task: a pushed bot keeps its push for a short
  config-set window instead of being braked at once, because knockback is the core of the
  design. This promotes the "recovery window" entry in `docs/IDEAS.md` into scope.
- "Keep dev and main reconciled." Accepted; the task 1.1 merge to `main` is the next step
  after the current review.
