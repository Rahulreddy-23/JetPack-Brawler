# Gemini Bug, Security & CEO Audit Report

Date: 24 Nov 2026
Branch: `geminiceo` (synced from `origin/main` `9a9a2d4` and `dev` `320df9b`)

---

## Part 1: Bug and Security Hunt

All findings below are grounded in the repository files inspected on `dev` (`320df9b`) and `origin/main` (`9a9a2d4`), plus the unmerged Phase 1 feature worktrees (`combat/`, `hazard/`, `effects/`) where noted. All findings in the active prototype have been fixed and regression-tested on branch `geminiceo` (`tests/test_security_audit.tscn`).

### Critical

#### 1. Host clock hijack and match-wide freeze via unauthenticated `_handle_set_timestamp`
- **Severity:** critical
- **Category:** Network trust / Denial of service
- **Location:** `addons/netfox/network-time-synchronizer.gd:298-303` (`_handle_set_timestamp`)
- **What happens and how to trigger it:** `_cmd_set_time` is registered on `NetworkCommandServer`, whose transport RPCs (`addons/netfox/servers/network-command-server.gd:168-181`) are `@rpc("any_peer")`. `_handle_set_timestamp(sender, data)` does not check `multiplayer.is_server()` or `sender == 1`, nor does it validate `bytes_to_var(data)` is a finite number. Any connected modified client can send `_cmd_set_time` to peer 1 (the host) with `var_to_bytes(NAN)` or `var_to_bytes(1.0e9)`. The host calls `_clock.set_time(timestamp)`, poisoning `NetworkTimeSynchronizer.get_time()`, corrupting `NetworkTime._loop()` clock stretching (`addons/netfox/network-time.gd:539`), and handing poisoned timestamps to every subsequent joining client. On clients, sending `_cmd_set_time` multiple times also spawns duplicate concurrent `_loop()` coroutines.
- **Suggested fix:** Reject `_handle_set_timestamp` unless `not multiplayer.is_server() and sender == 1 and _active and not _loop_running`, and require the decoded value to be a finite numeric type. (Fixed on `geminiceo`.)

#### 2. Host history buffer wipe and bot freeze via boundary future tick (`+history_limit`) and empty post-sanitize snapshots
- **Severity:** critical
- **Category:** Network trust / Denial of service
- **Location:** `addons/netfox/servers/network-history-server.gd:298-305` (`_can_merge_tick`), `addons/netfox.internals/history-buffer.gd:93-102`, `addons/netfox/servers/network-synchronization-server.gd:394-449`, `addons/netfox/servers/data/snapshot.gd:118-127`
- **What happens and how to trigger it:** The local netfox patch capped incoming ticks at `NetworkTime.tick + NetworkRollback.history_limit` (`+64`). When a modified client sends a single input or state packet stamped at `tick = NetworkTime.tick + 64` (right before the host records `NetworkTime.tick`, when `_HistoryBuffer._head == NetworkTime.tick`), `set_at(at, value)` hits `elif at >= head + _capacity:` (`64 >= 64`) and executes `_previous.fill(null); _buffer.fill(null)`, wiping all 64 ticks of history and causing subsequent host `set_at(NetworkTime.tick, ...)` calls to hit `at < head - _capacity` and silently drop the host's own inputs. Furthermore, `snapshot.sanitize(sender)` erased unauthorized subjects from `_data` without clearing `_auth_subjects`, and `_handle_input`/`_ingest_state`/`_handle_*_sync` merged empty post-sanitize snapshots into shared tick buffers anyway.
- **Suggested fix:** Tighten the future tick window to `NetworkRollback.input_delay + mini(NetworkRollback.history_limit / 4, 16)`, clear `_auth_subjects` in `sanitize()`, and drop empty snapshots after `sanitize()` before calling `NetworkHistoryServer._merge_*`. (Fixed on `geminiceo`.)

