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
| `dev` | `320df9b` | 24 Nov 2026 18:23 | No new commits since `320df9b` (finding D-3). |
| `geminiceo` | `e66eee1` (verification in progress) | 24 Nov 2026 18:23 | First commit on this branch, on GitHub only: an audit report (`docs/reviews/geminiceo-audit.md`, twelve findings plus a product review) and fixes across 20 files, written against the `dev` snapshot `320df9b`, which is older than the lead's current code. Each finding is being checked against the current code before any outcome is recorded; see "geminiceo audit" below. |

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

## geminiceo audit (`e66eee1`)

Status at 18:23: received, verification started. No finding is accepted or rejected yet.

The audit's code changes cannot be merged as they are, because they were made on an older
copy of the code than the lead's working tree (which has since had its own fix round,
including two netfox patches that overlap findings 1, 2 and 4). Accepted fixes will be
ported onto the current code with a test each.

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
