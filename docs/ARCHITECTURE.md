# Architecture: combat, projectiles, gadgets, hazard and effects on netfox

Status: design accepted by the lead on 24 Nov 2026. Experiment E1 has been run; its results,
and the one change they force, are in the section "E1 results" below.
Nothing in this file is built yet except task 1.1 (networked movement) and the three modules
under `combat/`, `hazard/` and `effects/`. Designed by the Opus architect from the netfox
v1.49.12 source; netfox facts are summarised in
`research_notes/Foundations from successful arena games/netfox_patterns.md`.

## netfox behaviour this design depends on (read from source, not yet run)

1. On every loop tick, including re-simulated ones, the host simulates every node whose
   input is present for that tick plus every inputless node
   (`servers/rollback-simulation-server.gd`, `_get_nodes_to_simulate`). When a client's input
   for tick T arrives late, the host re-runs T..now.
2. Per tick: restore, `on_process_tick`, simulate in tree order, `after_process_tick`, record
   T+1, send T+1 (`rollback/network-rollback.gd`). A write made in `after_process_tick` is
   recorded as part of the state for T+1.
3. Recording captures every owned subject; a subject with no input for the tick is marked
   non-authoritative and is not sent to peers. The host's guesses about a client bot whose
   input has not arrived are therefore never sent out.
4. `mutate()` is not needed on the host for this design (to be confirmed by E1).
5. Despawn through liveness is local to each peer and freed about 64 ticks later, which is
   why this design avoids spawned rollback nodes.
6. Child nodes with `_rollback_tick` under a bot's RollbackSynchronizer are simulated in tree
   order after the root.
7. The latency and loss simulator is `addons/netfox.extras/network-simulator.gd` (a UDP proxy
   reading `netfox/autoconnect/*` settings, active only with the `editor` feature tag).

## Decisions

D1. Every gameplay consequence is netfox rollback state on host-owned nodes: health,
knockback, ammo, cooldowns, gadget inventory, knockout, credit and repair. netfox restores
tick-T state before every re-run of T, so recomputing T gives the same writes instead of
adding to them. Hits are applied idempotently, not "once". Rules for all simulation code
(`_rollback_tick` and the resolver): write only registered state properties; no RPCs, no
spawning or freeing, no signals to presentation; never read `NetworkTime.tick` or the default
config directly, use the `tick` argument and `MatchSettings.tuning_at(tick)`.

D2. `combat/combat_math.gd` is used unchanged. `combat/fighter_health.gd` and
`combat/combat_ledger.gd` are retired: their dictionaries are not restored by rollback, so
the host would apply a late client's hit once per re-run (2 to 5 times at normal latency) and
would keep damage from a hit that a later re-run removes. Their rules and test cases are
ported onto bot state in task B: no damage while knocked out; a push with no damage still
sets the last attacker; older ticks never replace a newer attacker; the credit window; repair
deferred to the end of the tick; the trade rule.

D3. One stateless `CombatResolver` on the host, connected to
`NetworkRollback.after_process_tick(tick)`. It runs after every bot and object has moved for
the tick and before T+1 is recorded. It collects shots, melee, gadget use, rocket contacts,
blasts, plate launches, pickups and the hazard into a list of `Hit` objects and applies them
in one pass with bots sorted by peer id, never by tree order. It returns at once on clients.

D4. Hit tests are pure geometry, never physics queries. Bots are rectangles taken from state,
the world is the arena layout's solid rectangles, bombs and rockets are circles. One file,
`combat_geometry.gd`, provides segment against rectangle, first hit against a list of
rectangles with the surface normal, and circle against rectangle. This removes the question
of stale physics queries during rollback. Bullets and thrown objects ignore thin platforms in
phase 1.