#### 3. Remote host crash via out-of-bounds property index in `_SparseSnapshotSerializer.read_from`
- **Severity:** critical
- **Category:** Denial of service / Crashes and logic bugs
- **Location:** `addons/netfox/serializers/sparse-snapshot-serializer.gd:84-88`, `addons/netfox/schemas/network-schemas.gd:612-630`
- **What happens and how to trigger it:** Any connected client can send a crafted `_cmd_diff_state` or `_cmd_diff_sync` command referencing any registered node (for example its own `BotInput` node, which has 0 properties in `_rb_state_properties`, or any `Bot` node with 15 properties) with `changed_bits` setting a bit index `>= node_props.size()`. Before `snapshot.sanitize(sender)` is reached, `node_props[idx]` throws an out-of-bounds array error on the host. In addition, `_VariableBitsetSerializer.decode` had no cap on continuation bytes (`0x80`), allowing unbounded array growth from a single packet.
- **Suggested fix:** Bounds-check `idx >= 0 and idx < node_props.size()` and `node_buffer.get_available_bytes() > 0` before reading properties, and cap `_VariableBitsetSerializer.decode` to available bytes and 256 bits. (Fixed on `geminiceo`.)

#### 4. Unauthenticated `_handle_pong` / `_handle_ping` crash on malformed payload
- **Severity:** critical
- **Category:** Denial of service / Network trust
- **Location:** `addons/netfox/network-time-synchronizer.gd:251-263, 294-296`
- **What happens and how to trigger it:** `_handle_pong` does not check `not multiplayer.is_server()` or `sender == 1`, and indexes `args[0]`, `args[1]`, `args[2]` directly on `bytes_to_var(data)`. Any client sending `_cmd_pong` to the host with empty bytes, an integer, or a short array causes an immediate GDScript runtime error on the host. `_handle_ping` and `_handle_request_timestamp` also lacked `multiplayer.is_server()` and payload type checks.
- **Suggested fix:** Enforce sender and server/client direction checks on all four time-sync handlers and validate decoded types, array length, and float finiteness before indexing or casting. (Fixed on `geminiceo`.)

### High

#### 5. Debug/Android-Debug host assertion crash via conflicting `_handle_ids`
- **Severity:** high
- **Category:** Denial of service / Network trust
- **Location:** `addons/netfox/servers/network-identity-server.gd:192-203`, `addons/netfox/servers/data/network-identifier.gd:22-25`
- **What happens and how to trigger it:** `_handle_ids` is reachable by any client via `_cmd_ids` (`@rpc("any_peer")`). Sending two `_cmd_ids` packets for the same node path (e.g. `/root/Main/Bots/Bot1`) with two different integer IDs hits `assert(not _ids.has(peer) or _ids[peer] == id, ...)` in `_NetworkIdentifier.set_id_for`, crashing debug builds (including Android Debug builds).
- **Suggested fix:** Ignore conflicting peer ID re-registrations in `set_id_for` instead of asserting. (Fixed on `geminiceo`.)

#### 6. Single-packet CPU amplification in `_RedundantSnapshotSerializer.read_from` and unbounded sync packet size
- **Severity:** high
- **Category:** Denial of service
- **Location:** `addons/netfox/serializers/redundant-snapshot-serializer.gd:40-46`, `addons/netfox/servers/network-synchronization-server.gd:394-443`
- **What happens and how to trigger it:** `_RedundantSnapshotSerializer.read_from` loops `while buffer.get_available_bytes() > 0` with no upper bound on snapshot count or minimum `snapshot_size`. A single client packet filled with `0x00` bytes (e.g., 16 KB) causes 16,384 iterations of `_dense_serializer.read_from` and snapshot merges inside a single RPC on the host.
- **Suggested fix:** Cap incoming sync packets in `NetworkSynchronizationServer` (`<= max(_max_packet_size * 4, 4096)` bytes), cap snapshots per redundant packet, and break when `snapshot_size <= 0` or `snapshot_size > buffer.get_available_bytes()`. (Fixed on `geminiceo`.)

