# Patches to the bundled netfox addon

Netfox version: v1.49.12 (addons/netfox and addons/netfox.internals).
Re-apply every patch below after updating the addon, then run
`tests/test_input_flood.tscn`.

## 1. Reject snapshots stamped far in the future

- File: `addons/netfox/servers/network-history-server.gd`
- Function: `_can_merge_tick`
- Why: `_can_merge_tick` only checked the lower bound. Any client can send one
  input packet (netfox's `any_peer` command RPC) with a tick far ahead, for
  example current tick + 100000. Merging it makes the shared history buffer
  jump its head forward, after which the host's own records are discarded and
  no bot is simulated. `tests/test_input_flood.tscn` reproduces this: without
  the patch the bot stops moving after the packet.
- Bound: `NetworkRollback.history_limit` (netfox's own history size, 64 ticks
  by default), measured ahead of `NetworkTime.tick`. No new number.
- Coverage: `_merge_rollback_input`, `_merge_rollback_state` and
  `_merge_synchronizer_state` all call `_can_merge_tick`, so full state, diff
  state, sync state and input snapshots share the guard.

```diff
@@ -296,6 +296,13 @@
 	return has_updated
 
 func _can_merge_tick(tick: int, history: _PerObjectHistory) -> bool:
+	# PATCH (see addons/NETFOX_PATCHES.md): refuse ticks further ahead than the
+	# history can hold. One packet stamped far in the future would make the
+	# history buffers jump forward and discard everything the host recorded.
+	if tick > NetworkTime.tick + NetworkRollback.history_limit:
+		_logger.trace("Dropping snapshot @%d from too far in the future", [tick])
+		return false
+
 	if tick >= NetworkRollback.history_start:
 		return true
 
```
