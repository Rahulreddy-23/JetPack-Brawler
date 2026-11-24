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
| `dev` | `42a9f10` | 24 Nov 2026 17:40 | One reviewer commit, `3ae5003`, with two changes; both accepted (findings D-1 and D-2). `42a9f10` only merges the lead's documents commit into `dev`. |
| `geminiceo` | none | 24 Nov 2026 17:40 | Branch does not exist locally or on GitHub yet. |

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
- Verified: partly. The project sets `emulate_mouse_from_touch=false` because the sticks use
  raw touch, so the concern is plausible; `edit()` does put the field into edit mode. The
  lead could not reproduce the failure itself, because injected touches did not reach
  controls in a headless probe.
- Outcome: accepted. It is five lines, does nothing harmful if the field already handles
  touch, and a field that cannot be typed into would block the two-phone test. Must be
  confirmed on a phone.