#### 7. Coroutine leak, stale-bot erasure, and missed restart transition in `BotSpawner`, `Session`, and `NetworkEvents`
- **Severity:** high
- **Category:** Crashes and logic bugs / Denial of service
- **Location:** `scripts/net/bot_spawner.gd:32-55, 87-93`, `scripts/net/session.gd:29-58, 70-77`, `addons/netfox/network-events.gd:97-111`
- **What happens and how to trigger it:**
  1. `BotSpawner.on_peer_accepted(id)` awaited `NetworkTime.after_client_sync` in a loop per connecting peer. A client that connects and disconnects repeatedly without sending `_submit_sync_success` leaks a suspended coroutine and signal connection every time.
  2. `BotSpawner._on_bot_exited(peer_id)` erased `_bots[peer_id]` without checking whether the exiting node was still the current bot for `peer_id`; `clear()` left queued-free nodes in the tree until frame end, causing name collisions (`Bot1`) on rapid restart.
  3. `Session.leave()` switched to `OfflineMultiplayerPeer` without updating `NetworkEvents._is_server`, which only polled inside `_process()`. Leaving and re-hosting on the same frame skipped both `on_server_stop` and `on_server_start`, leaving the host with no bot and a stopped `NetworkTime`.
  4. `Session._on_peer_join` checked `multiplayer.get_peers().size() + 1 > _cfg.max_players` instead of tracking accepted peers, allowing a lingering rejected 5th peer awaiting ENet disconnect timeout to block a legitimate 4th player from joining.
  5. `Session.host()` and `Session.join()` overwrote `multiplayer.multiplayer_peer` without calling `leave()` first if already active.
- **Suggested fix:** Replace the `await` loop with an event-driven `_pending_peers` map, detach children before `queue_free()`, verify bot identity in `_on_bot_exited`, track `_accepted_peers` and call `leave()` on re-entry in `Session`, and add `NetworkEvents.sync_state()` called from `Session.leave()`. (Fixed on `geminiceo`.)

### Medium

#### 8. `TouchControls` intercepts menu/Leave touches, clobbers keyboard input on idle mouse motion, and sticks on Android focus loss
- **Severity:** medium
- **Category:** Crashes and logic bugs
- **Location:** `scripts/ui/touch_controls.gd:29-43, 69-99`, `scripts/game/main.gd:27-28, 95-101`
- **What happens and how to trigger it:**
  1. `TouchControls` was made visible on the start menu and used `_input(event)` (which fires before GUI controls), intercepting touches meant for Host/Join/IP field/Leave buttons.
  2. `_drag(index, pos)` called `_publish()` unconditionally even when `index` was neither `_move.finger` nor `_aim.finger`; with `--touch-ui` on desktop, moving the mouse without clicking released all keyboard movement actions every frame.
  3. Missing `NOTIFICATION_APPLICATION_FOCUS_OUT` / `NOTIFICATION_APPLICATION_PAUSED` handling left sticks and dash stuck pressed if Android interrupted the app mid-touch (incoming call, notification shade, app switch).
- **Suggested fix:** Keep `TouchControls` hidden on the start menu, switch to `_unhandled_input`, return early in `_drag` for untracked finger indices, and clear active touches on focus-loss/pause notifications. (Fixed on `geminiceo`.)

#### 9. Unvalidated join address allows blocking main-thread DNS lookups and UI overflow hiding the Leave button
- **Severity:** medium
- **Category:** Untrusted input
- **Location:** `scripts/game/main.gd:61-86`, `scripts/ui/menu.gd:52-55, 73-79`
- **What happens and how to trigger it:** `_address_field` had no `max_length` and `Main._on_join(address)` passed arbitrary text directly to `ENetMultiplayerPeer.create_client(address, port)` and displayed it in a non-clipping `Label` beside the `Leave` button. Typing a non-IP string on an offline hotspot triggers a blocking DNS attempt; long pasted strings or multiple host IPv4 interfaces push the `Leave` button off-screen. Also `--port=99999` bypassed the `> 0` check in `_port()`.
- **Suggested fix:** Validate `address.is_valid_ip_address()` before calling `join()`, cap `_address_field.max_length = 45`, clip `_strip_label` with ellipsis so `Leave` remains on-screen, and bound `--port` to `1..65535`. (Fixed on `geminiceo`.)

