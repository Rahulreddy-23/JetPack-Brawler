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
   Status: corrected and merged after two review rounds. Measured in the game with the
   real movement code: melee 2.50, close scrap blast 1.50, bolt 0.10, blast at its centre
   5.00, recoil 1.00, twice those at 0 health, 30 bolts in a row 3.08. Left open on
   purpose and written into `docs/ARCHITECTURE.md` D10: in the air a push carries about
   five times as far, repeated hits in the air still build up, and a blast lifts a bot so
   its sideways travel follows the air figures. The debug builds made on 25 Nov up to 16:59
   have the old weak pushes.
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
   it. Status: corrected with item 1.
7. No sound of any kind (the hit clank, the empty steam pack's whistle). Status: grey-box
   prototype, as recorded; not a phase 1 item.

### Is every tuning number in the config resource?

Yes. No gameplay script holds a tuning literal. Two config entries (`weapon_slot_count`,
`gadget_slot_count`) were read nowhere and have been removed.

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

### Authority: can a client-sent value change state without the host's say?

An independent audit followed every path from a peer to the host: each remote call, each
netfox command handler, every synchronised property and its owner, and every place the
host reads a client's input.

- No client owns any state. State a client sends for a node it does not own is discarded.
- Every input the host reads is checked for type, for finite values and for length; a
  crafted input gives no extra speed, fire rate, ammo, dash, gadget or range, and nothing
  while knocked out. Several inputs for one tick: the first wins. Inputs stamped in the
  future are bounded.
- Was not validated, corrected in netfox patch 15: the host accepted input for ticks up to
  about 2 seconds in the past and replayed the match from there, so a modified client
  could withhold its input and send it with hindsight, or make the host replay 64 ticks
  every frame. Input older than 12 ticks (400 ms) is now refused.
- Was not validated, corrected in netfox patch 16: three log lines any connected device
  could trigger without limit, one of them before it is accepted.
- Found by the external reviewer and corrected in the same patch: one 4-byte packet crashed
  the host, because the engine allocates a length taken from the packet before checking
  the bytes left. Every read that takes a length or count from a packet is now checked
  first, join packets are bounded and must be plain ASCII, clock messages must have their
  exact size and type, and only fixed-size values are decoded.
- Still open, before strangers can join: there is no limit on how fast a device may send
  packets, and the engine's own network layer below netfox has not been examined.
- Noted for phase 2: leaving and rejoining gives a fresh bot at full health with no
  respawn wait, which matters once there is scoring. A modified client can aim perfectly;
  the host cannot tell.
- Not checked: the engine's own handling of bad remote calls below netfox.

### Does the game run from a clean checkout?

Yes. A fresh copy made from git imports with no error or warning, a headless host starts
and exits cleanly, and the full suite passes there: 51 of 51 (at `7c2da44`). Nothing the
game needs is untracked, and nothing is tracked that should not be (no build outputs, no
keystores). The debug APK lives in the ignored `builds/` folder on the Mac.

### What was not tested

Nothing has run on a phone: touch feel, frame rate, heat, real Wi-Fi, every visual effect
and the health bar. The audit above read code and did arithmetic; it measured nothing in
the running game.
