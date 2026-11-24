# Patches to the bundled netfox addon

Netfox version: v1.49.12 (addons/netfox and addons/netfox.internals).
Re-apply every patch below after updating the addon, then run
`tests/test_input_flood.tscn` and `tests/test_clock_hijack.tscn`. Both must
fail without the patch and pass with it.

## 1. Reject snapshots stamped ahead of the current tick

- File: `addons/netfox/servers/network-history-server.gd`
- Function: `_can_merge_tick`
- Why: `_can_merge_tick` only checked the lower bound. Any client can send
  an input packet (netfox's `any_peer` command RPC) stamped with a tick
  ahead of the host's. Merging it moves the shared history buffer's head
  forward. The buffer holds only `history_limit` ticks (64 by default), so a
  snapshot at `current tick + 100000`, or even exactly `history_limit` ahead,
  pushes the old edge past the host's current tick, the host's own record for
  that tick is dropped, and no bot is simulated.
- Bound: `NetworkTime.max_ticks_per_frame` (netfox's own project setting
  `netfox/time/max_ticks_per_frame`, default 8), measured ahead of
  `NetworkTime.tick`. No new number.
- Cost: under attack the rollback window for honest late inputs shrinks by at
  most that many ticks, because accepted snapshots up to that far ahead still
  move the buffer. Measured over three localhost smoke runs: honest inputs reach the host
  at most 1 tick behind its own tick, and honest state reaches the client at
  most 1 tick ahead of its own tick.
- Coverage: `_merge_rollback_input`, `_merge_rollback_state` and
  `_merge_synchronizer_state` all call `_can_merge_tick`, so full state,
  diff state, sync state and input snapshots share the guard.
- Test: `tests/test_input_flood.tscn` (one +100000 packet, then one empty
  snapshot per tick for 1.2 s at leads 1, the bound, bound + 1,
  `history_limit` - 1, `history_limit` and `history_limit` + 1).
- Note: a first version used `history_limit` as the bound and failed at a
  lead of exactly `history_limit` (bot frozen).

```diff
@@ -296,6 +296,16 @@
 	return has_updated
 
 func _can_merge_tick(tick: int, history: _PerObjectHistory) -> bool:
+	# PATCH (see addons/NETFOX_PATCHES.md): refuse ticks more than one tick-loop
+	# burst ahead of the current tick. The history buffers hold only
+	# history_limit ticks, so a snapshot stamped further ahead pushes the
+	# buffer's old edge past the current tick and discards what this peer just
+	# recorded. A lead of up to max_ticks_per_frame is accepted, so under attack
+	# the rollback window shrinks by at most that many ticks.
+	if tick > NetworkTime.tick + NetworkTime.max_ticks_per_frame:
+		_logger.trace("Dropping snapshot @%d from too far in the future", [tick])
+		return false
+
 	if tick >= NetworkRollback.history_start:
 		return true
 
```

## 2. Only the server may set or answer the clock

- File: `addons/netfox/network-time-synchronizer.gd`
- Functions: `_handle_set_timestamp` and `_handle_pong`
- Why: both handlers are registered as commands on netfox's `any_peer`
  transport and never checked who sent them. Any peer could call
  `_handle_set_timestamp(2, var_to_bytes(100000.0))` on a running host and
  move its reference clock to 100002 s, after which the host ran about 25
  percent fast (75 ticks in 2 s instead of 60) and kept doing so.
- Checked first: in the synchroniser, clients send the timestamp request and
  the ping to peer 1; the server replies with `set_timestamp` and `pong`
  to the sender. So these two handlers only legitimately run on a client, with
  sender 1. The host never receives either from a client (its own sync loop
  stops at once on a server). `_handle_ping` and `_handle_request_timestamp`
  are the ones a server legitimately receives from clients; they are untouched.
- Test: `tests/test_clock_hijack.tscn` hosts, calls the handlers with sender 2
  and checks the clock and tick rate stay normal, now and a second later.

```diff
@@ -117,6 +117,8 @@
 var _rtt: float = 0.
 var _rtt_jitter: float = 0.
 
+const SERVER_PEER_ID: int = 1
+
 @onready var _cmd_ping := NetworkCommandServer.register_command(_handle_ping, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE)
 @onready var _cmd_pong := NetworkCommandServer.register_command(_handle_pong, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE)
 @onready var _cmd_req_time := NetworkCommandServer.register_command(_handle_request_timestamp, MultiplayerPeer.TRANSFER_MODE_RELIABLE)
@@ -255,6 +257,10 @@
 	_cmd_pong.send(var_to_bytes([idx, ping_received, _clock.get_time()]), sender)
 
 func _handle_pong(sender: int, data: PackedByteArray) -> void:
+	# PATCH (see addons/NETFOX_PATCHES.md): only the server answers pings.
+	if sender != SERVER_PEER_ID:
+		return
+
 	var args := bytes_to_var(data)
 
 	var idx := args[0] as int
@@ -296,6 +302,11 @@
 	_cmd_set_time.send(var_to_bytes(_clock.get_time()), sender)
 
 func _handle_set_timestamp(sender: int, data: PackedByteArray) -> void:
+	# PATCH (see addons/NETFOX_PATCHES.md): only the server may set our clock.
+	# Without this, any peer could set the host's reference clock.
+	if sender != SERVER_PEER_ID:
+		return
+
 	var timestamp := bytes_to_var(data) as float
 
 	_logger.debug("Received initial timestamp @ %.4fs raw time", [_clock.get_raw_time()])
```
