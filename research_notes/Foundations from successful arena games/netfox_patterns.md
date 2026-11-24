# netfox v1.49.12 patterns for weapons, projectiles, knockback and match settings

Source: netfox clone at tag v1.49.12, commit 6410867 (`addons/netfox/plugin.cfg`
version="1.49.12"). Every claim comes from that source tree unless it is marked as inference;
release notes were read from the v1.49.12 GitHub release because the repo has no CHANGELOG.
Paths are relative to the netfox repository. Written up by the lead from the researcher's
report on 24 Nov 2026; the researcher did not read every doc or example line by line (noray,
schema internals, and the rollback-npc, input-prediction and state-machine examples were
skipped).

## Two points before the details

- GDD wording versus netfox. GDD "Tech approach" says "Shooter-style networking, not
  fighting-game rollback" and "Three layers of physics" says gameplay objects are "simulated
  by the host". netfox's documented weapon and projectile patterns run inside the rollback
  loop and let clients predict hits. Lead's call (docs/DECISIONS.md): the host alone decides
  hits, damage and knockouts; each phone predicts only its own bot's movement and the look of
  its own shots.
- Two doc-versus-source mismatches were found: the NetworkWeaponHitscan3D doc (section a)
  and a Forest Brawl snippet in the mutations tutorial (section c).

## a. Hitscan and fast bullets

Two mechanisms exist:

- RewindableAction (core netfox, no longer experimental as of this release). The documented
  pattern for server-authoritative firing that clients predict. Each peer predicts "did I
  fire on tick T" and runs the hit logic in `_rollback_tick`; the host broadcasts which ticks
  were really active; a misprediction returns as `CONFIRMING` or `CANCELLING` on that tick and
  triggers a resimulation from it.
- NetworkWeapon / NetworkWeapon2D / NetworkWeapon3D / NetworkWeaponHitscan3D in
  netfox.extras. RPC-based, outside rollback, the older approach. There is no 2D hitscan
  class.

Evidence:

- `docs/netfox/nodes/rewindable-action.md` ("Predicting events", "Performing events"): call
  `set_active()` on every rollback tick; apply game-state changes for both `ACTIVE` and
  `CONFIRMING`; spawn only in `CONFIRMING` and undo in `CANCELLING`; use `mutate()` to
  register nodes that must re-run; use `has_confirmed()` in `after_tick_loop` for sounds and
  effects.
- `addons/netfox/rewindable-action.gd`: the authority sends its active-tick set through
  `_submit_state` (`authority`, `unreliable_ordered`); other peers queue differences and
  `_before_rollback_loop` calls `NetworkRollback.notify_resimulation_start(earliest_change)`.
  Release note: "chore: Remove @experimental tag from RewindableActions (#680)".
- `examples/rollback-fps/scripts/player-weapon.gd`: `fire_action.set_active(input.fire and
  _can_fire())` runs only when `not rollback_synchronizer.is_predicting()`; `_fire()` raycasts,
  calls `collider.damage()` and `NetworkRollback.mutate(result.collider)`; `last_fire` is a
  state property. `examples/forest-brawl/scripts/brawler-weapon.gd` warns: "DO NOT set
  RewindableAction from a predicted tick, it will conflict with server auth".
- `addons/netfox.extras/weapon/network-weapon.gd`: `fire()` spawns locally then sends
  `_request_projectile.rpc_id(authority, id, NetworkTime.tick, data)`; the server checks
  `_can_peer_use`, `_can_fire`, `_is_reconcilable`. `_request_projectile` sets `_fired_tick`
  from the client's claimed tick and does not check it.
- Mismatch: `network-weapon-hitscan-3d.gd` `fire()` never calls `_weapon.fire()`, so no RPC is
  sent, although `docs/netfox.extras/guides/network-weapon.md` says "Reconciliation is handled
  under the hood".

Recommendation: do not use NetworkWeapon2D (its fired tick is an unchecked client value).
Keep cooldown and ammo as state properties and trigger effects from confirmed events.