D5. Firing is the shooter's own state. `BotArsenal._rollback_tick` decides, on the client and
on the host, whether the bot fires at T from the fire input, `fire_ready_tick` and ammo, and
writes `last_shot_tick`, `shots_fired`, `last_shot_weapon`, `shot_dir`, ammo and the next ready
tick. Effects use the recorded weapon even if a pickup changes the bot's loadout that tick.
The muzzle flash uses the shot direction and the swing arc uses the melee direction, even
when both appear in the same frame.
The scrap blaster's recoil goes into the shooter's velocity there. The resolver treats
`last_shot_tick == tick` as "fired this tick". No RewindableAction and no NetworkWeapon.

D6. Rockets, bombs and plates live in a fixed pool of slot nodes created identically on every
peer (`Objects/Obj0..ObjN-1`), each owned by peer 1 with an inputless RollbackSynchronizer
and a TickInterpolator. Launching writes state into a slot: the slot range is fixed per owner
and per kind; the lowest free index is used, otherwise the slot with the oldest `spawn_tick`
(which gives "placing a third trap removes the oldest"). Objects move on the host only;
clients display host state. There is no MultiplayerSpawner, no despawn and no duplicate on
re-runs.

D7. One-shot outcomes come from counters in state (`hits_taken`, `ko_serial`, `shots_fired`,
`melee_serial`, `gadget_serial`, and per object `launches` and `blasts`). On each phone an
`EffectsDirector` compares each counter with the highest value it has seen for that node,
triggers once per increase, and records without triggering the first time it sees a node. The
shooter's own `shots_fired` and `melee_serial` are predicted, so muzzle flash and swing are
immediate. Known imperfection: the host phone, and a shooter's own muzzle flash, can show one
effect for an event a later re-run removes.
"The first time it sees a node" means, on a client, the first frame on which the node's
counters come from the host: `NetworkHistoryServer.has_authoritative_state` is true for the
node netfox registers for those properties (a bot's `Vitals` and `Arsenal`, the slot itself
for a world object) and one rollback loop has finished since, because netfox copies merged
state onto the live node only at the end of a loop. On the host a node is real at once. All
marks are cleared when a session starts and when it stops. Two known limits: a counter that
rises in that one extra loop is recorded without its effect (in practice a rocket fired into
a slot a late joiner has not been sent yet), and the check is per node, not per tick.
The health bar above a bot is fed the same way: only from real state, once per frame after
the restore, so a value that moves and returns inside a re-run never shows it. It appears
when the health seen on a frame differs from the last frame's, holds for a config time on
the frame clock, and is hidden at first sight, while knocked out and after a session reset.

D8. `round_start_tick`, and later Chaos Card entries, are plain host values sent by reliable
RPC ahead of time and read by tick. Score (phase 2) is committed on the host only for ticks
that can no longer be re-run.

D9. New timers are absolute ticks (`*_ready_tick: int`), not counting-down floats.