#### 10. Unbounded memory growth in `NetworkTimeSynchronizer._awaiting_samples` on packet loss
- **Severity:** medium
- **Category:** Performance bugs
- **Location:** `addons/netfox/network-time-synchronizer.gd:113, 181-189, 266-274`
- **What happens and how to trigger it:** Every `0.25 s`, clients insert a `NetworkClockSample` into `_awaiting_samples` and send an unreliable `_cmd_ping`. Whenever a ping or pong UDP packet is dropped, the entry is never erased unless a clock panic clears the dictionary, leaking entries continuously over a 20-minute session on lossy Wi-Fi/hotspot networks.
- **Suggested fix:** Prune `_awaiting_samples` entries older than `max(NetworkTime.stall_threshold * 4.0, 10.0)` seconds inside `_loop()`. (Fixed on `geminiceo`.)

#### 11. Unmerged worktree findings (`combat/` and `effects/`)
- **Severity:** medium
- **Category:** Crashes and logic bugs / Performance bugs
- **Location:** `.claude/worktrees/agent-affed99a603bbe1b9/effects/screen_shake.gd:30-51`, `.claude/worktrees/agent-a2054b3bbdd4990f0/combat/combat_ledger.gd:90-95, 108-113`
- **What happens and how to trigger it:**
  1. `ScreenShake.shake(strength)` does not check `is_finite(strength)` or `is_instance_valid(_camera)` in `_process()`; passing `NAN`/`INF` permanently corrupts `_camera.offset` and freeing the parent camera causes a freed-instance access.
  2. `CombatLedger._finish_knockout` checks `tick - int(_last_attack_tick[victim]) > credit_window_ticks`, which allows negative deltas (`tick < last_attack_tick`) to credit a future hit, and lacks a `remove_fighter` cleanup path (though `docs/ARCHITECTURE.md` D2 notes `CombatLedger` is slated to be retired in favor of rollback state).
- **Suggested fix:** Guard `is_finite(strength)` and `is_instance_valid(_camera)` in `ScreenShake`, and ensure the replacement `BotVitals` rollback state checks `delta >= 0 and delta <= credit_window_ticks` when crediting knockouts.

### Low

#### 12. Unconditional 60 fps `queue_redraw()` on `Hud` and `TouchControls`
- **Severity:** low
- **Category:** Performance bugs
- **Location:** `scripts/ui/hud.gd:14-15`, `scripts/ui/touch_controls.gd:45-46`
- **What happens and how to trigger it:** Both `Hud` and `TouchControls` called `queue_redraw()` every rendered frame (60 fps) even when fuel, dash state, and finger positions did not change, causing avoidable canvas rebuilds and `draw_string` calls on budget Android GPUs.
- **Suggested fix:** Redraw `TouchControls` only on touch/drag/resize/reset events, and redraw `Hud` only when bot presence, fuel fraction, or dash-ready state changes. (Fixed on `geminiceo`.)

### Category Status Summary
- **Crashes and logic bugs:** Findings #3, #7, #8, #11
- **Network trust:** Findings #1, #2, #4, #5
- **Desync:** None found in current movement prototype (`_rollback_tick` is deterministic on fixed network tick; `BotInput._gather_device` on desktop `--touch-ui` falls back to mouse aim when right stick is idle, noted as a dev-flag caveat).
- **Denial of service:** Findings #1, #2, #3, #4, #5, #6, #7
- **Untrusted input:** Finding #9
- **Purchases and unlocks:** None found (not yet implemented in Phase 1).
- **Android and privacy:** None found (`export_presets.cfg` requests only `permissions/internet=true`, disables `user_data_backup/allow=false`, and logs do not emit PII or local IPs; note `scripts/dev/*` is currently not excluded from Android Debug APK exports, which is acceptable for debug builds and should be excluded in the future release preset).
- **Repository hygiene:** None found (no secrets, API keys, passwords, or keystores found in working tree or git history; bundled `netfox` and `netfox.internals` v1.49.12 are MIT licensed).
- **Performance bugs:** Findings #10, #11, #12

