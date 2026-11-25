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


---

## Iteration 4 Audit Update (24 Nov 2026 23:45 — against `origin/main` `f479130`)

Merged `origin/main` (`8ec8146..f479130`: `1.1b-N` netfox hardening patches 1..13, ENet packet throttle hold `242e7b4`, `G-13`/`G-14` disposition `8ab8550`, and Task D world objects & gadgets `f479130`). Reverted our previous `scripts/net/session.gd` G-13.3 timer guard to match `origin/main` per the lead's ruling in `8ab8550`, while keeping our unreviewed Iteration 2/3 fixes (`weapon_rules.gd`, `pickups.gd`, `hud.gd`, `touch_controls.gd`) intact.

### New Confirmed Findings (Most Severe First)

#### 21. Rocket hitting a wall, floor, or max-range tick skips bot contact and explodes behind/past the bot (plus deflected rocket swept path)
- **Severity:** high
- **Category:** Crashes and logic bugs
- **Location:** `scripts/game/world_object.gd:126-139` (`_step_rocket`), `scripts/game/gadget_rules.gd:50-68` (`_rocket_contacts`), `scripts/game/world_objects.gd:194-196` (`launch`)
- **What happens and how to trigger it:** `WorldObject._rollback_tick` moves rockets before `GadgetRules._rocket_contacts` runs. When a rocket hits a solid surface (`hit.index >= 0`) or reaches its max-range tick (`tick >= fuse_tick`), `_step_rocket` immediately sets `explode_tick = tick` at the wall or range-end point. `_rocket_contacts` then skips any slot with `slot.explode_tick >= 0`. Trigger: (a) fire a rocket downward at an angle at a bot standing on the floor (or next to a wall) so the rocket enters the bot's grown rectangle before hitting the floor/wall on the same tick — the rocket passes through the bot and detonates on the floor/wall behind/below it, flipping vertical knockback; (b) hit a bot on the rocket's final range tick (`fuse_tick == tick`) — it detonates past the bot instead of at contact; (c) deflect a rocket via bullet/melee in `WeaponRules` on tick `T` — `_rocket_contacts` reconstructs `start = end - slot.velocity * step` from the post-deflection velocity rather than the path actually traveled (also spotted in local `dev` `782da7b`).
- **Suggested fix:** Store host-only `rocket_step_start` on `WorldObject` (set in `WorldObjects.launch` and at the top of `_step_rocket`), and in `_rocket_contacts` sweep `[rocket_step_start, global_position]` for rockets where `explode_tick < 0 or explode_tick == tick` so an earlier bot contact moves the blast point to the bot. *(Fixed on `geminiceo`; tested in `tests/test_security_audit.gd`.)*

#### 22. Phase 1 cycle reset in `GadgetRules.collect` runs after blasts/plates/throws and misses stalled boundary ticks
- **Severity:** high
- **Category:** Crashes and logic bugs
- **Location:** `scripts/game/gadget_rules.gd:20-27` (`collect`)
- **What happens and how to trigger it:** (a) On cycle boundary tick `start + cycle`, `BotVitals._rollback_tick` has already respawned every bot at `spawn_position` with 100 HP. Because `GadgetRules.collect` runs `_rocket_contacts`, `_blasts`, and `_plates` *before* `objects.reset()`, a cycle-0 Cooker Bomb whose `fuse_tick == start + cycle` explodes on freshly respawned bots (dealing up to 50 damage/knockback on tick 0 of cycle 1), and a cycle-0 armed Spring Plate placed on a spawn point launches the freshly respawned bot before being cleared. (b) If a player presses gadget on tick `start + cycle`, `BotGadgets._rollback_tick` consumes their fresh starting Cooker Bomb and `_use_gadgets` launches it, then line 27 `objects.reset()` immediately deletes it. (c) If a host stall jumps `NetworkTime.tick` past `start + cycle`, `MatchSettings.hazard_ticks(tick) == 0` never triggers, leaving fuseless Spring Plates on the arena permanently into the next cycle.
- **Suggested fix:** Run the cycle reset at the top of `GadgetRules.collect` (before `_use_gadgets`, `_rocket_contacts`, `_blasts`, `_plates`) and deactivate any active slot with `slot.spawn_tick < cycle_start` whenever `cycle_start > MatchSettings.round_start_tick`. *(Fixed on `geminiceo`; tested in `tests/test_security_audit.gd` and `tests/test_world_objects.gd`.)*

#### 23. `Pickups` never resets `PickupSpot.ready_tick` between sessions
- **Severity:** medium
- **Category:** Crashes and logic bugs
- **Location:** `scripts/game/pickups.gd:15-31` (`_ready`)
- **What happens and how to trigger it:** Unlike `WorldObjects` (which connects `reset_session()` to all four `NetworkEvents` session signals because `Main` stays loaded across sessions while `NetworkTime.tick` resets to `0`), `Pickups` never resets `spot.ready_tick`. Trigger: play Session 1 past tick 5000, take a weapon/gadget pickup (`spot.ready_tick = 5450`), click Leave, and host Session 2 — `spot.ready_tick` remains `5450`, locking that pickup out for the entire first 45-second hazard cycle (`ticks 0..1349`).
- **Suggested fix:** Add `Pickups.reset_session()` to set `spot.ready_tick = 0` on every spot and connect it to `NetworkEvents.on_server_start`, `on_server_stop`, `on_client_start`, and `on_client_stop`. *(Fixed on `geminiceo`; tested in `tests/test_security_audit.gd`.)*

#### 24. Oversized-packet warning in netfox `_is_acceptable` is not rate-limited and serializer warning maps leak per-peer entries
- **Severity:** medium
- **Category:** Denial of service / Performance bugs
- **Location:** `addons/netfox/servers/network-synchronization-server.gd:154-166, 449-459` (`erase_peer`, `reset`, `_is_acceptable`), `addons/netfox/serializers/base-snapshot-serializer.gd:10` (`_last_warning_msec`)
- **What happens and how to trigger it:** As noted under "Not done" in `addons/NETFOX_PATCHES.md:361-362`, every oversized packet sent by a peer logs a full `_logger.warning(...)` (`push_warning` with backtrace) without rate limiting. A hostile client sending 100 packets/sec over `limit` floods the log and burns host CPU on stack-trace formatting. In addition, `_dense_serializer._last_warning_msec` and `_sparse_serializer._last_warning_msec` are never pruned in `erase_peer()` or `reset()`.
- **Suggested fix:** Rate-limit `_is_acceptable`'s size warning to once per 1000 ms per peer (preserving the first warning so `net_smoke` still fails on honest oversized packets) and clear per-peer warning timestamps in `erase_peer()` and `reset()`. *(Fixed on `geminiceo`; tested in `tests/test_security_audit.gd`.)*

### Areas With No New Findings (Iteration 4)
- **Network trust:** None found in Task D (`WorldObjects`/`WorldObject` are host-owned, `BotGadgets` sanitizes `input.gadget` with `Bot.clean_bool` and `input.aim` with `Bot.clean_vector`, `Session._on_peer_connected` only configures ENet throttle on local peer).
- **Desync:** None found in Task D or `242e7b4`.
- **Untrusted input:** None found in Task D or `launch_args.gd` (`--sim-jitter-ms` is ignored in release builds and clamped `>= 0`).
- **Purchases and unlocks:** None present yet (none found).
- **Android and privacy:** None found.
- **Repository hygiene:** None found (no new secrets, keystores, or third-party addons).

