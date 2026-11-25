# Phase 1 handoff

In preparation. Phase 1 is not finished: the Dabba fight is not built, nothing has run on a
phone, and Rahul has not judged the gate. This file is filled in as the phase review
proceeds; the summary, the list of changed files and the device test script are added when
the phase's tasks are done.

## Review so far (25 Nov 2026, `main` at `7c2da44`)

### Does every feature match the design's numbers and rules?

An independent audit compared the GDD and `docs/DECISIONS.md` line by line with the config
and the code (by reading and arithmetic; it ran nothing). About forty numbers and rules
match or are recorded first guesses. The mismatches:

1. Push distances. The GDD gives pushes as distances in bot heights; the code treated
   them as speeds. On the ground a melee hit moved a bot about 0.5 bot heights (design
   2.5), a close scrap blast 0.2 (1.5), scrap recoil 0.1 (1), a blast at its centre 2.3
   (5). At 0 health a bot went three to four times as far, where the design says twice.
   Status: being corrected (see `docs/DECISIONS.md`, lead's calls). The debug builds made
   on 25 Nov up to 16:59 have the weak pushes.
2. The Smelter's shape. The GDD calls it "tall and vertical"; it was built 40 by 16 bot
   heights, following the GDD's general arena size (about two screens wide, one and a half
   tall). The two lines of the GDD disagree. Status: open, Rahul to decide.
3. Aim assist is described in the GDD as on by default and is not built or assigned to a
   stage. Status: open, in `docs/IDEAS.md`, Rahul to decide the stage.
4. The Spring Plate launches straight up only; the GDD also allows "along its angle".
   Status: logged in `docs/IDEAS.md`.
5. Dash bullet immunity is 4 ticks (0.133 s) against 0.15 s, because it follows the dash
   time and the tick rate. Status: accepted for the prototype; logged.
6. The health bar turned red at exactly 25 health while the extra push starts just below
   it. Status: being corrected with item 1.
7. No sound of any kind (the hit clank, the empty steam pack's whistle). Status: grey-box
   prototype, as recorded; not a phase 1 item.

### Is every tuning number in the config resource?

Yes. No gameplay script holds a tuning literal. Two config entries (`weapon_slot_count`,
`gadget_slot_count`) were read nowhere and are being removed.

### Is anything in the build that phase 1 does not list?

Recorded additions: the melee button shown by default, the push window, the 45-second test
cycle with respawn, the health bar that shows while health changes, and dev-only network
simulator flags that are ignored in release builds. Not recorded before this audit: an
effects demo scene under `effects/demo/` ships in the build, although nothing can reach it.
Nothing for rounds, scoring, Chaos Cards, thinking bots, discovery or extra content exists.

Missing from phase 1: the Dabba fight (deliberately last).

### Project rules

No emoji in project files (the vendored netfox README has three), no untyped declarations,
no secrets or keystores in the tracked files, and one debug export preset with the internet
permission only.

### Authority, clean checkout and a headless run

Audit in progress.

### What was not tested

Nothing has run on a phone: touch feel, frame rate, heat, real Wi-Fi, every visual effect
and the health bar. The audit above read code and did arithmetic; it measured nothing in
the running game.