### What Could Not Be Checked From Provided Material
1. **Real Android hardware & hotspot networking:** Two-phone hotspot discovery, actual touch ergonomics, on-screen soft keyboard behavior on `LineEdit.edit()`, thermal/battery profile over a 20-minute session on 3-4 GB RAM devices, and Android APK size (< 80 MB).
2. **Multi-process loopback tests (`tests/net_smoke.sh`, `tests/net_rejoin.sh`, `tests/net_full.sh`):** Blocked inside the sandbox environment by localhost UDP socket restrictions (all single-process Godot headless tests — `test_movement.tscn` 56/56, `test_input_flood.tscn` 3/3, `test_menu_touch.gd` 1/1, and `test_security_audit.tscn` 9/9 — were executed and passed).
3. **Unimplemented future systems:** Combat weapons/gadgets/pickups, Chaos Cards, rounds/scoring/ties/timer expiry, online relay (`noray`), six-character room codes, WhatsApp deep links, player names, save files, and Google Play purchases/unlocks (all out of scope in Phase 1).

---

## Part 2: Studio CEO Review (Fun, Product Direction, and Execution)

### Overall Assessment
The engineering discipline on this project is unusually strong for a Phase 1 prototype: typed GDScript enforced as errors, single-source `TuningConfig`, clean netfox rollback separation, and a smart combat architecture (`docs/ARCHITECTURE.md`) that avoids the classic `MultiplayerSpawner` + rollback traps.

### Is It Fun Yet? (Honest CEO Verdict)
**Not yet — and that is expected at Task 1.1, but we are at the single most important risk window in the whole project.**
Right now the prototype only has flying/dashing/wall-jumping around empty grey rectangles. The GDD's actual Phase 1 fun test is:
> *"Flying around one map and knocking a dummy bot into a hazard should be enjoyable for 10 minutes."*

Until Tasks 1.2–1.5 (knockback, 4 weapons, melee deflect, Cooker Bomb + Spring Plate, molten metal hazard, hit-freeze/shake/parts burst) are playable together on two real Android phones, we have **not** yet proven the game is fun.

### Strategic Watch-Items & Course Corrections
1. **Do not build Dabba (Task 1.6) until the movement + knockback + hazard sandbox passes the 10-minute fun test on a real phone.** Right now `docs/ARCHITECTURE.md` warns about a real gameplay feel risk: *"Ground braking may cancel pushes quickly and make them feel weak."* With `ground_brake = 80.0 bh/s^2` (`config/tuning.tres:11`), a grounded bot hit by a horizontal push will decelerate to zero almost instantaneously unless knockback briefly lifts the bot slightly off the ground or temporarily suppresses ground braking (`hitstun`/`knockback_slide` window). Fix that feel immediately in Task B/C playtesting — knockback *is* the entire game.
2. **Verify touch controls on real phones before adding 4 more buttons in Task F.** Right now `TouchControls` has 2 sticks + Dash. Task F adds Fire (aim outer ring), Melee tap + dedicated Melee button, Gadget button, and Weapon Swap button. On a 6-inch phone screen, thumb ergonomics can kill a twin-stick shooter faster than netcode. Test the 2-stick + Dash feel on hardware *this week* while the layout is still simple.
3. **Security hygiene paid off early.** Because `docs/ARCHITECTURE.md` builds all combat, gadgets, and hazards on top of `netfox` rollback history and `NetworkTimeSynchronizer`, fixing the 4 critical netfox vulnerabilities now (host clock hijack, `+64` history wipe bypass, out-of-bounds sparse diff crash, malformed pong crash) protects the entire Phase 2 online-room roadmap before those systems multiply the attack surface.
4. **Keep `dev` and `main` reconciled.** Right now the Godot prototype lives on `dev` while `origin/main` has only docs. Merging Task 1.1 cleanly to `main` (with the verified `dev` and `geminiceo` fixes) will eliminate drift across parallel agents and ensure every future audit tests the exact canonical build.