### Could Not Check (Iteration 4)
- Multi-process loopback UDP tests (`net_smoke.sh`, `net_combat.sh`, `net_combat_objects.sh`, `net_world_objects.sh`, `net_world_objects_join.sh`, `net_hitch.sh`, `net_diffs.sh`, `net_reject.sh`, `net_rejoin.sh`, `net_full.sh`) cannot send localhost UDP sockets inside the sandbox; all single-process headless tests (23 suites, including `test_world_objects.tscn` 251/251, `test_netfox_handlers.tscn` host+client, `test_netfox_diffs.tscn`, `test_slow_frames.tscn`, and `test_security_audit.tscn` 22/22) passed; `test_full_state_coverage.tscn` also performs a loopback UDP handshake and could not complete inside the sandbox.
- Real Android device touch feel, Wi-Fi hotspot jitter with ENet `throttle_deceleration = 0`, and unfinished Task E worktree (`effects_director.gd` is still a stub on `main`).

### CEO Review (Iteration 4)
1. **Huge technical milestone landed:** Netfox hardening (`c69179c`, patches 1..13), the ENet throttle fix (`242e7b4`), and Task D (`f479130`: Cooker Bomb, Spring Plate, rockets, deflection, idle-slot send throttling) are all on `main` with 48/48 passing on the lead's machine. Throttling idle world-object slots (`object_idle_send_interval = 1.0 s`) directly addresses the bandwidth spike from Iteration 2/3!
2. **Finish Task E and get onto two phones immediately:** Task E (presentation/effects) is the only remaining piece before Device Checkpoints 1 & 2. Do NOT start Task 1.6 (Dabba) until Rahul plays the 10-minute knockback sandbox on two real Android phones over a hotspot — especially to validate ENet `throttle_deceleration = 0` on real Wi-Fi/hotspot packet loss and test the aim-ring flick + melee/gadget thumb ergonomics on actual screens.
3. **Bandwidth & diff-states decision:** Keeping `enable_diff_states = false` for Phase 1 is the right pragmatic call (avoiding lost-diff stale state without a custom packet reference tick), provided idle-slot throttling keeps 4-player hotspot bandwidth comfortably inside budget during Device Checkpoint 2. Measure host upload KB/s with 4 bots firing/throwing during the phone test.


---

## Iteration 5 Audit Update (25 Nov 2026 09:50 — against `origin/main` `0c8e6a4`)

Merged `origin/main` (`f479130..0c8e6a4`: `D-11` deflected rocket swept path `39339bc`, netfox `has_authoritative_state(subject: Variant)` freed-object guard & mutation tests `d13f90d`, open jitter finding `D-10` `4c28880`, and `G-15..G-24` decisions `2787aaf`). Aligned `geminiceo` with `2787aaf`:
- Reverted `scripts/ui/hud.gd` to `origin/main` (`G-18` rejected).
- Tightened `scripts/ui/touch_controls.gd` (`G-19`) so `_update_aim` only updates `pending_touch_fire_aim` on initial crossing (`not was_firing`) or while an unsampled crossing is still pending (`pending_touch_fire_aim != Vector2.ZERO`), eliminating the extra shot when a thumb is pulled back inside the fire ring after a sampled tick.
- Trimmed `tests/test_security_audit.gd` so every check strictly tests an active `geminiceo` fix (`G-15, G-17, G-19, G-21a/b, G-22, G-23, G-24`) and fails on unpatched `main`.

### Audit of New Commits (`39339bc..0c8e6a4`) & Root-Cause Proof for Open Finding `D-10`

#### 25. Root-cause mechanism & combat impact of open finding `D-10` (two-tick stale authoritative state under UDP jitter)
- **Severity:** medium (visual snap on own bot under jitter; also affects re-simulated combat hits under jitter)
- **Category:** Desync
- **Location:** `addons/netfox/servers/network-history-server.gd:181-190` (`_record_rollback_state`) and `addons/netfox/servers/network-history-server.gd:221-229, 321-345` (`_merge_rollback_state` / `_merge_history`)
- **What happens and how to trigger it:** Under `SIM_JITTER_MS=150` (0% packet loss, independent 0..150 ms per-packet delay, so packets reorder), two netfox behaviours combine to produce the exact 2-tick, 1-step-behind settled trace mismatch recorded in `D-10`:
  1. **Out-of-order input hole stamped `is_auth = true` on the host:** With `input_redundancy = 3` and `enable_prediction = false`, suppose client packets `P(u), P(u+1), P(u+2)` (the three packets carrying `input[u]`, e.g. `u = 194`) draw high jitter delays while `P(u+3)` (carrying `[197, 196, 195]`) draws a small delay and arrives first. On Host Pass 1, tick `194` is not simulated (`state[195]` holds `pos(194)` with `is_auth = false`), **but** `input[195]` and `input[196]` are present, so `RollbackSimulationServer.simulate` runs ticks `195` and `196` starting from `pos(194)` (one step behind!). `_record_rollback_state(196)` and `(197)` check only `RollbackSimulationServer._is_predicting(input_snapshot, subject)` (which checks `input` at `tick - 1` alone, ignoring that `state[tick - 1]` was not authoritative) and stamp `@196_wrong` and `@197_wrong` as `is_auth = true`, sending both to the client.
  2. **Out-of-order state delivery overwrites Pass 2's repair on the client:** One frame later, `P(u+2)` arrives with `input[194]`. Host Pass 2 re-simulates `194..197` and sends `@195_right, @196_right, @197_right, @198_right`. If Pass 2's packets arrive *after* Pass 1's, `_merge_rollback_state` repairs the client's history cleanly. However, when `NetSim` delays Pass 1's `@196_wrong`/`@197_wrong` *past* Pass 2's `@196_right`/`@197_right`, `_merge_history` has no per-peer send sequence number and overwrites the newer authoritative state for ticks `196` and `197` with the older Pass-1 state, while `@198_right` (never sent in Pass 1) leaves tick `198` onward exact. Note that Step 2 also applies to multi-player combat without any input reordering: if Host Pass 1 sends `Victim @(T+1)` before Shooter's tick-`T` shot arrives and Host Pass 2 sends `Victim @(T+1)` with damage/push, UDP reordering of those two state packets overwrites the hit at `T+1` until `T+2` arrives.
- **Suggested fix:** First, in `_record_rollback_state(tick)`, do not mark `subject` authoritative when `not _rb_state_history.is_auth(tick - 1, subject)` and an earlier authoritative input exists within a bounded reorder window (e.g., `2 * input_redundancy` ticks, so genuine 3-packet loss bursts under `SIM_LOSS` still resume sending promptly instead of stalling for `history_limit` ticks). Second, if full elimination of reordered re-sent states (including combat hits) is desired, attach a monotonic per-peer packet sequence `u32` so `_merge_history` ignores an authoritative state for `(subject, tick)` from an older packet than one already merged for `(subject, tick)`. *(Documented for the active `D-10` investigation rather than altering netfox wire format mid-round.)*

### Areas With No New Findings (Iteration 5)
- **`d13f90d` (`has_authoritative_state(subject: Variant)`):** Cleanly handles freed objects, `null`, non-`Object` `Variant`s, refused ticks, unauthorized senders, and `deregister()`.
- **`39339bc` (`D-11` deflected rocket swept path):** Clean and deterministic.
- **Crashes/logic bugs, Network trust, DoS, Untrusted input, Purchases/unlocks, Android/privacy, Repository hygiene, Performance:** None found in `39339bc..0c8e6a4`.