D10 (replaced 25 Nov 2026, revised the same day). A GDD push number is a DISTANCE in bot heights,
as the GDD says, and distances ADD. The rule, written in the header of `combat_rules.gd`: on flat
ground with a neutral stick a push of P bot heights moves the bot P bot heights; a tick's hits on
one victim are summed as distance vectors (after the low-health multiplier, 1 at 25 health or more
and 2 at 0, which multiplies the distance, so a bot at 0 health goes twice as far); and across
ticks `CombatRules.push_change` gives the bot, per axis, the launch speed for (the signed distance
its present speed would still carry it under the push window's braking) + (the new push). The
conversion is `CombatMath.launch_speed`, `v = a dt / 2 + sqrt(2 a P + (a dt / 2)^2)`, the speed
whose per-tick braking sums to P, and `CombatMath.travel_distance` is its inverse. Sideways
`a = ground_brake x push_window_control`; up and down `a = gravity`. Consequences:
- The bot's own speed, whatever gave it, counts as distance still to travel: a bot running into a
  push is slowed, one running away from it goes a little further than P, a push against an
  earlier push's motion takes its distance off, and 30 bolts of 0.1 move a bot 3.0. Adding
  speeds instead would build up without limit, because the conversion is a square root.
- Because each axis is converted on its own and almost every blast has an upward part, a blast
  lifts the bot and its sideways travel follows the air figures, not the ground ones (a push of
  2.5 at 45 degrees moved a grounded bot 6.2 bot heights sideways, and the direction is bent
  toward 45 degrees when the two decelerations are equal).
- In the air the same speed carries further, because air braking is weaker ("momentum carries"):
  about P x (ground_brake x push_window_control / air_brake) x 1.4, about 5 P today. The knob
  is `push_window_control`: lower it and pushes carry less in the air, at the cost of a longer
  window.
- Distances add exactly only on the ground. The rule measures what a bot would still travel
  with the ground window's braking, and an airborne bot slows far less between hits, so in
  the air separate pushes still build on each other: 30 bolts moved a hovering bot 26.9 bot
  heights where one push of 3.0 gives about 15, and two melee hits 8 ticks apart 26.8 where
  one push of 5.0 gives 24.9. It is bounded (under endless bolt fire the speed levels off at
  about 13.4 bh/s) and the same knob tunes it. Whether the air needs its own rule is open,
  to be judged after the phone test.
- The window covers the bot's whole sideways speed, so a small sideways push on a running
  bot opens a window of the full length for that speed (0.01 on a bot at 6 bh/s: 10 ticks),
  during which turning back is about three times slower. Dodging under fire is stiffer for
  it.
- A bot's own speed counts as distance still to travel on each axis, falling included: an
  upward blast on a bot falling at the limit leaves it falling at about half that speed.
- The window is as long as it takes to brake the bot's sideways speed away after a push or
  launch with a sideways part; a push with none (straight up, a Spring Plate) opens no window.
- While the window is open, a stick held against the motion brakes at least as hard as a released
  stick, so resisting a push never carries the bot further than letting go.
`push_speed_scale` is gone: it made every push a speed and let braking decide the distance, so
melee moved a grounded bot 0.54 bot heights, not 2.5. Retuning a brake or gravity keeps every
distance. Recoil is a push on the shooter under the same rule and is not multiplied by the
shooter's health. Loose bombs and rockets kicked by a blast are not bots: their speed is the
blast's push at their distance times `blast_object_speed_scale` (2, as before).

## State

| State | Node | Kind |
|---|---|---|
| position, velocity (with knockback), fuel, dash and the rest of movement | `Bot` | rollback state (exists) |
| health, knocked_out, respawn_tick, ko_serial, hits_taken, last_hit_push, last_hit_damage, last_attacker, last_attack_tick, knockouts | `Bot/Vitals` | rollback state, written by the resolver |
| active_slot, picked_weapon, picked_ammo, fire_ready_tick, last_shot_tick, shots_fired, last_shot_weapon, shot_dir, melee_ready_tick, last_melee_tick, melee_serial, melee_dir | `Bot/Arsenal` | rollback state, written by the bot's own tick |
| gadget_a, gadget_b, gadget_ready_tick, last_gadget_tick, gadget_dir, gadget_serial | `Bot/Gadgets` | rollback state |
| active, kind, owner_peer, position, velocity, spawn_tick, arm_tick, fuse_tick, explode_tick, landed, launches, blasts | `Objects/ObjN` | rollback state, inputless, host-owned |
| pickup spot ready_tick | `Pickups/SpotN` | rollback state, inputless, host-owned |
| round_start_tick, later card entries | `MatchSettings` autoload | host value, reliable RPC, read by tick |
| effect high-water marks | `EffectsDirector` | local to each phone |

## Interfaces fixed by task A

```gdscript
class_name Hit extends RefCounted
var victim: Bot
var attacker_peer: int
var damage: float
var push: Vector2          # bot heights per second, before the low-health multiplier
var bullet: bool           # true: ignored while the victim is dashing
var scale_push: bool = true

# CombatResolver.after_process_tick(tick), host only, bots sorted by peer id:
#   WeaponRules.collect(tick, bots, objects, solids, cfg, hits)   # task C
#   GadgetRules.collect(tick, bots, objects, solids, cfg, hits)   # task D
#   pickups.resolve(tick, bots, cfg)                              # task C
#   CombatRules.apply(tick, bots, hits, layout, cfg)              # task B

BotVitals:    is_out() -> bool; reset_for_spawn(cfg) -> void
BotArsenal:   fired_at(tick) -> bool; meleed_at(tick) -> bool; active_weapon() -> int;
              give_weapon(id, cfg) -> void; reset_for_spawn(cfg) -> void
BotGadgets:   used_at(tick) -> bool; used_id() -> int; give(id) -> bool; reset_for_spawn(cfg) -> void
WorldObjects: launch(kind, owner_slot, owner_peer, pos_px, vel_px, tick, cfg) -> WorldObject;
              slots() -> Array[WorldObject]; reset() -> void
CombatGeometry (static): segment_rect(a, b, r) -> float   # entry fraction, -1 for none
                         cast(a, b, rects) -> CastResult   # t and normal
                         circle_rect(c, radius, r) -> bool
MatchSettings: round_start_tick: int; tuning_at(tick) -> TuningConfig;
               hazard_ticks(tick) -> int; start_round(start_tick) -> void   # host only
```

## Tasks

Task A lands first and is the only task that edits shared files. B to F then run in
parallel, each in its own files against A's stubs.

- A. Foundation and contracts. Edits `bot.gd` (config by tick, early return while knocked
  out, drawing moved to a Visual child, `body_rect()`, `center()`), `bot.tscn` (children
  Vitals, Arsenal, Gadgets, Visual with HitFreeze and HitFlash; all state and input paths),
  `bot_input.gd` (fire, melee, gadget, swap vars and a `dummy` flag), the config schema and
  `tuning.tres` (a `WeaponStats` sub-resource for each weapon and every number listed in the
  rulings below, all flagged as first guesses), the arena layout (dummy spawn, hazard top,
  pickup spots, `solid_rects_px`), `main.tscn` (Objects, Pickups, Resolver, Effects,
  PartsBurst, ScreenShake, HazardVisual), `project.godot` (MatchSettings autoload, the
  vendored `netfox.extras` simulator behind dev flags `--sim-latency-ms=` and `--sim-loss=`).
  Creates `match_settings.gd`, `hit.gd`, `combat_resolver.gd`, `item_ids.gd` and typed stubs
  for every script B to F own. Implements no rule. Checks: the movement test and smoke test
  still pass; every synchronizer path resolves; no new config field is zero; the smoke test
  passes at 75 ms simulated latency; a grep finds no `NetworkTime.tick`, default-config read
  or `rpc` in simulation scripts.
- B. Combat core. Owns `bot_vitals.gd`, `combat_rules.gd`, the dummy and respawn in
  `bot_spawner.gd`. Checks: the ported ledger cases; multiplier 1 at 25 health and 2 at 0;
  applying the same tick twice from restored state gives identical results; a hazard knockout
  lands on the tick `HazardMath` predicts; a two-process run at 75 ms where host and client
  agree on the knockout tick, `ko_serial` and respawn tick.
  Also check a non-bullet push applied after a dash tick. It must change movement on the next
  tick and survive dash exit. `_tick_dash()` currently sets velocity for each dash tick and
  sets it again on exit, so a push applied only to `velocity` would be erased.
- C. Weapons, melee, pickups. Owns `bot_arsenal.gd`, `weapon_rules.gd`, `pickups.gd`. Checks:
  exact fire cadence, ammo run-down and fall-back to the rivet gun, exact recoil, nearest
  target wins, walls block, deterministic pellets, no bullet hit on a dashing bot, melee arc
  and deflect; two-process runs at 0 ms, 75 ms and 75 ms with 5 percent loss where the
  dummy's final health is `max - N x damage` on both sides, at least one fire tick was
  processed twice on the host, and each side shows exactly one hit effect per hit tick.
- D. World objects and gadgets. Owns `world_objects.gd`, `world_object.gd`, its scene,
  `bot_gadgets.gd`, `gadget_rules.gd`. Checks: rocket wall hit on the predicted tick, bomb
  explodes after exactly 3 seconds of ticks, blast push 5 at the centre and 0 at 3 bot
  heights, a third plate replaces the oldest; a two-process run at 75 ms where explosion tick
  and position match and each side shows exactly one explosion effect per launch.
- E. Presentation. Owns `scripts/fx/effects_director.gd`, `bot_visual.gd`, hazard visual
  wiring. Never writes a simulation property. Checks: one trigger per increase, none on a
  drop then rise to the same value, none on first sight, and every state property of bots and
  objects is identical before and after 120 frames of effects.
- F. Input and HUD. Owns input gathering in `bot_input.gd`, `touch_controls.gd`,
  `input_actions.gd`, `hud.gd`. Fire when the aim stick passes the outer ring; a quick tap on
  the aim stick and the separate melee button each latch melee for one tick; gadget button;
  weapon swap icon; health, weapon, ammo and gadgets on the HUD.

## Rulings on the architect's open questions (lead and product owner)

1. Push units: D10 stands. Only bullets miss a dashing bot (GDD: bullet immunity); blasts,
   melee and plates still affect it.
2. Phase 1 has no crates. The three pickup weapons and the Spring Plate come from fixed
   pickup spots on the map, which the GDD's Combat section already describes.
3. Phase 1 has no rounds. The hazard runs on a repeating 45-second test cycle (rises from 30
   to 45 seconds, then everything resets), and a knocked-out bot respawns after a short
   config delay. Both are test scaffolding that phase 2 replaces with rounds.
4. Blasts push and damage everyone in range, the owner included. Self-damage is scaled by a
   config value (first guess one half) so a rocket jump costs health without ending the round.
5. Plates launch whoever steps on them, the owner included, and a plate can be destroyed by a
   bullet, as the GDD's trap rules say. Bombs and rockets collide with solids only in phase 1.
6. Plate launches are decided by the host.
7. Weapon damage, fire rate and ammo are first guesses in the config, set so the bolt thrower
   takes about one second to empty a full health bar at mid range.
8. A bomb or rocket that is punched or shot away belongs to whoever deflected it, for credit
   and for arming.
9. The modules stay at `res://combat`, `res://hazard` and `res://effects`.

## Contract rulings after the review of task A (24 Nov 2026)

- netfox simulates every inputless node on every peer. A world-object slot changes state
  only where it is the multiplayer authority, and an inactive slot is left unchanged
  everywhere.
- Launching a rocket is task C's. Everything a world object then does is task D's: motion,
  contact, arming, the fuse, the blast and its hits, for rockets as well as bombs and
  plates. Task C never writes slot state directly; it calls methods on `WorldObjects` that
  task D fills: a query for the objects a bullet or melee arc can reach, `deflect` (the
  deflector becomes the owner for credit and arming) and `destroy` (a bullet on a plate).
- `Gadgets` has one more state property than the table lists: `last_gadget_id`, because the
  gadget is consumed on the tick it is used.
- The dummy has peer id 0 (never -1, which is `NO_PEER`) and a dedicated bot slot equal to
  `max_players`, with no world-object range. It is not counted against `max_players`.
- `Arsenal` and `Gadgets` ticks do nothing while the bot is knocked out.
- Knockout credit requires `0 <= tick - last_attack_tick <= credit window`.
- A push that lands on a dashing bot ends the dash: the combat rules set the bot's remaining
  dash time to zero when they apply a non-bullet push, so the push moves the bot on the next
  tick. Without this the dash code overwrites the velocity every dash tick and again on
  exit, and the push would be lost (dev finding D-6).
- Positions when an effect fires: a bot is not moved on the tick it is knocked out (respawn
  moves it later), and an exploded object stays where it exploded on its blast tick, so
  effects can read the position on the frame a counter rises.
- Effect marks are cleared when a session starts and stops, and a node counts as first seen
  only once its counters come from real state (on a client, state received from the host).
- Tracers are drawn only for single-line weapons (rivet gun, bolt thrower). The scrap
  blaster and the rocket tube show a muzzle flash only.
- The hazard's floor and top in pixels come from one helper on the arena layout, used by the
  combat rules and by the picture.
- A Spring Plate launches: a hit flagged as a launch replaces the victim's vertical speed
  with the plate's and adds the horizontal part, so a falling bot leaves at the plate's
  speed and a running bot keeps its run.
- A push that ends a dash first gives the bot its normal dash-exit speed, then adds the push as a distance on top of what that speed still carries (D10).
- A tick's hits on one victim are summed in a fixed sorted order, so the result does not
  depend on the order they were collected.
- In the phase 1 test cycle a bot knocked out once the metal has started rising waits for
  the next cycle to respawn.
- Bullets pass through a dashing bot and can hit a bot behind it.
- Melee does not reach through solid walls.
- Recoil is a push on the shooter and opens the shooter's push window.
- An object launched overlapping a solid is an immediate contact. A rocket's range is
  enforced by the world-object rules.
- Swap and melee are one-tick pulses from the input layer. This is safe while no bot is
  simulated on a repeated input; when AI bots write inputs directly (phase 2), add
  previous-input state for both.
- The push window uses one control factor for braking and steering, on the ground and in
  the air. Jetpack thrust is not reduced. Its length is not a setting: it lasts exactly until
  the push's speed is braked away at the window's rate (`CombatRules.push_window_ticks`), so
  the full brake never cuts a push short.
- Pushes in the config are the GDD's numbers, distances in bot heights; D10 converts every push,
  recoil included, into a speed. In the air the same speed carries further, because air braking
  is weaker ("momentum carries").
- Nothing is in the metal before the hazard's start time (`HazardMath.is_in_metal`), so float error
  in a bot's resting position on the floor can never knock it out before the hazard starts.
- `Vitals.last_hit_push` is the tick's summed push distance in bot heights (a plate launch adds
  its speed); the hit freeze threshold is in the same unit.