---

## Follow-up Check (24 Nov 2026 18:38, after `origin/main` `e75514d`)

Synced `geminiceo` with `origin/main` (`e75514d`) and aligned `_can_merge_tick`'s future-tick ceiling with the lead's tighter `NetworkRollback.input_delay + NetworkTime.max_ticks_per_frame` bound. Audited newly added worktree code (`scripts/game/combat_geometry.gd`, `scripts/game/cast_result.gd` at `d531f23`) and the lead's local task 1.1 fix round (read-only).

### New Findings on Unmerged / In-Progress Code

#### 13. Delayed `disconnect_peer` (`reject_notice_seconds`) widens slot blocking and RPC window, and lacks post-await session/tree guard
- **Severity:** high
- **Category:** Crashes and logic bugs / Denial of service
- **Location:** `scripts/net/session.gd:73-81` (lead's local task 1.1 fix round)
- **What happens and how to trigger it:** When a 5th peer joins a full match, `_on_peer_join` sends `_match_full.rpc_id(id)` and awaits `get_tree().create_timer(_cfg.reject_notice_seconds).timeout` (`0.5 s`) before calling `disconnect_peer(id)`.
  1. Because capacity still checks `multiplayer.get_peers().size() + 1 > _cfg.max_players` rather than accepted peers, a rejected 5th peer is guaranteed to hold a slot in `get_peers()` for at least `0.5 s`, rejecting any legitimate replacement player if someone leaves during that window.
  2. During that `0.5 s` window, the rejected peer remains a connected ENet peer and can send `@rpc("any_peer")` commands (`_cmd_input`, `_cmd_diff_state`, `_cmd_ids`, `_cmd_ping`, etc.).
  3. If the host leaves and restarts during the `0.5 s` timer, `multiplayer.get_peers().has(id)` runs after the await without checking `is_inside_tree()` or that the same session is still active.
- **Suggested fix:** Track `_accepted_peers: Dictionary[int, bool]` for the capacity check, guard `is_inside_tree()` and a session generation counter after the `await`, and combine with the netfox packet/command hardening patches (findings #1-#6) so a rejected peer cannot harm the host during the notice grace period.

#### 14. Residual gaps in lead's local `network-time-synchronizer.gd` patch
- **Severity:** medium
- **Category:** Network trust / Performance bugs
- **Location:** `addons/netfox/network-time-synchronizer.gd:253-313` (lead's local task 1.1 fix round)
- **What happens and how to trigger it:** The lead's local patch adds `sender != SERVER_PEER_ID` checks to `_handle_pong` and `_handle_set_timestamp`, which blocks the host clock hijack from non-server peers. Four gaps remain compared to `geminiceo`:
  1. `_handle_ping` does not check `multiplayer.is_server()` or validate `bytes_to_var(data)` before casting `as int` (empty `PackedByteArray()` triggers an engine deserialization error and null-to-int cast error).
  2. `_handle_request_timestamp` does not check `multiplayer.is_server()`.
  3. `_handle_set_timestamp` does not check `is_finite(timestamp)` or prevent duplicate `_loop()` coroutines on clients.
  4. `_awaiting_samples` still leaks entries whenever unreliable ping/pong UDP packets are dropped.
- **Suggested fix:** Port the full validation, `_loop_running` guard, and stale-sample pruning from `geminiceo`'s `addons/netfox/network-time-synchronizer.gd`.

### Clean Audits (No Findings)
- **`scripts/game/combat_geometry.gd` and `scripts/game/cast_result.gd` (`worktree-agent-a4bc7d39dec0511d8`, `d531f23`):** None found. Checked `NaN`/`INF` inputs, `INF + (-INF)` rect sum, zero-length segments, edge/corner entry normals, subnormal division in 64-bit double, and circle-rect overflow; all handled cleanly.

### CEO Note (Iteration 1)
- All three product recommendations from the first audit (push window so ground braking does not cancel knockback, Dabba deferred until after the 10-minute phone sandbox test, and early phone test of touch controls after Task 1.1) are now recorded in `docs/DECISIONS.md`.
- Keep the focus strictly on merging Task 1.1 to `main` and getting the Android Debug APK onto two phones for Rahul's touch-stick and hotspot check before Task F adds four more buttons.

---

## Iteration 2/3 Audit (24 Nov 2026 23:20, after `origin/main` `8ec8146`)

Merged `origin/main` (`8ec8146`, covering Tasks A, B, C, F, `12394b2`, `cf94537`, and D-4 through D-9) into `geminiceo` and audited all new combat, weapon, pickup, match-settings, HUD, touch-input, and session scripts.

### New Confirmed Findings (All Fixed & Regression-Tested on `geminiceo`)

#### 15. Rocket muzzle spawns inside solid walls when firing flush against a wall
- **Severity:** high
- **Category:** Crashes and logic bugs / Gameplay
- **Location:** `scripts/game/weapon_rules.gd:45-50` (`_collect_shot`)
- **What happens and how to trigger it:** When a bot stands flush against a solid wall or column (such as Smelter's 1-bh columns at `x = 11` and `x = 28`, left face at `704 px`) and shoots the Festival Rocket Tube into the wall, `muzzle = origin + dir * (leave + stats.projectile_radius * px)` places the rocket 16 px (`0.25 * 64`) inside the solid wall (`x = 720 px`), bypassing the wall face before Task D's flight/contact code runs.
- **Suggested fix:** Cast `CombatGeometry.cast(origin, muzzle, solids)` and clamp `muzzle = origin.lerp(muzzle, wall.t)` when `wall.index >= 0 and wall.t < 1.0`. *(Fixed on `geminiceo`; tested in `tests/test_security_audit.gd`.)*

#### 16. Server-side full-room rejection timer lacks tree/peer guard (server counterpart of D-7)
- **Severity:** high
- **Category:** Crashes and logic bugs
- **Location:** `scripts/net/session.gd:81-90` (`_on_peer_join`)
- **What happens and how to trigger it:** Finding D-7 guarded the client-side deferred close (`_close_rejected_peer`) against leaving/re-hosting before the deferred work runs, but `_on_peer_join` on the server still awaits `get_tree().create_timer(_cfg.reject_notice_seconds).timeout` and then unconditionally accesses `multiplayer.get_peers()` and `multiplayer.multiplayer_peer`. If the host leaves and `Session` exits the tree or starts a new server peer within `0.5 s`, the resumed coroutine errors on null `multiplayer` or operates on the wrong peer.
- **Suggested fix:** Capture `var server_peer: MultiplayerPeer = multiplayer.multiplayer_peer` before the `await` and check `is_inside_tree() and multiplayer.multiplayer_peer == server_peer and multiplayer.get_peers().has(id)` after it. *(Fixed on `geminiceo`; tested in `tests/test_security_audit.gd`.)*

#### 17. Pickup cycle reset is missed if a host stall skips the exact boundary tick
- **Severity:** medium
- **Category:** Crashes and logic bugs
- **Location:** `scripts/game/pickups.gd:41-45` (`resolve`)
- **What happens and how to trigger it:** Unlike `BotVitals` (which tracks `cycle_index` specifically so a skipped tick cannot lose a cycle reset), `Pickups.resolve` checks `MatchSettings.hazard_ticks(tick) == 0`. If the host stalls over tick `1350` (resuming at `1352`), any pickup spot taken near the end of cycle 0 stays on its 15-second cooldown into cycle 1.
- **Suggested fix:** Compute `cycle_start = tick - into_cycle` and reset any spot whose `ready_tick > cycle_start` and `ready_tick - respawn_ticks < cycle_start` (was taken in an earlier cycle) to `cycle_start`. Zero new state properties and rollback-idempotent. *(Fixed on `geminiceo`; tested in `tests/test_security_audit.gd`.)*

#### 18. HUD does not redraw on viewport resize and lacks `_max_health > 0.0` guard
- **Severity:** medium
- **Category:** Crashes and logic bugs
- **Location:** `scripts/ui/hud.gd:36-39, 85`
- **What happens and how to trigger it:** `Hud._ready()` does not connect `resized.connect(queue_redraw)`. When a phone rotates or window resizes while bot state is unchanged, the right-aligned weapon/gadget lines (`size.x - 2.0 * _cfg.hud_margin_px`) stay drawn at the old width. Also `_health / _max_health` divides by zero if `_max_health <= 0.0`.
- **Suggested fix:** Connect `resized.connect(queue_redraw)` in `_ready()` and guard `_max_health > 0.0` before dividing. *(Fixed on `geminiceo`; tested in `tests/test_security_audit.gd`.)*

#### 19. Quick flick curving past the fire ring fires at the initial crossing angle instead of release angle
- **Severity:** medium
- **Category:** Crashes and logic bugs
- **Location:** `scripts/ui/touch_controls.gd:193-199` (`_update_aim`)
- **What happens and how to trigger it:** `_update_aim` only wrote `InputActions.pending_touch_fire_aim` when `not was_firing and _is_fire_held()`. If a player flicks past the fire ring in one direction, curves their thumb to a new aim direction while still past the ring, and lifts before the next network tick (< 33 ms), the shot fires along the stale initial crossing angle.
- **Suggested fix:** Update `InputActions.pending_touch_fire_aim = _aim.value(_cfg.stick_radius_px)` whenever `_is_fire_held()` is true. *(Fixed on `geminiceo`; tested in `tests/test_security_audit.gd`.)*

#### 20. Accepted netfox hardening (`1.1b-N`) still unmerged on `origin/main` (`8ec8146`)
- **Severity:** critical (2.26 s / 837 ms single-packet host freeze DoS)
- **Category:** Denial of service / Network trust
- **Location:** `addons/netfox/schemas/network-schemas.gd`, `addons/netfox/serializers/redundant-snapshot-serializer.gd`, `addons/netfox/serializers/sparse-snapshot-serializer.gd`, `addons/netfox/servers/network-synchronization-server.gd`, `addons/netfox/servers/data/snapshot.gd`, `addons/netfox/servers/data/network-identifier.gd`, `addons/netfox/network-time-synchronizer.gd`
- **Status:** Accepted in `docs/reviews/phase-1-findings.md` (G-2b, G-2c, G-3a, G-3b, G-4, G-5, G-6) but not yet merged to `main`; re-applied cleanly on `geminiceo` with strict assertions in `tests/test_security_audit.tscn`.

### Areas With No New Findings
- **Combat rules (`combat_rules.gd`, `bot_vitals.gd`, `bot_arsenal.gd`):** Clean deterministic hit sorting, `0 <= age <= window` knockout credit, trade handling, and finite guards.
- **Desync:** None found in Tasks A/B/C/F.
- **Purchases/unlocks, Android/privacy, Repository hygiene:** None found.

### CEO Review (Iteration 2/3)
1. **Huge velocity and discipline:** Tasks A, B, C, and F are all merged on `main` with 500+ passing automated checks, `server_relay = false` enforced, and D-4..D-9 incorporated cleanly.
2. **Watch bandwidth immediately (`232 KB/s` per player with diff states off!):** `docs/reviews/phase-1-findings.md` D-5 notes that disabling `enable_diff_states` pushed the idle `WorldObjects` pool to ~232 KB/s per player (~700 KB/s host upload for 4 players, ~1.6 MB/s for 8 players!). That is a **ship-blocker** for Indian 4G/hotspot play. Prioritize fixing the netfox diff-merge bug (`worktree-agent-abdc8cb18a9ad9d79`) and merging `1.1b-N` right after Tasks D and E so bandwidth drops back near the 20 KB/s target before the Phase 1 phone playtest.
3. **Next milestone:** Once Task D (Cooker Bomb, Spring Plate, rocket flight) and Task E (hit freeze, flash, parts burst, shake, rising metal visual) land, put the APK on two Android phones immediately and run the 10-minute knockback fun test before touching Dabba (Task 1.6).