### Could Not Check (Iteration 5)
- Multi-process loopback UDP tests (`net_*.sh`) and `test_full_state_coverage.tscn` (loopback UDP blocked in sandbox); real Android hotspot play.

### CEO Review (Iteration 5)
1. **Tight review-to-architecture loop:** Seven `geminiceo` findings (`G-15, G-17, G-19, G-21a/b, G-22, G-23, G-24`) and `D-11` are now locked into `docs/ARCHITECTURE.md` and entering `main`'s fix rounds.
2. **Pragmatic call on `D-10` for Phase 1:** `D-10` is a 1-tick (~10 px, 33 ms) transient snap under heavy 150 ms packet-reordering jitter that self-heals on the very next tick (`enable_diff_states = false`). Fixing the host input-hole `is_auth` check (bounded by a small reorder window so 5% packet loss never starves state updates) is cheap and worthwhile; do **not** let `D-10` block finishing Task E and getting the build onto two real Android phones for Device Checkpoints 1 & 2.


---

## Iteration 6 Audit Update (25 Nov 2026 16:05 — against `origin/main` `2a9e175`)

Merged `origin/main` (`0c8e6a4..2a9e175`: Device Checkpoint 2 draft & Rahul's changing-health-bar decision `0635a6e`/`0b10721`, netfox patch 14 `G-24` `a73b845`, `D-10` root-cause confirmation `406ecc5`, `D-12` + `G-25` acceptance `549cb15`, `G-15/17/19/23` landing `4bd6e34`, and open `net_blast_bomb_loss` flake `2a9e175`). Aligned `network-synchronization-server.gd`, `pickups.gd`, and `weapon_rules.gd` verbatim with `origin/main` so `geminiceo` carries zero drift on landed fixes; also audited the remaining unaudited modules (`combat/combat_math.gd`, `hazard/hazard_math.gd`, `effects/*.gd`, `scripts/game/arena_layout.gd`, `item_ids.gd`, `weapon_stats.gd`, `project.godot`, `export_presets.cfg`).

### New Confirmed Findings (Most Severe First)

#### 26. Root cause & fix for `net_blast_bomb_loss` intermittent failure (`2a9e175`): client history reads un-merged local prediction (`is_auth == false`) when Packet 2 (`client.vitals`) is dropped
- **Severity:** medium (test flake masking real convergence; gameplay itself self-heals on `explode + 2`)
- **Category:** Desync / Crashes and logic bugs (test harness)
- **Location:** `tests/test_combat_objects.gd:142-160, 187-221` (`_read_history`, `_dump`)
- **What happens and how to trigger it:** Under `SIM_LATENCY_MS=75` + `SIM_LOSS=5`:
  1. **Asymmetric send count + 508-byte packet split:** On tick `explode`, `_watch` (`Obj6`, inputless) and `dummy.vitals` (host-owned input) are marked `is_auth = true` and sent on **Host Pass 1** (at real-time tick `explode`) *and* again on **Host Pass 2** (when `client.input[explode]` arrives 75 ms later), giving them two transmissions (`0.05^2 = 0.25%` loss). By contrast, `client.vitals` is linked to `client.input` in `RollbackSimulationServer._input_graph`, so on Host Pass 1 `_is_predicting` is `true` and `client.vitals` is **omitted**; it is sent **only once** (on Pass 2), and because the full state across `Spot0..3`, `Obj6`, `Bot1`, `Bot0`, `Bot2` exceeds `max_sync_packet_size = 508` bytes, `_DenseSnapshotSerializer` puts `Bot2` (`client.vitals`) in a separate UDP packet from `_watch` and `dummy.vitals`.
  2. **Unchecked `require_auth` reads local prediction:** Because `CombatResolver` does not run on clients, local prediction of tick `explode` writes `client.vitals` with `health = 100.0` and `is_auth = false` into `_rb_state_snapshots[explode + 1]`. When `SIM_LOSS=5` drops Pass 2's single UDP packet for `client.vitals` at `explode + 1`, `test_combat_objects.gd:144` calls `snapshot.has_subject(client.vitals)` (default `require_auth = false`), accepting the un-merged `100.0` HP prediction even though `explode + 2` received the authoritative `79.17` HP. Real gameplay and effects (`Hud`, `EffectsDirector`) self-heal cleanly one tick (33 ms) later.
- **Suggested fix:** Record per-subject `snapshot.has_subject(..., true)` flags in `_read_history`, skip non-authoritative rows in `_rises`, and in `_dump()` read `client_hp` / `dummy_hp` from the nearest authoritative row within `explode + 1..explode + 6` when `explode + 1`'s packet for that subject was lost. *(Fixed on `geminiceo`; verified in `tests/test_security_audit.gd`.)*

#### 27. `4bd6e34` flick aim refresh misses a curved flick pulled back inside the fire ring before the next tick
- **Severity:** low
- **Category:** Crashes and logic bugs
- **Location:** `scripts/ui/touch_controls.gd:174-177, 193-199` (`_touch`, `_update_aim`)
- **What happens and how to trigger it:** In `4bd6e34`, `pending_touch_fire_aim` is only refreshed on thumb lift (`_touch(..., pressed=false)`), not during `_drag`. Trigger: within one network tick (< 33 ms), drag right past the fire ring (`(1, 0)`), curve up while still outside the ring (`(0, -1)`), then pull back inside the fire ring before lifting (or before the tick fires). Because `_is_fire_held()` is now `false` on lift, `_touch` skips the refresh and `BotInput` fires at the stale initial crossing angle `(1, 0)`.
- **Suggested fix:** Refresh `InputActions.pending_touch_fire_aim = _aim.value(_cfg.stick_radius_px)` inside `_update_aim` whenever `_is_fire_held() and (not was_firing or InputActions.pending_touch_fire_aim != Vector2.ZERO)`, removing the redundant lift-only branch in `_touch`. Preserves zero extra shots on pull-back after a sampled tick and zero extra shots after a held lift. *(Fixed on `geminiceo`; passes both `test_touch_input.tscn` and `test_security_audit.tscn`.)*

### Areas With No New Findings (Iteration 6)
- **Full pass of remaining game modules (`combat/combat_math.gd`, `hazard/hazard_math.gd`, `effects/debris_piece.gd`, `effects/parts_burst.gd`, `effects/hit_flash.gd`, `effects/hit_freeze.gd`, `effects/screen_shake.gd`, `effects/debris_layers.gd`, `scripts/game/arena_layout.gd`, `item_ids.gd`, `weapon_stats.gd`):** Clean finite/zero guards, proper `DEBRIS` layer isolation (`1 << 15`), bounded debris cap (`max_debris = 60`), safe material/transform restore on `_exit_tree()`.
- **Android and privacy (`export_presets.cfg`):** Only `permissions/internet=true`, `user_data_backup/allow=false`, `arm64-v8a=true`, no secrets or keystores.
- **Network trust, DoS, Untrusted input, Purchases/unlocks, Repository hygiene, Performance:** None found.

### Could Not Check (Iteration 6)
- Multi-process loopback UDP tests (`net_*.sh`, including `net_combat_objects.sh`) and `test_full_state_coverage.tscn` (loopback UDP blocked in sandbox); real Android device testing (Device Checkpoints 1 & 2).

### CEO Review (Iteration 6)
1. **Great product decision on health bars (`0b10721`):** Showing a bot's health bar only while health is changing (~1.5 s) with a color flip at `<= 25` HP keeps the grey-box/final arena uncluttered while solving the core readability gap for the 2x low-health knockback push.
2. **`net_blast_bomb_loss` is a test-harness artifact, not a gameplay blocker:** Because `Hud` and `EffectsDirector` self-heal on `explode + 2` (33 ms later), fixing `test_combat_objects.gd` to check `has_subject(..., true)` removes the 3-in-16 flake cleanly without adding redundant server bandwidth.
3. **Ship the Device Checkpoint 2 APK next:** Once Task D's follow-up (`G-21`/`G-22`), Task E (effects + changing health bars), and netfox patch 15 (`D-10`) merge, cut the debug APK immediately and get two phones running the 10-minute knockback sandbox — nothing else should come before real thumb feel and hotspot validation.


---

## Iteration 7 Audit Update (25 Nov 2026 16:40 — against `origin/main` `22dd106`)

Merged `origin/main` (`2a9e175..22dd106`: Task E presentation effects & changing health bar `0cfa603`, D-13 shared `Bot.input_aim_direction` `8ccb4b7`, and Device Checkpoint 1/2 APK scripts `715c149`/`22dd106`). Audited every new and changed script (`scripts/fx/counter_watch.gd`, `scripts/fx/health_bar_state.gd`, `scripts/fx/shot_fx.gd`, `scripts/fx/effects_director.gd`, `scripts/game/bot_visual.gd`, `scripts/game/bot.gd`, `scripts/game/bot_arsenal.gd`, `scripts/game/bot_gadgets.gd`, `scripts/game/tuning_config.gd`, `config/tuning.tres`).

### Findings (0cfa603..22dd106)
- **Crashes and logic bugs:** none found. (`EffectsDirector` validates `is_instance_valid(bot)`, `is_node_ready()`, finite directions, `stats != null`, and `range_px > 0` under `tuning.tres`; `ShotFx` uses fixed-size `Packed*Array` rings; `HealthBarState` guards `is_finite(health)` and `max_health <= 0.0`; `Bot.input_aim_direction` runs after `facing` updates and stays consistent across aim line, shots, melee, and gadgets.)
- **Network trust:** none found. (Task E adds zero RPCs, reads only host-authoritative or locally predicted presentation counters, and writes no simulation state.)
- **Desync:** none found. (Effects and health bars run strictly on frame time in presentation nodes, use dedicated `RandomNumberGenerator` instances, and never mutate rollback state; verified by `test_fx_director.tscn` 112/112.)
- **Denial of service:** none found. (Fixed `fx_pool_size = 16` shape rings, `debris_max = 60`, host-owned counters.)
- **Untrusted input:** none found. (`Bot.input_aim_direction` routes `input.aim` through `Bot.clean_vector`.)
- **Purchases and unlocks:** none found (not yet present).
- **Android and privacy:** none found. (Device Checkpoint 2 APK uses `arm64-v8a`, target 36, `INTERNET` permission only.)
- **Repository hygiene:** none found. (Debug APK stays out of git under `builds/`.)
- **Performance bugs:** none found. (`ShotFx` stops `_process` when idle and allocates nothing per shot; `test_fx_director.tscn` confirms flat node and object counts over 580 frames.)

### Unmerged `geminiceo` Fixes Still Active (verified 7/7 in `tests/test_security_audit.tscn`)
- `G-21a/b` (`scripts/game/gadget_rules.gd`): rocket hitting wall/floor or max-range tick still resolves earlier bot contact first.
- `G-22` (`scripts/game/gadget_rules.gd`): gadget cycle reset runs before blasts/plates/throws and clears prior-cycle objects even if a stall skips the exact boundary tick.
- `G-26` (`tests/test_combat_objects.gd`): `net_blast_bomb_loss` flake fix — record per-subject `snapshot.has_subject(..., true)` flags and read `client_hp` / `dummy_hp` from the nearest authoritative row within `explode + 1..explode + 6`.
- `G-27` (`scripts/ui/touch_controls.gd`): refresh `pending_touch_fire_aim` in `_update_aim` while armed so a curved flick pulled back inside the fire ring before the next tick keeps its curved angle.

### Could Not Check (Iteration 7)
- Multi-process loopback UDP tests (`net_*.sh`, including new `tests/net_fx.sh`), `test_fx_client.tscn`, and `test_full_state_coverage.tscn` (loopback UDP blocked in sandbox; `test_fx_client.tscn` creates an ENet client to `127.0.0.1` which immediately fails in sandbox and drops to `OfflineMultiplayerPeer`).
- Real Android device testing (Device Checkpoints 1 & 2 APK).

### CEO Review (Iteration 7)
1. **Milestone hit — Device Checkpoint 2 APK is cut (`8ccb4b7`, 28.6 MB):** Task E landed cleanly (112/112 headless checks, zero simulation writes, crisp changing-only health bars) and the APK is ready for Rahul's two-phone test.
2. **Next priorities after phone feedback:** Merge the three remaining in-progress items (Task D `G-21`/`G-22` follow-up, netfox patch 15 for `D-10`, and `G-26` for the `net_blast_bomb_loss` flake), then act strictly on what Rahul feels on real thumbs before starting Dabba or Phase 2.


---

## Iteration 8 Audit Update (25 Nov 2026 17:30 — against `origin/main` `7c2da44`)

Merged `origin/main` (`22dd106..7c2da44`: D-14 `last_shot_weapon` `e5f9fec`, Task D follow-ups landing `G-21a/b`, `G-22`, and `G-26` + zero-speed rocket fallback `b90d525`, cycle clean-up ordered ahead of `WeaponRules.collect` `7c2da44`, and rebuilt Device Checkpoint 2 debug APK `a888e93`/`36fa991`). Aligned `scripts/game/gadget_rules.gd`, `tests/test_world_objects.gd`, and `tests/test_combat_objects.gd` verbatim with `origin/main` so `geminiceo` carries zero drift on landed fixes.

### Findings (22dd106..7c2da44)
- **Crashes and logic bugs:** none found. (`WorldObjects._rocket_range_tick` now guards `normal_step > 0.0 and is_finite(normal_step)` with `bomb_fuse_time` fallback; `WorldObjects.launch` initializes `rocket_step_start = pos_px` so even wall-overlap rockets sweep cleanly; `GadgetRules.clear_old_cycle` runs first in `CombatResolver.resolve`, preventing old-cycle plates/bombs from absorbing boundary-tick shots while preserving rockets/gadgets launched on the boundary tick.)
- **Network trust:** none found. (`BotArsenal.last_shot_weapon` is host-authoritative rollback state registered on `Bot/Arsenal` in `scenes/bot.tscn`; no new RPCs.)
- **Desync:** none found. (`last_shot_weapon` is part of rollback state and written deterministically in `_fire`; `EffectsDirector._on_shot` reads `last_shot_weapon` instead of `active_weapon()`.)
- **Denial of service:** none found.
- **Untrusted input:** none found.
- **Purchases and unlocks:** none found (not yet present).
- **Android and privacy:** none found.
- **Repository hygiene:** none found.
- **Performance bugs:** none found.

### Unmerged `geminiceo` Fix Still Active (verified 1/1 in `tests/test_security_audit.tscn`)
- `G-27` (`scripts/ui/touch_controls.gd`): refresh `pending_touch_fire_aim` in `_update_aim` while armed so a curved flick pulled back inside the fire ring before the next tick keeps its curved angle.

### Could Not Check (Iteration 8)
- Multi-process loopback UDP tests (`net_*.sh`), `test_fx_client.tscn`, and `test_full_state_coverage.tscn` (loopback UDP blocked in sandbox); real Android device testing (Device Checkpoints 1 & 2 APK).

### CEO Review (Iteration 8)
1. **Clean sweep on Phase 1 combat/object bugs:** Every high/medium bug from Iterations 4–6 (`G-21a/b`, `G-22`, `G-23`, `G-24`, `G-26`, plus `D-13`/`D-14` and the `clear_old_cycle` ordering polish) is now on `main` and in the rebuilt debug APK.
2. **Hold feature work for phone feedback:** With only netfox patch 15 (`D-10`) and low-severity `G-27` remaining open, the highest-leverage next step is Rahul running Device Checkpoints 1 and 2 on two phones to validate stick/button ergonomics, knockback feel, and hotspot stability before starting Dabba or Phase 2.


---

## Iteration 9 Audit Update (25 Nov 2026 18:12 — against `origin/main` `50f7445`)

Merged `origin/main` (`7c2da44..50f7445`: `G-27` landed in `588a572`, phase 1 design-numbers & authority audits in `834d6da`/`024da7d`, netfox patch 15 review in `17aeef5`, and `D-15` in `50f7445`). Aligned `scripts/ui/touch_controls.gd` verbatim with `origin/main`. Audited `NetworkIdentityServer`, `_IdentityPacketSerializer`, `NetworkCommandServer`, and `NetworkSchemas` string/variant/snapshot decoders for remote crash and DoS vectors missed by the authority audit.

### New Confirmed Findings (Most Severe First)

#### 28. Remote 4-byte identity packet immediately crashes the host process with `SIGBUS` (`rc=-10`) + missing identity packet size cap
- **Severity:** critical
- **Category:** Denial of service / Crashes and logic bugs
- **Location:** `addons/netfox/serializers/identity-packet-serializer.gd:28-32`, `addons/netfox/schemas/network-schemas.gd:499-500`, `addons/netfox/servers/network-identity-server.gd:192-193`
- **What happens and how to trigger it:** `NetworkIdentityServer` registers command `#0` (`_handle_ids`) on `NetworkCommandServer`, accepting reliable RPC or raw packets from any connected peer (including an unaccepted/rejected 5th peer during the 0.5 s notice window). `_IdentityPacketSerializer.deserialize` calls `buffer.get_utf8_string()` (default `-1`), which in Godot 4.7.2 reads a 32-bit signed length and allocates a `Vector<uint8_t>` of that size before checking `get_available_bytes()`. Sending the 4-byte payload `[0xff, 0xff, 0xff, 0x7f]` (`0x7fffffff` = 2 GB) to command `#0` immediately kills the Godot host process with `SIGBUS` (signal 10, exit code `-10`, reproduced directly in headless Godot 4.7.2). The identical `b.get_utf8_string()` call in `NetworkSchemas._StringSerializer.decode` also crashes with `rc=-10` on the same 4 bytes. Additionally, `_handle_ids` has no packet-size cap (unlike `NetworkSynchronizationServer`'s 16,384-byte limit), allowing multi-megabyte identity packets (63 KB of 2-byte names takes ~54 ms and builds 8,100+ dictionary entries).
- **Suggested fix:** Validate `str_len` (`>= 0` and `<= buffer.get_available_bytes()`) before reading UTF-8 bytes in `_IdentityPacketSerializer.deserialize` and `NetworkSchemas._StringSerializer.decode`, and cap `data.size()` in `NetworkIdentityServer._handle_ids` at `max_incoming_packet_size = 16384`. *(Fixed on `geminiceo`; verified in `tests/test_security_audit.tscn`.)*

#### 29. Truncated 3-byte raw command prefix (`\0nf`) triggers buffer underflow and spuriously dispatches command `#0`
- **Severity:** low
- **Category:** Crashes and logic bugs / Untrusted input
- **Location:** `addons/netfox/servers/network-command-server.gd:137-159`
- **What happens and how to trigger it:** `_PacketTransport` is always connected to `SceneMultiplayer.peer_packet` (even when `use_raw_commands` is `false`). `is_command_packet(packet)` only checks `packet.size() < _packet_prefix.size()` (3 bytes) without requiring the 1-byte command index. Any peer calling `send_bytes(PackedByteArray([0, 78, 70]))` hits `buffer.get_u8()` at 0 remaining bytes, causing `get_u8()` to return `0` and spuriously dispatch command `#0` (`NetworkIdentityServer._handle_ids`) with an empty payload.
- **Suggested fix:** Require `packet.size() >= _packet_prefix.size() + 1` in `_PacketTransport._handle_packet` before calling `buffer.get_u8()`. *(Fixed on `geminiceo`; verified in `tests/test_security_audit.tscn`.)*

### Areas With No New Findings (Iteration 9)
- **`NetworkSchemas.variant()` (`get_var(false)`), `_NetworkIdentityReferenceSerializer` (`c_string()`), and `StreamPeerBuffer.get_partial_data(0x7fffffff)`:** Tested directly in Godot 4.7.2; all safely reject or clamp bogus `0x7fffffff` lengths without crashing or over-allocating.
- **Network trust, Desync, Purchases/unlocks, Android/privacy, Repository hygiene, Performance:** None found (beyond items already logged in `docs/reviews/phase-1-handoff.md`: past-tick input bound in patch 15, log-flood rate limiting in patch 16, and push-distance correction).

### Could Not Check (Iteration 9)
- Multi-process loopback UDP suites (`tests/net_*.sh`), `tests/test_fx_client.tscn`, and `tests/test_full_state_coverage.tscn` (loopback UDP blocked in sandbox); real Android device testing (Device Checkpoints 1 & 2).

### CEO Review (Iteration 9)
1. **Great catch by both the phase 1 audit and this pass:** The design-numbers audit catching push distances vs speeds (0.5 bh vs 2.5 bh on ground) explains why knockback could feel flat on phones, and `D-15` tying the phone playtest to the corrected knockback build is the exact right call.
2. **Patch `G-28` alongside netfox patch 16:** Because `G-28` is a 4-byte instant host crash (`SIGBUS`) reachable even by a rejected 5th peer on a local hotspot (and later over internet relay), fold the 10-line length check + 16 KB cap into netfox patch 16 before shipping the next APK.


---

## Iteration 10 Audit Update (25 Nov 2026 18:29 — against `origin/main` `dc56a86`)

Merged `origin/main` (`50f7445..dc56a86`: D-16 `melee_dir` in `509e41b` and acceptance of `G-28`/`G-29` for netfox patch 16 in `dc56a86`). Audited `509e41b` (`scenes/bot.tscn`, `scripts/game/bot_arsenal.gd`, `scripts/game/weapon_rules.gd`, `scripts/fx/effects_director.gd`) and swept all remaining binary decoders in `addons/netfox/`.

### Findings (`50f7445..dc56a86`)
- **Crashes and logic bugs:** none found. (`BotArsenal.melee_dir` is registered rollback state, written deterministically on melee ticks, normalized and zero-guarded in `WeaponRules._collect_melee` and `EffectsDirector._on_swing`.)
- **Network trust:** none found. (`melee_dir` is host-authoritative rollback state on `Bot/Arsenal`; no new RPCs.)
- **Desync:** none found.
- **Denial of service:** none found beyond `G-28`/`G-29` (active on `geminiceo`, accepted for netfox patch 16). Note for patch 16's decoder sweep: `_ArraySerializer` and `_DictionarySerializer` in `addons/netfox/schemas/network-schemas.gd:868-906` read unchecked counts (`array.resize(item_count)`), though neither schema is used by Jetpack Brawler today.
- **Untrusted input, Purchases/unlocks, Android/privacy, Repository hygiene, Performance bugs:** none found.

### Unmerged `geminiceo` Fixes Still Active (verified 6/6 in `tests/test_security_audit.tscn`)
- `G-28` (`addons/netfox/serializers/identity-packet-serializer.gd`, `addons/netfox/schemas/network-schemas.gd`, `addons/netfox/servers/network-identity-server.gd`): length-checked UTF-8 decoding (prevents 4-byte `SIGBUS` host crash) + 16 KB incoming identity packet cap. Accepted in `dc56a86` for netfox patch 16.
- `G-29` (`addons/netfox/servers/network-command-server.gd`): require `packet.size() >= _packet_prefix.size() + 1` in `_PacketTransport._handle_packet`. Accepted in `dc56a86` for netfox patch 16.

### Could Not Check (Iteration 10)
- Multi-process loopback UDP suites (`tests/net_*.sh`), `tests/test_fx_client.tscn`, and `tests/test_full_state_coverage.tscn` (loopback UDP blocked in sandbox); real Android device testing (Device Checkpoints 1 & 2).

### CEO Review (Iteration 10)
1. **Clean convergence toward the Phase 1 APK:** `G-28` and `G-29` are accepted into netfox patch 16 alongside log-flood hardening, the push-distance fix is actively in progress (`3a0bafb` on its worktree), and `D-16` closed the last presentation-direction overlap.
2. **Next gate:** Once push distances, patch 15 (past-tick input bound + D-10), and patch 16 (`G-28`/`G-29` + log limits) merge, cut the fresh debug APK and run Rahul's two-phone playtest immediately before starting Dabba.


---

## Iteration 11 Audit Update (25 Nov 2026 18:50 — against `origin/main` `cf0dfdd`)

Merged `origin/main` (`dc56a86..cf0dfdd`: Iteration 10 recorded in `67ff235`; `cf0dfdd` recorded the `net_fx` 1-in-10 flake and push-fix second round). Diagnosed the exact cause of the `net_fx` flake (`G-30`).

### New Confirmed Finding

#### 30. Root cause & fix for `net_fx` 1-in-10 flake (`cf0dfdd`): `_wait_ticks(10)` starts before `NetworkTime.is_initial_sync_done()`, so the initial tick jump (`0 -> host tick`) bypasses the rollback loop
- **Severity:** medium (test flake in `tests/test_fx_net.gd`; `EffectsDirector` itself is unaffected)
- **Category:** Crashes and logic bugs (test harness timing)
- **Location:** `tests/test_fx_net.gd:89-92, 141-147` (`_wait_ticks`, `_run_client`), interacting with `addons/netfox/network-time.gd:429-459` (`start`)
- **What happens and how to trigger it:** On connect, `NetworkTime._tick` starts at `0` while `_initial_sync_done` is `false`. Because the host already has `Bot0` (dummy) and `Obj2` (`_bomb_slot()`) active from tick 0, `MultiplayerSpawner` replicates `Bot0` and netfox merges host snapshots for `dummy.vitals`, `dummy.arsenal`, and `_bomb_slot()` while `NetworkTime.tick == 0` (setting `has_authoritative_state == true` before initial clock sync finishes). `_run_client` then exits line 141 with `NetworkTime.tick == 0` and calls `_wait_ticks(10)` (`until = 10`). On the frame `NetworkTimeSynchronizer.on_initial_sync` fires, `NetworkTime` jumps `_tick` directly from `0` to the host tick (~20–30, `>= 10`) and sets `_next_tick_time = _clock.get_time()` (`ticks_in_loop == 0` on that frame). `_wait_ticks(10)` returns immediately before any rollback loop has copied the merged host state onto the live nodes, so line 146 reads zeros (`hits 0, shots 0, blasts 0`). `EffectsDirector._has_real_state` is unaffected because it gates on `_loops > watch.armed_at_loop`.
- **Suggested fix:** Include `not NetworkTime.is_initial_sync_done()` in the wait loop at `tests/test_fx_net.gd:141` and `await NetworkRollback.after_loop` before `await _wait_ticks(10)` so `_wait_ticks` never computes `until` from pre-sync tick `0` and always runs after at least one finished rollback loop. *(Fixed on `geminiceo`.)*

### Areas With No New Findings (Iteration 11)
- No production code changed in `dc56a86..cf0dfdd` (docs only). All 9 security/bug categories remain clean beyond active `G-28`/`G-29` (in progress for netfox patch 16).

### Could Not Check (Iteration 11)
- Running `tests/net_fx.sh` end-to-end (loopback UDP blocked in sandbox); real Android device testing.

### CEO Review (Iteration 11)
1. **Strong engineering discipline on the push-distance fix (`cf0dfdd`):** Rejecting the first push fix because 30 rapid bolts stacked to 19.6 bh (vs 3 bh design) prevented a huge gameplay balance bug from sneaking into the phone test.
2. **All three blockers (`push distances`, `patch 15`, `patch 16` incl. `G-28`) are clearly scoped:** Once they land and `net_fx` stops flaking (`G-30`), build the APK and get two phones into Rahul's hands.


---

## Iteration 12 Audit Update (25 Nov 2026 21:05 — against `origin/main` `0229176`)

Merged `origin/main` (`cf0dfdd..0229176`: `G-30` recorded in `e8bfcef`, push-distance physics rewrite in `24f0224`, and rebuilt Device Checkpoint 2 debug APK in `0229176`). Audited all modified files in `24f0224` (`combat/combat_math.gd`, `hazard/hazard_math.gd`, `scripts/fx/health_bar_state.gd`, `scripts/game/bot.gd`, `scripts/game/bot_arsenal.gd`, `scripts/game/bot_vitals.gd`, `scripts/game/combat_rules.gd`, `scripts/game/gadget_rules.gd`, `scripts/game/hit.gd`, `scripts/game/tuning_config.gd`, `scripts/game/weapon_stats.gd`, `config/tuning.tres`). Verified **25/25** non-UDP headless Godot suites pass (including new `tests/test_push_distance.tscn` 116/116).

### Findings (`cf0dfdd..0229176`)
- **Crashes and logic bugs:** none found. (`CombatMath.launch_speed` and `travel_distance` guard non-finite and `<= 0` inputs; `CombatRules._axis_change` and `push_window_ticks` are deterministic with finite positive `ground_brake * push_window_control * dt` from `tuning.tres`; `HazardMath.is_in_metal` returns `false` before `start_time_s` or when `ticks < 0`; `HealthBarState.is_low` now uses `<` matching `CombatMath.push_multiplier`; `Bot._tick_free_movement` ensures holding stick against a push brakes at least as hard as a neutral stick.)
- **Network trust:** none found. (No new RPCs; all push math runs deterministically from server-owned `TuningConfig` and `CombatRules`.)
- **Desync:** none found. (`CombatRules.push_change` and `push_window_ticks` are pure functions of restored velocity, distance, and `MatchSettings.tuning_at(tick)`.)
- **Denial of service:** none found beyond active `G-28`/`G-29` (in review as netfox patch 16 on worktree `4c66e72`).
- **Untrusted input, Purchases/unlocks, Android/privacy, Repository hygiene, Performance bugs:** none found.

### Active Unmerged `geminiceo` Fixes
- `G-28` & `G-29` (`addons/netfox/`): 4-byte `SIGBUS` crash fix + 16 KB identity packet cap + truncated 3-byte raw command prefix guard (verified 6/6 in `tests/test_security_audit.tscn`; accepted for netfox patch 16, in review on `4c66e72`).
- `G-30` (`tests/test_fx_net.gd`): wait for `NetworkTime.is_initial_sync_done()` + `NetworkRollback.after_loop` before `_wait_ticks(10)` (recorded in `e8bfcef`, being verified).

### Could Not Check (Iteration 12)
- Multi-process loopback UDP suites (`tests/net_*.sh`), `tests/test_fx_client.tscn`, and `tests/test_full_state_coverage.tscn` (loopback UDP blocked in sandbox); real Android device testing (Device Checkpoints 1 & 2 APK).

### CEO Review (Iteration 12)
1. **First truly playtest-ready APK (`0229176`):** Push numbers now match GDD distances (melee 2.50 bh, close scrap 1.50 bh, bolt 0.10 bh, blast center 5.00 bh, recoil 1.00 bh, 30 bolts = 3.08 bh) with 116/116 push-distance checks green and the floor-metal false-KO fixed.
2. **Playtest now, land patches 15 & 16 next:** Rahul has a clean, accurate build to run the 10-minute knockback fun test on two phones right away, while netfox patch 16 (`G-28`/`G-29` + log limits) and patch 15 (`D-10` + past-tick input bound) finish review. Keep Dabba held until phone feedback comes back.


---

## Iteration 13 Audit Update (25 Nov 2026 21:29 — against `origin/main` `2326514`)

Merged `origin/main` (`0229176..2326514`: `G-30` landed in `1414f84` with 0 failures in 120 runs, and D-17 counter-push window shortening in `2326514`). Aligned `tests/test_fx_net.gd` verbatim with `origin/main`. Audited `2326514` (`scripts/game/bot_arsenal.gd`, `scripts/game/combat_rules.gd`, `tests/test_push_distance.gd`).

### Findings (`0229176..2326514`)
- **Crashes and logic bugs:** none found. (`CombatRules.push_window_end_tick` cleanly shortens `push_until_tick` when `absf(sideways_speed) < absf(previous_speed)` and keeps `maxi(previous_end, end)` when speed grows; zero remaining speed closes the window on `tick + 1` as expected.)
- **Network trust:** none found. (No new RPCs or client-owned state.)
- **Desync:** none found. (`push_window_end_tick` is a pure function of `tick`, restored speeds, and `TuningConfig`, applied identically in both `CombatRules._apply_hits` and `BotArsenal._fire`.)
- **Denial of service:** none found beyond active `G-28`/`G-29` (in final review as netfox patch 16 on worktree `4f4842d`).
- **Untrusted input, Purchases/unlocks, Android/privacy, Repository hygiene, Performance bugs:** none found.

### Active Unmerged `geminiceo` Fixes
- `G-28` & `G-29` (`addons/netfox/`): 4-byte `SIGBUS` crash fix + 16 KB identity packet cap + truncated 3-byte raw command prefix guard (verified 6/6 in `tests/test_security_audit.tscn`; accepted for netfox patch 16, in review on `4f4842d`).

### Could Not Check (Iteration 13)
- Multi-process loopback UDP suites (`tests/net_*.sh`), `tests/test_fx_client.tscn`, and `tests/test_full_state_coverage.tscn` (loopback UDP blocked in sandbox); real Android device testing.

### CEO Review (Iteration 13)
1. **Clean execution:** `G-30` (`net_fx` 0/120 flakes) and `D-17` (opposing pushes/recoil no longer leave dead steering windows) both landed cleanly, while netfox patch 15 (`08fa764`) and patch 16 (`4f4842d`) are in final review on their worktrees.
2. **Next step:** Once patches 15 and 16 merge onto `main`, cut the security-hardened Phase 1 APK so Rahul's two-phone test runs on the final Phase 1 netcode + knockback physics.


---

## Iteration 14 Audit Update (25 Nov 2026 22:10 — against `origin/main` `cf9c87a`)

Merged `origin/main` (`2326514..cf9c87a`: netfox patch 16 landing `G-28`, `G-29`, variant/clock header guards, and log rate limits in `4f4ea2d`/`cf9c87a`, plus rebuilt hardened debug APK in `cd8ad46`). Aligned all four netfox files (`network-schemas.gd`, `identity-packet-serializer.gd`, `network-command-server.gd`, `network-identity-server.gd`) verbatim with `origin/main`, then audited every line of patch 16 and found one remaining Unicode log-flood vector (`G-31`).

### New Confirmed Finding

#### 31. `_CStringSerializer.decode` (used by `_NetworkIdentityReferenceSerializer` on every incoming snapshot/input packet) still triggers 15,000 `Unicode parsing error` lines (~100 ms) per 15 KB packet (`G-31`)
- **Severity:** medium
- **Category:** Denial of service
- **Location:** `addons/netfox/schemas/network-schemas.gd:530-544` (`_CStringSerializer.decode`), called via `_NetworkIdentityReferenceSerializer.decode` from `addons/netfox/serializers/dense-snapshot-serializer.gd:71` and `addons/netfox/serializers/sparse-snapshot-serializer.gd:70`
- **What happens and how to trigger it:** Patch 16 (`4f4ea2d`) closed the per-byte `Unicode parsing error` log flood in `_IdentityPacketSerializer` (rejecting names > 128 bytes or containing bytes `>= 0x80`), `_VariantSerializer`, and `_NetworkTimeSynchronizer`, but left `_CStringSerializer.decode` calling `data.get_string_from_utf8()` on unchecked raw bytes. Any connected peer (including an unaccepted 5th peer during the 0.5 s notice window) can send an unreliable rollback input packet (`<= 16,384` bytes, below `max_incoming_packet_size`) whose frame begins with `id = 0` followed by 15,000 `0xff` bytes and `0x00`. Measured on `origin/main` `cf9c87a`: a single packet prints **15,000 `Unicode parsing error` lines** and blocks the host for **100 ms** on Mac before ownership is checked.
- **Suggested fix:** In `_CStringSerializer.decode`, reject bytes `>= 0x80` and lengths above `_IdentityPacketSerializer.MAX_NAME_BYTES` (128) while consuming to the NUL terminator, decoding valid ASCII via `get_string_from_ascii()` and returning `""` otherwise (0 error lines, bounded 128-byte allocation). *(Fixed on `geminiceo`; verified in `tests/test_security_audit.tscn`.)*

### Areas With No New Findings (`2326514..cf9c87a`)
- **Patch 16 (`_VariantSerializer`, `_IdentityPacketSerializer`, `_NetworkTimeSynchronizer`, `NetworkCommandServer`, `NetworkIdentityServer`, `NetworkTickrateHandshake`):** `G-28`, `G-29`, variant type/size tables (including the `type > TYPE_COLOR` shift-wrap guard), clock scalar/pong payload checks, and per-peer log rate limits are all sound and cleanly reset on `NetworkTime.stop()`.
- **Crashes and logic bugs, Network trust, Desync, Untrusted input, Purchases/unlocks, Android/privacy, Repository hygiene, Performance:** none found.

### Could Not Check (Iteration 14)
- Multi-process loopback UDP suites (`tests/net_*.sh`), `tests/test_fx_client.tscn`, and `tests/test_full_state_coverage.tscn` (loopback UDP blocked in sandbox); real Android device testing (rebuilt APK `cd8ad46`).

### CEO Review (Iteration 14)
1. **Major security milestone landed (`4f4ea2d`, `cf9c87a`, `cd8ad46`):** The 4-byte `SIGBUS` crash (`G-28`), truncated prefix bug (`G-29`), variant/clock malformed-header floods, and log rate limits are all on `main` and baked into the rebuilt debug APK (`cd8ad46`).
2. **One quick follow-up (`G-31`), then phones first:** Folding `_CStringSerializer`'s 10-line ASCII/length check into patch 16 closes the last per-byte Unicode log-flood path; meanwhile the `cd8ad46` APK is already solid for Rahul's two-phone hotspot playtest.


---

## Iteration 16 Audit Update (25 Nov 2026 23:47 — against `origin/main` `e3f6f4f`)

Merged `origin/main` (`486e5dd..e3f6f4f`: `G-31` landed in `e3f6f4f` using `PackedByteArray.find(0, start)` + ASCII/length guard + missing-NUL rejection, with 123 checks in `tests/test_netfox_handlers.gd` and full second byte-to-text sweep in `addons/NETFOX_PATCHES.md`). Aligned `addons/netfox/schemas/network-schemas.gd` verbatim with `origin/main` and removed the superseded `tests/test_security_audit.*` so `geminiceo` now has zero code drift against `origin/main` (`e3f6f4f`).

### Findings (`486e5dd..e3f6f4f`)
- **Crashes and logic bugs:** none found. (`_CStringSerializer.decode` uses `raw.find(0, start)`, seeks to `raw.size()` when NUL is missing and `end + 1` otherwise, rejects `end - start > MAX_NAME_BYTES` and any byte `>= 0x80`, and decodes valid ASCII via `get_string_from_ascii()`.)
- **Network trust, Desync, Denial of service, Untrusted input, Purchases/unlocks, Android/privacy, Repository hygiene, Performance bugs:** none found.

### Could Not Check (Iteration 16)
- Multi-process loopback UDP suites (`tests/net_*.sh`), `tests/test_fx_client.tscn`, and `tests/test_full_state_coverage.tscn` (loopback UDP blocked in sandbox); real Android device testing.

### CEO Review (Iteration 16)
1. **Every accepted `geminiceo` finding (G-1 through G-31) is now landed on `main`:** Zero open findings remain on `geminiceo`, and netfox patch 16 is completely buttoned up (123/123 handler checks green).
2. **Final Phase 1 netcode item:** Netfox patch 15 (`D-10` + past-tick input bound) is actively wrapping up on its worktree (`94f7575`). Once patch 15 lands, cut the final Phase 1 debug APK so Rahul's two-phone playtest validates the complete Phase 1 build before starting Dabba.


---

## Iteration 17 Audit Update (26 Nov 2026 00:10 — against `origin/main` `c05420e`)

Merged `origin/main` (`e3f6f4f..c05420e`: netfox patch 15 landing `D-10` + past-tick input bound in `1d75eaf`, and rebuilt Phase 1 debug APK in `c05420e`). Audited every line of `1d75eaf` (`addons/netfox/rollback/network-rollback.gd`, `addons/netfox/servers/network-history-server.gd`, `addons/netfox/servers/network-synchronization-server.gd`, `addons/netfox/servers/rollback-simulation-server.gd`, `scripts/dev/autopilot_script.gd`, `scripts/dev/net_sim.gd`, `scripts/net/launch_args.gd`, `scripts/game/main.gd`).

### New Confirmed Finding

#### 32. `RollbackSimulationServer._get_earliest_expired_hole()` returns the first peer's accepted hole instead of the earliest tick across all peers (`G-32`)
- **Severity:** medium
- **Category:** Desync / Crashes and logic bugs
- **Location:** `addons/netfox/servers/rollback-simulation-server.gd:341-365` (`_get_earliest_expired_hole`)
- **What happens and how to trigger it:** Inside the outer `for input: Node in _input_graph._links_from` loop, line 364 executes `return tick` as soon as the first remote input node has an accepted hole or pre-start tick, never inspecting subsequent remote peers. Trigger in a 3+ player match: Peer A (first in `_input_graph._links_from`) has an accepted pre-start tick at `now - 2`, while Peer B (second) has an expired input hole at tick `11` (`now - 14`, past the 12-tick allowance). `_get_earliest_expired_hole()` returns `now - 2` instead of `11`. On that rollback loop, the host only rolls back to `now - 2` and sends authoritative states for Peer A at `now - 1..now` while leaving Peer B's expired hole unresolved until the next frame; on the next loop, the host rolls back to `11`, re-simulating and potentially replacing Peer A's already-sent authoritative states if Peer B interacted with Peer A during `11..now`.
- **Suggested fix:** Track `var earliest := -1` across all remote input nodes, update `earliest = tick if earliest < 0 else mini(earliest, tick)` and `break` out of the inner `for tick` loop instead of returning early, then `return earliest` (and guard `if nodes.is_empty(): continue` before `nodes[0]`). *(Fixed on `geminiceo`; verified failing on `c05420e` and passing after fix in `tests/test_security_audit.tscn`.)*

### Areas With No New Findings (`e3f6f4f..c05420e`)
- **Patch 15 (`_merge_rollback_input`, `_note_refused_input`, `_is_hole_accepted`, `_is_start_decided`, `_starts_from_carry_over`):** Input age refusal (> 12 ticks), per-peer rate-limited warnings, 1-second sliding window refusal counts (erased on `erase_peer` and `reset`), and dev-only `--sim-hold-*`/`--sim-drop-ms`/`--autopilot-wiggle` release guards in `launch_args.gd` are all clean.
- **Network trust, Denial of service, Untrusted input, Purchases/unlocks, Android/privacy, Repository hygiene, Performance bugs:** none found.

### Could Not Check (Iteration 17)
- Multi-process loopback UDP suites (`tests/net_*.sh`, including new `tests/net_late_input.sh` and `tests/net_lost_input.sh`), `tests/test_fx_client.tscn`, and `tests/test_full_state_coverage.tscn` (loopback UDP blocked in sandbox); real Android device testing (`c05420e` APK).

### CEO Review (Iteration 17)
1. **All major Phase 1 items are now in the `c05420e` APK:** Push distances, Task E effects + changing health bar, netfox patch 15 (`D-10` + past-tick input refusal), and netfox patch 16 (`G-28`, `G-29`, `G-31`, log rate limits) are all merged on `main` (59/59 suite) and built into the APK.
2. **Playtest right now, fold `G-32` cleanly alongside any phone-test polish:** `G-32` only triggers in 3+ player matches (2-phone hotspot tests have 1 client), so it does not block Rahul's Device Checkpoints 1 & 2 playtest — ship the 4-line fix into patch 15's follow-up while Rahul tests the APK on phones.