- Pool and pickup synchronizers re-register on server start, so a phone that was a client
  and then hosts sends their state.

## Contract rulings after the review of task D (24 Nov 2026)

- In the phase 1 sandbox a bot gets one Cooker Bomb on every spawn and respawn. The GDD's
  "starts each round with one" arrives with rounds in phase 2.
- When a bot's bomb or rocket range is full, the oldest object is replaced without a blast.
  The GDD's "third removes the oldest" is about traps.
- A rocket is not a bullet: it explodes on a dashing bot. Its contact with bots is a swept
  test over the tick's motion.
- A slot already marked to explode this tick is skipped by the bullet and melee queries, so
  a shot reaches the bot behind it.
- Every rocket has a finite lifetime, a deflected one with no speed included.
- The pool and its send bookkeeping reset when a session starts and stops, on host and
  client.
- A plate that cannot be pushed clear of solids is placed at the thrower's position; a used
  gadget is never lost.
- Traps are drawn in their owner's colour. Bombs and rockets stay neutral. Blink timing and
  colours are presentation constants in the draw code, not tuning numbers.
- One exception to "all gameplay values are rollback state": a rocket slot's
  `rocket_step_start` (where this tick's move began) is plain host-side data. Only the host
  reads it, in the contact rule, and the host rewrites it at launch and at the start of
  every rocket step, re-simulated ones included, before that rule runs.
- On the tick a rocket reaches a wall or its range, a bot on its path is still tested first.
- The test cycle's reset of gadgets and objects happens before that tick's blasts, plates
  and throws, and is keyed on the cycle number so a skipped boundary tick is not missed.

## Experiments before tasks B to F start

- E0. The vendored simulator runs headless with the dev flags and the client's measured
  round trip is about twice the configured latency. If the `editor` feature tag blocks it,
  copy its proxy loop (MIT) into `scripts/dev`.
- E1. A throwaway spike: `hp` as state on the bot, a trivial resolver at
  `after_process_tick` that subtracts 1 and adds a push when the shooter fired this tick and
  the target is in range, a client autopilot firing 10 shots at the dummy at 75 ms. Pass:
  final `hp` is `max - 10` on host, client and a second client; at least one fire tick was
  processed twice on the host; the change appears exactly at T+1; it works without
  `mutate()`. Variant: the host shoots the client's bot, the client's reconciled trace matches
  the host's, and the client never receives a hit that is absent from the host's final trace.
- E2. On a budget phone (Rahul): the `netfox/Rollback loop duration (ms)` monitor with 5 bots
  and the full object pool.

## E1 results (24 Nov 2026)

Run as a throwaway spike (branch `worktree-agent-a0e740ce9169c5afb`, commit `f8fe07b`, not
merged): host, two clients and a dummy, 6 runs per configuration at 0 ms and at 75 ms
one-way simulated latency, some with 5 percent loss.

Confirmed on the host:

- A hit decided in `after_process_tick` is applied idempotently. In every run the host's
  settled trace shows health falling by exactly 1 on the tick after each fire tick and
  nowhere else, with and without `mutate()`. Fire ticks were processed up to 4 times each.
- A hit decided from a stale position is removed when the victim's late input arrives
  (scenario 4, 6 of 6 at both latencies), and the removed hit never reached a client.
- Children run in tree order after the root. Resolving inside the shooter's own tick gives
  results that depend on tree order, which supports decision D3.

Not confirmed on clients:

- With netfox's diff states on (the default), clients kept wrong values for a property that
  changes rarely. The dummy's health trace matched the host's on a client in 0 of 6 runs at
  75 ms, and in one run a client showed the wrong health until the process ended. Cause,
  from the source and from logs of what the host sent: a diff carries only what changed
  relative to the host's own sent history and is merged on top of the client's local guess
  for that tick, which is then marked authoritative; and periodic full states rarely include
  client-input bots.
- With `netfox/rollback/enable_diff_states=false`, health and position traces matched on
  every client in 18 of 18 runs at 75 ms. Cost: about 78 KB/s received per client with 4
  bots, against about 11.5 KB/s with diffs on; about 157 KB/s sent by the host.
- Claim 3 above is only true for a bot whose own input is missing. A host-owned subject that
  depends on another peer's late input (the dummy, and later rockets, bombs and pickups) is
  sent with its first-pass value and corrected afterwards. With diffs off the correction
  arrives within about 2 ticks.

Decision (lead): the prototype runs with diff states off. Correct replication matters more
than bandwidth on a hotspot. Before online rooms, either fix the diff merge in the addon or
measure and accept the data cost; this is on the "before online play" list.

Consequence for effects (D7): a client can briefly show an effect for a value that the host
corrects a tick or two later. Counters and the high-water mark keep it to one false
trigger; it is cosmetic.

Measured at 75 ms with 4 bots: the host re-simulated about 3 ticks per loop on average
(worst 7, or 20 with 5 percent loss). Not measured: 5 bots, 150 ms, a real phone.

The spike's latency proxy (`scripts/dev/net_sim.gd`, flags `--sim-latency-ms=` and
`--sim-loss=`) is the starting point for task A's simulator; netfox's stock simulator node
cannot be used because it creates its own connection.

## Risks

- The design relies on how netfox 1.49.12 re-simulates and records. An addon upgrade needs E1
  rerun as a regression test.
- No shooter favouring: players see others about one round trip behind and must lead their
  aim. Fine on a hotspot, poor at 150 ms.
- A push reaches the victim's own bot through reconciliation, so it snaps about two one-way
  latencies after the hit, and a rocket jump has the same lag. Judge on phones.
- Ground braking may cancel pushes quickly and make them feel weak. Tuning.
- A full pool replaces the oldest live object; size the per-kind counts above fire rate times
  lifetime.
- Bandwidth estimate, to be measured: about 20 KB/s per client and 60 KB/s up from the host
  at 4 players.
