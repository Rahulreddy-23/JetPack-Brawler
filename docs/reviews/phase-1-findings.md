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
| `dev` | `3ac46a8` | 24 Nov 2026 21:01 | No reviewer changes since `78f7e99` (finding D-5); `3ac46a8` only merges `main` into `dev`. |
| `geminiceo` | `e66eee1` | 24 Nov 2026 21:01 | No commits since the audit, which is decided finding by finding below. |

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