## b. Slow, deflectable projectiles (rockets, the 3-second Cooker Bomb)

Forest Brawl spawns bombs locally on every peer inside the weapon's `_rollback_tick` and
simulates each under a PredictiveSynchronizer, which keeps local history and sends nothing.
Nothing authoritative corrects a bomb's position. The docs recommend PredictiveSynchronizer
for projectiles that "behave very predictably" and RollbackSynchronizer "for objects that need
to interact with other objects in rollback". A deflectable bomb interacts, so a host-owned
RollbackSynchronizer with no inputs is the better fit.

Evidence:

- `examples/forest-brawl/scripts/brawler-weapon.gd` (`_spawn()`),
  `scenes/bomb-projectile.tscn` (PredictiveSynchronizer state `:position`, `:distance_left`,
  `:ghost_cooldown`; TickInterpolator on `:position`), `scripts/bomb-projectile.gd`
  (`force_shapecast_update()`, `cast_motion`, `synchronizer.despawn()`, `_rollback_spawn` /
  `_rollback_despawn`).
- `docs/faq.md` ("When should I use RollbackSynchronizer vs. ...");
  `docs/netfox/nodes/predictive-synchronizer.md` ("No networking - Operates entirely
  locally"; a node managed by both synchronizers is "not supported").
- `docs/netfox/tutorials/using-rollbacksynchronizer-without-inputs.md`: an inputless node is
  simulated on the server for new ticks only, and on clients never unless prediction is
  enabled.
- `addons/netfox/servers/network-identity-server.gd`: networked nodes are identified by node
  path, so a networked projectile needs the same path on every peer.
- Spawn timing: both synchronizers default `spawn_tick` to `NetworkRollback.tick + 1`, defer
  `process_settings`, and request resimulation from `spawn_tick` on the next loop.
  `rollback-simulation-server.gd` `register()` asserts the node is inside the tree.

Trade-offs at 30 Hz and 150 ms (inference): a PredictiveSynchronizer bomb costs no bandwidth
but any divergence lasts until it explodes, and a melee deflect depends on another player's
timing, which clients learn 2 to 3 ticks late. A host-owned RollbackSynchronizer bomb costs
about one transform and velocity per tick per live bomb and snaps clients to the host's path.
Resimulation depth at 150 ms is about 2 to 3 ticks, far inside `history_limit` 64.

Recommendation: rockets and Cooker Bombs as RollbackSynchronizer nodes with no input
properties, owned by peer 1, spawned on the host with a deterministic name (owner id plus
spawn tick) and added on clients through a MultiplayerSpawner. Despawn with `despawn()`,
never `queue_free()`.

## c. Knockback on another player's rollback body

Apply the push inside a `_rollback_tick`, on the hit tick, computed only from rollback state,
to a state property (`velocity`). Restore runs before every resimulated tick, so re-applying
the push on a resimulation does not double it. Anything applied outside rollback (an RPC
handler, `_process`) is overwritten by the next restore. Writing to another entity needs
`NetworkRollback.mutate(victim)`, an API still marked `@experimental`.

Evidence:

- `docs/netfox/tutorials/modifying-objects-during-rollback.md`: without `mutate()` a shove on
  a node that is not simulated, or already simulated, "will not be saved to history".
- `addons/netfox/rollback/network-rollback.gd`: `mutate()` records the minimum tick per target
  and is cleared at the end of every `_rollback()`; `_rollback()` restores state for every
  tick, then simulates and records.
- `addons/netfox/servers/network-history-server.gd`: state counts as authoritative only on
  the owner and only when not predicting; "Never overwrite auth data".
- `addons/netfox/servers/data/snapshot.gd` `sanitize(sender)` drops incoming state for
  subjects the sender does not own, so clients cannot inject state.
- Mismatch: Forest Brawl's `brawler-controller.gd` pulls forces itself in `_rollback_tick`
  (`for displacer in Displacer.overlapping(self): displacer.apply_to(self)`) before its
  `is_predicting()` early return, unlike the tutorial snippet.

Recommendation: keep `velocity` and any dash or stun timers in the bot's state. Make blasts
and melee "push sources" that live in rollback, and have each bot sum them inside its own
`_rollback_tick` (the Forest Brawl pattern, no mutate needed). The low-health push rule then
reads `health` from the same tick's state.

## d. Health, ammo, held weapon

The source shows both patterns and names no preferred one:

- Rollback state (`examples/rollback-fps/characters/player.tscn`): `:health`, `:deaths`,
  `last_fire` are state properties; damage is predicted and the host corrects it.
- Plain host state (`examples/multiplayer-fps/scripts/player.gd`): health changes only where
  `is_multiplayer_authority()` holds and is replicated by MultiplayerSynchronizer.
- Forest Brawl keeps scores outside rollback, sent by reliable RPC
  (`scripts/score-manager.gd`).

What breaks with health in rollback state: mispredicted one-shot consequences (death effects,
sounds, kill credit, score) must be tied to `is_fresh`, `has_confirmed()` or input-submission
checks; reference-type values leak between ticks (`docs/faq.md`: "Values passed by reference
are not recommended"); any write from another entity needs `mutate()`.
`docs/netfox/guides/network-rollback.md` ("Input Submission Status") says to delay "hard to
reverse" outcomes such as death using `get_latest_input_tick` / `has_input_for_tick`.

Recommendation: health, ammo, held-weapon id, gadget counts and fuel in rollback state as
plain ints or floats, because push depends on health and firing depends on ammo inside the
simulation. Score, knockout credit and Chaos Card picks stay outside rollback as host-only
values sent by reliable RPC. Commit a knockout only on the host, after inputs for that tick
have arrived.

## e. Lag compensation

There is no separate rewind API for hit checks. Compensation is implicit: when the host gets
a client's input for tick T it resimulates from T with every subject restored to its tick-T
value, so the shot is checked against the host's own history at T. This does not favour the
shooter (`docs/faq.md`: "favoring the shooter is not trivial to implement").

Physics queries during rollback see stale transforms
(`docs/netfox/tutorials/rollback-caveats.md`, "Physics updates"); the documented workaround is
for PhysicsServer3D only and the 2D equivalent was not determined from source. An experimental
"Rollback No More" branch ships only as `*.rnm.zip` release assets with no documentation; it
is not in the cloned addons.

Recommendation: accept the implicit compensation. Build hit tests on geometry from rollback
state, not on Area2D overlap signals.

## f. Chaos Cards and a hazard that change at an exact tick

Make every rule value a function of the tick being simulated: `settings_at(tick)` or
`hazard_level(tick - round_start_tick)`. Read it with the `tick` argument of `_rollback_tick`,
never `NetworkTime.tick` and never a mutable "current" value. The host sends
`(card_id, start_tick)` and `round_start_tick` by reliable RPC ahead of time. If a change
arrives after its start tick, call `NetworkRollback.notify_resimulation_start(start_tick)` in
`before_loop`; this works only while `start_tick >= history_start` (current tick minus 64 by
default).

Evidence: `docs/netfox/guides/network-time.md` ("Synchronized time");
`network-rollback.gd` (`tick`, `notify_resimulation_start`, `history_start`);
`examples/forest-brawl/scripts/effects/effect.gd` (`_apply_tick`, `_cease_tick`). Caveat:
Forest Brawl computes `_apply_tick` locally on receipt, so it differs per peer; sending an
explicit tick avoids that.

Recommendation: a `MatchSettings` node outside any synchronizer holding an immutable list of
`(start_tick, settings)` entries plus `round_start_tick`. Schedule each card for the round
start, several seconds ahead during the gap between rounds, so no resimulation is normally
needed.

## g. Pitfalls in this version

- move_and_slide: wrap as `velocity *= NetworkTime.physics_factor; move_and_slide();
  velocity /= ...`, and do a zero-velocity `move_and_slide()` before reading `is_on_floor()`
  (`rollback-caveats.md`, every example controller). Task 1.1 avoids this by using its own
  `move_and_collide` loop.
- physics_factor (`addons/netfox/network-time.gd`) is integer division of physics ticks per
  second by tick rate in a physics frame: keep physics TPS a multiple of 30. With
  `sync_to_physics` false (default) the tick loop runs in `_process`.
- RigidBody rollback needs a fork or a physics addon; the drivers ship disabled as `*.gd.off`.
  Fits GDD layer 3 (cosmetic physics only).
- Area and overlap queries are stale during rollback; Forest Brawl's Displacer uses a distance
  check.
- Godot versions: CI tests 4.2.2, 4.3.0, 4.4.0, 4.5.0, 4.6.0 and 4.7.0; 4.7.2 is not in the
  matrix. Some schema serializers need 4.4 or newer.
- Spawning and despawning: never `queue_free` rollback nodes, use `despawn()`; never remove a
  node from the tree and re-add it (rules out pooling by reparenting); a node spawned mid-loop
  is first simulated on the next loop from `spawn_tick`
  (`docs/netfox/tutorials/spawning-and-despawning-in-rollback.md`).
- Host as player: avatars are owned by peer 1 and their Input nodes by the player. Inference:
  on the host, remote players are simulated late, once their input arrives, and are either
  predicted (`enable_prediction`) or held still until then. Test this on the host phone.
- Stalls and backgrounding: a frame gap over `netfox/time/stall_threshold` (1.0 s) is treated
  as a pause; the tick jumps and the history floor resets. Pause and unpause all peers
  together.
- Changes since older 1.x: `full_state_interval`, `diff_ack_interval` and
  `enable_input_broadcast` moved to project settings (`enable_input_broadcast` defaults to
  false); `register_rollback_input_submission` now does nothing; new: schemas,
  PredictiveSynchronizer, liveness, packet size limit. Mutations are still experimental.

## h. Project settings netfox reads (defaults from `addons/netfox/netfox.gd`)

- time: `tickrate` 30; `max_ticks_per_frame` 8; `stall_threshold` 1.0; `sync_interval` 0.25;
  `sync_samples` 8; `sync_adjust_steps` 8; `sync_to_physics` false; `max_time_stretch` 1.25;
  `tickrate_mismatch_action` Warn.
- rollback: `enabled` true; `history_limit` 64; `input_redundancy` 3; `display_offset` 0;
  `input_delay` 0; `enable_input_broadcast` false; `enable_diff_states` true;
  `full_state_interval` 24.
- general: `max_sync_packet_size` 508. logging: all levels default to DEBUG.
- extras: `autoconnect/simulated_latency_ms` 0 and `simulated_packet_loss_chance` 0.

For this game: keep tickrate 30; set `tickrate_mismatch_action` to Disconnect;
`input_redundancy` 3 to 5 for hotspot packet loss; leave `display_offset` and `input_delay` at
0 (`is_fresh` misbehaves with `input_delay`); set log levels to Warning for device builds; use
the simulated latency and loss settings to rehearse 150 ms on desktop.

## Could not determine from source, and how to test

1. Whether CharacterBody2D raycasts and shape casts during rollback need a 2D equivalent of
   the 3D physics-transform workaround. Test headless: move a body in a rollback tick, raycast
   in the same tick, compare with the expected hit.
2. Whether the missing RPC in NetworkWeaponHitscan3D is a bug or deliberate (irrelevant if
   NetworkWeapon is not used).
3. How visible the host's correction of remote players is with `enable_prediction` on or off.
   Test with two desktop instances at 75 ms simulated latency each way, then two phones.
4. How far a PredictiveSynchronizer bomb diverges after a melee deflect at 150 ms.
5. Resimulation CPU cost for 8 players plus projectiles on a 3 to 4 GB phone (read the
   `netfox/Rollback loop duration (ms)` and `netfox/Rollback ticks simulated` monitors).
6. Godot 4.7.2 specifically: CI covers 4.7.0 only and open issues were not checked.
7. Whether DEBUG logging costs measurable time in Android release exports.
