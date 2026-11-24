# Patches to the bundled netfox addon

Netfox version: v1.49.12 (addons/netfox and addons/netfox.internals).
Re-apply every patch below after updating the addon, then run
`tests/test_input_flood.tscn` and `tests/test_security_audit.tscn`.

## 1. Tight future-tick window in `_can_merge_tick`

- File: `addons/netfox/servers/network-history-server.gd`
- Function: `_can_merge_tick`
- Why: The previous bound `NetworkTime.tick + NetworkRollback.history_limit`
  (`+64`) still allowed a client to stamp an input or state snapshot at
  `tick + 64`, which hits `_HistoryBuffer.set_at`'s `at >= head + _capacity`
  branch and wipes the entire 64-tick history buffer to `null`, causing the host
  to drop its own subsequent inputs. Limiting future lead to
  `input_delay + min(history_limit / 4, 16)` (16 ticks = ~533 ms at 30 tps)
  tolerates normal clock skew while guaranteeing the ring buffer cannot be
  wiped or active host history evicted.

## 2. Reject spoofed time-sync commands and prune unanswered ping samples

- File: `addons/netfox/network-time-synchronizer.gd`
- Functions: `_handle_set_timestamp`, `_handle_pong`, `_handle_ping`,
  `_handle_request_timestamp`, `_loop`, `stop`
- Why: All four handlers are registered via `NetworkCommandServer`
  (`@rpc("any_peer")`). Previously:
  - Any client could invoke `_cmd_set_time` on the host, overwriting the host's
    reference clock (including with `NAN` or huge values) and corrupting time for
    every peer.
  - Any client could invoke `_cmd_pong` on the host with malformed bytes,
    crashing `args[0]` with a runtime error.
  - Duplicate `_cmd_set_time` calls on a client spawned duplicate `_loop()`
    coroutines.
  - Dropped unreliable ping/pong packets leaked entries in `_awaiting_samples`
    for the entire session.
- Fix: Enforce server/client direction and `sender == 1` checks, validate
  `bytes_to_var` types and finiteness, guard `_loop()` with `_loop_running`, and
  prune stale `_awaiting_samples` entries.

## 3. Clear auth flag on sanitized snapshots and drop oversized/empty packets

- Files:
  - `addons/netfox/servers/data/snapshot.gd` (`sanitize`)
  - `addons/netfox/servers/network-synchronization-server.gd` (`_handle_*`, `_ingest_state`)
- Why: `sanitize(sender)` erased unauthorized subjects from `_data` but left
  them in `_auth_subjects`, and `_handle_*` still passed empty post-sanitize
  snapshots into `NetworkHistoryServer._merge_*` (allowing unauthorized peers to
  advance shared tick snapshot buffers) and accepted unbounded packet sizes.
- Fix: Erase unauthorized subjects from `_auth_subjects` too, reject empty or
  oversized sync packets (`> max(_max_packet_size * 4, 4096)` bytes), and return
  before merging when a sanitized snapshot is empty.

## 4. Bounds-check malformed snapshot/bitset/identity packets

- Files:
  - `addons/netfox/serializers/sparse-snapshot-serializer.gd` (`read_from`)
  - `addons/netfox/serializers/redundant-snapshot-serializer.gd` (`read_from`)
  - `addons/netfox/schemas/network-schemas.gd` (`_VariableBitsetSerializer.decode`)
  - `addons/netfox/servers/data/network-identifier.gd` (`set_id_for`)
- Why:
  - A crafted diff packet with a high bit set in `changed_bits` crashed
    `node_props[idx]` with an out-of-bounds index before `sanitize()` ran.
  - A crafted redundant-input packet filled with zero-length frames spun one
    `_dense_serializer.read_from` and `_Snapshot` merge per byte.
  - A crafted `0x80`-filled bitset grew unboundedly.
  - Sending `_cmd_ids` twice for the same node path with different IDs crashed
    debug/Android-Debug hosts on `assert()` in `set_id_for`.
- Fix: Bounds-check `idx` against `node_props.size()`, cap snapshot count and
  require `0 < snapshot_size <= available_bytes`, cap bitset decoding to 256
  bits and available bytes, and ignore conflicting peer ID re-registrations
  instead of asserting.

## 5. Synchronous `NetworkEvents.sync_state()` on session leave

- File: `addons/netfox/network-events.gd` (`sync_state`, `_process`)
- Why: `_NetworkEvents` only polled `is_server()` in `_process()`. If a host
  left and re-hosted before the next frame, `_is_server` stayed `true`, so
  neither `on_server_stop` nor `on_server_start` fired, leaving `NetworkTime`
  stopped and `BotSpawner` without a host bot.
- Fix: Factor `_process()` body into `sync_state()` and call it from
  `Session.leave()` after switching to `OfflineMultiplayerPeer`.
