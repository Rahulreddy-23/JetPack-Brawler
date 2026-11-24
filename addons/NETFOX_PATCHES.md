# Patches to the bundled netfox addon

Netfox version: v1.49.12 (addons/netfox and addons/netfox.internals).

The diffs are in the last section, "The diffs", one block per file, against the
unpatched v1.49.12 source, with git headers. All the blocks together are the whole
set: extract them and run `git apply` from the directory that holds `addons/` on a
clean v1.49.12 tree (checked: applying the blocks to a copy of the unpatched addon
reproduces `addons/netfox` here exactly). Several patches change the same file, so each block says which
patches it carries. Re-apply the set after updating the addon, then run
`PORT_BASE=<free range> bash tests/run_all.sh`. Each patch names the test that fails
without it; the mutation table lists what was seen when each was removed in turn.

Tests named below (the `run_all.sh` name in brackets):

- `tests/test_input_flood.tscn` [input_flood]: in-process host; hands the real handlers packets stamped at, past and far past the bound and reads the history buffers.
- `tests/test_clock_hijack.tscn` [clock_hijack]: forged clock messages sent to a host and to a client.
- `tests/test_netfox_handlers.tscn --mode=host` [netfox_host] and `--mode=client` [netfox_client]: call the five synchronisation handlers, the ping handler and the identity table with chosen senders, ticks and bytes. Helper: `tests/netfox_probe.gd`.
- `tests/test_netfox_diffs.tscn` [netfox_diffs]: a client feeds diffs to the real handlers and reads what it stores; also the public authoritative-state query.
- `tests/test_full_state_coverage.tscn` [full_state_coverage]: a host runs the real `_synchronize_state` for three subjects and reads which get full states and what the diffs carry.
- `tests/test_slow_frames.tscn` [slow_frames]: in-process host with 100 ms frames; every tick must be simulated.
- `tests/net_hitch.sh` [host_hitch]: two processes; the host stalls its main thread for 400, 700 and 950 ms while an autopilot client plays, and must store and simulate every input tick the client sent.
- `tests/net_diffs.sh` [host_diffs]: two processes, diff states on in the host; the client's bot and the host's own must each get a full state at least every `full_state_interval` ticks.
- `tests/net_smoke.sh` [net_smoke]: two-process honest session; also fails if a packet was dropped for size.

## 1. A server refuses snapshots stamped too far ahead of its clock

- File: `addons/netfox/servers/network-history-server.gd`
- Function: `_can_merge_tick`
- Why (the bound): `_can_merge_tick` only checked the lower bound. Any client can
  send an input packet (netfox's `any_peer` command RPC) stamped with a tick ahead
  of the host's. Merging it moves the shared history buffer's head forward. The
  buffer holds only `history_limit` ticks (64 by default), so a snapshot at
  `current tick + 100000`, or at `current tick + history_limit`, pushes the old edge
  past the host's current tick, the host's own record for that tick is dropped, and
  no bot is simulated.
- Why (measured from the clock): the first version of this patch measured the bound
  from `NetworkTime.tick`. Commands arrive in the multiplayer poll, before
  `NetworkTime` runs its tick loop, so after a main-thread hitch shorter than the
  stall threshold `NetworkTime.tick` lags the real time by the length of the hitch
  while honest inputs are stamped with the real time. A two-process probe lost 1
  client input tick after a 400 ms host hitch, 11 after 700 ms and 21 after 950 ms
  (this suite's `host_hitch`, run against that version); the unpatched addon lost
  none. The bound is now measured from the reference clock: the tick
  `NetworkTime.seconds_to_ticks(NetworkTimeSynchronizer.get_time())` (netfox's own
  conversion, and the clock keeps running through a hitch), never less than
  `NetworkTime.tick`, plus `NetworkTime.max_ticks_per_frame` plus
  `NetworkRollback.input_delay` (netfox records and sends input at
  `tick + input_delay`; the setting is 0 in this project, so that term is not
  exercised by a test).
- Bound: `max(NetworkTime.tick, reference tick) + max_ticks_per_frame +
  input_delay`, cut at `NetworkTime.tick + size - 1`, where `size` is the history
  size of the buffers the call guards: `history_limit` for input and rollback state,
  the state synchronizer's own `history_limit` setting for synchronized state. The
  cut is what keeps the freeze from returning: a buffer's old edge passes the
  current tick only for a snapshot `size` or more ticks ahead of it. Without the cut,
  the accepted lead is `(reference tick - NetworkTime.tick) + 8`. Below the stall
  threshold (1 s; `NetworkTime._loop` resets the tick to the reference above it)
  that lag is at most 30 ticks at 30 ticks per second, so the lead is at most 38
  (+1 for rounding), under 64 even without the cut. The cut also covers several
  hitches in a row, which each stay under the threshold, and tick rates above
  about 54.
- No new tuning number: every term is a netfox setting.
- Honest play: the bound is never lower than the previous patch's
  (`NetworkTime.tick + max_ticks_per_frame`), so everything that patch accepted is
  still accepted; hitches that used to lose inputs no longer do (the host_hitch
  test reports 0 lost at 400, 700 and 950 ms).
- Cost under attack: a flood stamped at the accepted lead L over `NetworkTime.tick`
  leaves the newest merged tick L ahead, so honest late snapshots must be no older
  than `history_limit - 1 - L` ticks behind the current tick. The flood sweep in
  `input_flood` measures a lead of 8 leaving 55 of 64 ticks of rollback window, a
  loss of L + 1 ticks (9), not "at most L". During a hitch of `h` ticks the same
  flood can reach lead `h + 8`, at most 63, so the window can shrink to 1 tick for
  the length of the hitch; the simulation still runs.
- Coverage: `_merge_rollback_input`, `_merge_rollback_state` and
  `_merge_synchronizer_state` all call `_can_merge_tick`; `input_flood` checks all
  three paths, through the real handlers (`_handle_input`, `_handle_full_state`,
  `_handle_full_sync`).
- Clients: the bound applies on a server only (`multiplayer.is_server()`), see
  patch 3. A client's tick can legitimately trail the server's (a late initial
  timestamp, its own hitch, a clock panic) and it takes snapshots from the server
  only. The distinction is made inside `_can_merge_tick` rather than in the five
  handlers because every merge path already goes through it, and the handler check
  in patch 3 guarantees that on a client nothing but the server's data gets there.
- Test that fails without it: `input_flood` (the bound is refused one tick past and
  accepted at the bound, on all three paths; the cut is checked with the reference
  clock pushed 2 s ahead, for input and for sync state with a history size of 16)
  and `host_hitch` (zero lost input ticks at 400, 700, 950 ms).
- Note: a version that used `history_limit` as the bound failed at a lead of
  exactly `history_limit` (bot frozen).

## 2. Only the server may set or answer the clock

- File: `addons/netfox/network-time-synchronizer.gd`
- Functions: `_handle_set_timestamp` and `_handle_pong`
- Why: both handlers are registered as commands on netfox's `any_peer` transport and
  never checked who sent them. Any peer could call
  `_handle_set_timestamp(2, var_to_bytes(100000.0))` on a running host and move its
  reference clock to 100002 s, after which the host ran about 25 percent fast and
  kept doing so. On a client, a forged pong for a ping the client is waiting for is
  used as a time sample and can move the clock the same way.
- Checked first: in the synchroniser, clients send the timestamp request and the
  ping to peer 1; the server replies with `set_timestamp` and `pong` to the sender.
  So these two handlers only legitimately run on a client, with sender 1.
  `_handle_ping` and `_handle_request_timestamp` are what a server legitimately
  receives from clients and are not changed beyond patch 7. Time-sync direction
  logic and `_awaiting_samples` are untouched.
- Cost: none for an honest session.
- Test that fails without it: `clock_hijack`. The host case calls both handlers with
  sender 2 on a host; the client case makes the process a client with ping 0 in
  flight and checks that a forged set-timestamp and a forged pong for ping 0 from
  peer 2 change neither the clock nor the awaiting sample, while the server's pong
  for the same ping is used (the control).

## 3. A client takes snapshots from the server only

- File: `addons/netfox/servers/network-synchronization-server.gd`
- Functions: `_handle_input`, `_handle_full_state`, `_handle_diff_state`,
  `_handle_full_sync`, `_handle_diff_sync` (through the new `_is_acceptable`)
- Why: with the bound of patch 1 applied everywhere, a client whose tick lags (after
  its own hitch, a late initial timestamp, or a clock panic, for up to about 7
  seconds) dropped the host's own state. A client only ever legitimately receives
  snapshots from the server, so on a peer that is not the server anything whose
  sender is not peer 1 is dropped, and snapshots from peer 1 are not bounded (patch
  1 applies the bound on servers only).
- Cost: none for an honest session. Messages relayed between clients are dropped on
  a client; that is out of scope here (the game does not use relay).
- Test that fails without it: `netfox_client`. The process is a client with its tick
  at 0. All five handlers must drop a packet from sender 2 even though sender 2 owns
  the subject (so only the sender check can stop it), and must merge the server's
  packets stamped 3, 30 and 100 ticks ahead (100 is past `history_limit`, so only
  removing the server-only bound lets it through).

## 4. Empty snapshots are not merged, and sanitising clears the auth marks

- Files: `addons/netfox/servers/data/snapshot.gd` (`sanitize`) and
  `addons/netfox/servers/network-synchronization-server.gd` (the handlers and
  `_ingest_state`)
- Why: `sanitize(sender)` removes the subjects the sender does not own, but the
  handlers merged the now-empty snapshot into the shared buffers, which moves the
  buffers' head and is how a client could move the host's buffers at all. `sanitize`
  also left `_auth_subjects` set for the removed subjects. Honest senders never send
  empty snapshots, so an empty one is dropped before any merge.
- Not changed: a frame for a subject the sender does not own whose body is empty
  sets an auth mark but no data, and `sanitize` only looks at data. Such a mark is
  harmless after the empty check unless the same packet also carries a valid subject.
- Cost: none for an honest session.
- Test that fails without it: `netfox_host`: after `sanitize` the subject and its
  auth mark are gone, and each of the five handlers leaves the buffers untouched
  for a packet whose only subject belongs to another peer (control: the same packet
  from the owner is merged).

## 5. Bounds on the changed-bits field of a diff packet

- Files: `addons/netfox/serializers/sparse-snapshot-serializer.gd` (`read_from`) and
  `addons/netfox/schemas/network-schemas.gd` (`_varbits`, the variable bitset decode)
- Why: a changed-bits index at or beyond the node's property count indexed out of
  range (`Out of bounds get index`), aborting the handler with a script error. The
  variable bitset decode had no cap on continuation bytes: decoding took 707 ms for
  100 KB and 13.8 s for 2 MB, and one 300 KB packet over ENet froze the host for
  2.26 s.
- Bound, derived rather than chosen: an honest sender writes one bit per property of
  the node, 7 bits per byte, so the decode reads at most `ceil(property count / 7)`
  bytes (`decode_limited(buffer, node_props.size())`), stops when no bytes remain and
  gives up (returns null) when the continuation bit is still set at the cap. The
  index check rejects any set bit at or past the property count. In both cases the
  rest of the packet is skipped, like an unknown identity already was. The identity
  is resolved before the bits are read so the property count is known; that only
  moves a lookup that already happened later in the same loop. `decode()` keeps its
  signature and is limited by the bytes available.
- Cost: none for an honest session.
- Test that fails without it: `netfox_host`: a diff naming property 2..6 of a
  2-property node reads as an empty snapshot and merges nothing (without the patch
  also a SCRIPT ERROR, which fails `run_all.sh`); a packet whose bit field is a
  1,000,000 byte run of 0xFF is read in under 50 ms.

## 6. Bounds on how much work one input or state packet can cause

- Files: `addons/netfox/serializers/redundant-snapshot-serializer.gd` (`read_from`,
  new `max_snapshots`) and `addons/netfox/servers/network-synchronization-server.gd`
  (`_is_acceptable`, the size check)
- Why: `read_from` looped while bytes remained with no minimum snapshot size: a
  zero-filled input packet cost 214 ms at 16 KB and 837 ms at 64 KB. Both caps are
  needed; either alone still leaves a cheap attack (the count cap does not help
  state and diff packets, the size cap alone still allows a packet of many tiny
  snapshots up to the size limit).
- Caps: the serializer stops when a snapshot's declared size is zero or exceeds the
  bytes left, and after `NetworkRollback.input_redundancy` snapshots (what an honest
  sender packs). The handlers drop a packet larger than
  `max_sync_packet_size x 2 x snapshots per packet` (3 for input, the redundancy
  setting; 1 otherwise): netfox cuts packets to `max_sync_packet_size`
  (`netfox/general/max_sync_packet_size`, 508 here), so twice that per snapshot is
  headroom for the size prefix and for a single frame a little over the limit. The
  factor 2 is the only number added (`_PACKET_SIZE_HEADROOM`). A `max_sync_packet_size`
  of zero or less means no limit, as in `PacketBuffer`, and then no cap applies. A
  dropped packet is logged as a warning ("Dropping N byte packet ...") so a future
  large honest property is not lost silently; this warning is not rate limited, so a
  flooding peer can fill the log with it.
- Cost: none for an honest session; `net_smoke` fails if it sees the warning.
- Test that fails without it: `netfox_host`: a zero-filled 64 KB redundant packet is
  read in under 50 ms into no snapshots; a snapshot size past the end of the packet,
  and a size of zero, end the packet; 50 tiny snapshots yield as many as the
  redundancy setting; zero-filled 64 KB input, state and sync-diff packets are
  handled in under 50 ms; an input packet whose first snapshot is valid but which is
  padded past the limit is dropped whole (and merged without the padding); with
  `max_sync_packet_size` at 0 nothing is dropped for size.

## 7. A ping with a malformed payload is ignored

- File: `addons/netfox/network-time-synchronizer.gd`
- Function: `_handle_ping`
- Why: a malformed payload caused a decode error and an invalid cast
  (`Invalid cast: could not convert value to 'int'`). Only a type check on the
  decoded value is added; the engine still prints its own decode error for bytes that
  are not a Variant.
- Cost: none.
- Test that fails without it: `netfox_host` and `netfox_client` call the handler with
  garbage, a string, a Vector2 and an empty payload; without the patch each prints a
  SCRIPT ERROR, which fails `run_all.sh` (the scene itself still exits 0).

## 8. A conflicting second id for the same peer is ignored

- File: `addons/netfox/servers/data/network-identifier.gd`
- Function: `set_id_for`
- Why: a client sending two different ids for the same node tripped an `assert`.
- Cost: none.
- Test that fails without it: `netfox_host` and `netfox_client` register id 5 and
  then id 6 for one peer and check 5 is kept; without the patch the assert prints a
  SCRIPT ERROR, which fails `run_all.sh`.

## 9. The rollback loop simulates every tick of a tick loop

- File: `addons/netfox/rollback/network-rollback.gd`
- Function: `_rollback`
- Why: `_rollback()` started its range from `NetworkTime.tick`, which the tick loop has
  already advanced past every tick it ran, and then capped it at `tick - 1`. When a
  frame ran k ticks and no input or state at or below the current tick arrived, only
  the last tick was simulated and the other k - 1 never were. On a host with no client
  and 100 ms frames 43 of 63 ticks were never simulated and the bot moved 243 px
  instead of 429 px; after the 400, 700 and 950 ms hitches of `host_hitch` the host
  stored every client input and still never simulated 3, 12 and 23 of them. It affects
  any phone below 30 frames per second. The range now starts at the tick the loop
  started at, recorded on `NetworkTime.before_tick_loop`.
- Cost: none when a loop runs one tick (the normal case): the start is then
  `tick - 1` as before. Measured in a smoke run, rollback ticks simulated per loop on
  the host 1.7 to 2.1 before and after, and on the client 1.000 before and after;
  ticks run per loop were 1.0 on both. With slow frames a loop now simulates all the
  ticks it ran, which is the point.
- Test that fails without it: `slow_frames` (0 of the window's ticks never simulated,
  and the distance moved matches that of normal frames) and `host_hitch` (every stored
  client input tick was also simulated).

## 10. A diff is laid over the last authoritative state, not over the client's guess

- Files: `addons/netfox/servers/network-history-server.gd` (`_complete_diff`, called
  by `_merge_rollback_state` and `_merge_synchronizer_state`),
  `addons/netfox/servers/data/per-object-history.gd` (`get_latest_auth_snapshot_before`)
  and, on the sending side, `addons/netfox/servers/network-synchronization-server.gd`
  (`_get_last_sent_rollback_state`, `_remember_sent_rollback_state`)
- Why: a diff carries only the properties that changed since what the host last sent.
  The client laid it over its own non-authoritative snapshot for that tick (in the
  per-object history, in the per-tick snapshot, and through the carry-forward when it
  had no snapshot for the tick) and marked the result authoritative. Reproduced as a
  client: host full state at T-1 is a=1, b=1; the client's guess at T is a=99, b=99;
  the host's diff at T carries a=2 only; the client stored authoritative a=2, b=99
  where the host has b=1. The per-tick snapshot, with nothing at the tick, stored the
  diff alone.
- Receiver: before merging a diff (`_merge_rollback_state` and `_merge_synchronizer_state`
  take an `is_diff` flag, set by `_handle_diff_state` and `_handle_diff_sync` only; a
  full state is whole already and pays nothing), `_complete_diff` adds to the incoming authoritative
  snapshot, for each subject that has no authoritative snapshot at that tick yet, the
  properties of the latest authoritative snapshot before the tick that the diff does
  not carry. Everything downstream (the per-object history, the per-tick snapshot, the
  carry-forward) then sees a whole state. A subject that already has an authoritative
  snapshot at the tick (an earlier diff or a full state for the same tick) is laid on
  as before.
- Sender: the host's record of what it sent carried the whole previous record forward
  into every tick it sent anything for. After a re-simulation of an earlier tick that
  carry is stale, so a diff computed against it did not match what the client holds,
  which is the latest authoritative state. The host now records, per tick, the full
  values of the subjects it actually sent for that tick and nothing else, and finds the
  reference per subject: the latest record at or before the tick that holds that
  subject. This is the same rule the client applies. With diff states off nothing is
  recorded.
- Cost: bandwidth is unchanged by the receiver part, and a full state is merged exactly
  as before (the walk back through earlier ticks is for diffs only). The sender part The sender part records less
  than before (only what was sent).
- What remains incorrect under packet loss: diff packets travel unreliably. If one is
  lost, the client's authoritative state for the properties it carried stays wrong,
  and every later diff is laid over that wrong state, until the next full state for
  the subject, which is at most `full_state_interval` ticks (24, 0.8 s) later (patch
  11). The client's own bot is then re-simulated from a wrong authoritative state
  during that time. The same happens when diffs arrive out of order. The previous
  merge onto the client's guess hid this whenever the client predicted the property
  correctly, which it does for deterministic movement; so with diff states on and
  loopback ENet dropping packets under load, the smoke test showed position mismatches
  in about 3 runs in 14 that the old merge did not (diff packets for ticks 124, 125
  and 128 were sent by the host and never reached the client in one captured run).
  A diff that names the tick it is relative to would let a client that lacks that
  state fall back to its guess instead; that needs a change to the packet format and
  was not done. The project keeps `enable_diff_states` off. Note for that work:
  `tests/test_netfox_diffs.gd` currently asserts the known wrong behaviour after a lost
  diff (the client's b stays at the stale value until the next full state) and must be
  inverted when diffs carry a reference.
- Test that fails without it: `netfox_diffs` (the deterministic case above, in the
  per-object history and the per-tick snapshot, with a guess at the tick and with the
  carry-forward from a guess at the tick before; a second diff for the same tick; and
  the same for sync state) and `full_state_coverage` (after a re-simulation the diff
  for a subject carries every property that differs from what was last sent for it,
  not from a stale carry), and `netfox_diffs` (a merge not marked as a diff is not
  completed; the same merge marked as a diff is). Also `netfox_diffs`: after a lost diff the client's value
  is still wrong, and is right again at the full state one interval later.

## 11. Every subject gets a full state at least once per interval

- File: `addons/netfox/servers/network-synchronization-server.gd`
  (`_synchronize_state`, new `_pick_full_state_subjects`, `_rb_last_full_tick`)
- Why: the full-state schedule counted calls to `_synchronize_state`, which come once
  or more per tick (a re-simulation sends the tick again) and which, for a subject
  whose input has not arrived yet, usually do not contain it on the first pass of a
  tick. A call that was due often fell on a first pass, so such subjects were rarely
  sent in full (18 of 838 sends for a client bot against 122 of 2936 for the host's in
  the reviewer's experiment). Full or diff is now decided per subject and peer: a
  subject is sent in full when it has never been sent to the peer, when it is not in
  the reference, or when `full_state_interval` ticks (not calls) have passed since its
  last full state; otherwise as a diff. With diff states off every subject is sent in
  full as before; an interval of 0 or less means no periodic full state, as before.
- Cost: with diff states on the number of full states per subject is one per interval
  instead of about one per 12 ticks, so bandwidth falls a little.
- Test that fails without it: `full_state_coverage` (three subjects, one present only
  in the second pass of each tick, one appearing mid-run: every one gets a full state
  within the interval, and diffs are still sent between them; with the old schedule
  the late-input subject got none) and `host_diffs` (the same on the real game, for
  the host's bot and the client's).

## 12. Bounds on frames of unknown identity, and rate-limited warnings

- Files: `addons/netfox/serializers/dense-snapshot-serializer.gd` (`read_from`),
  `addons/netfox/serializers/base-snapshot-serializer.gd` (`_warn_peer`) and
  `addons/netfox/serializers/sparse-snapshot-serializer.gd`
- Why: zero bytes decode as an unknown identity in about 3 bytes each, and each
  printed a warning with a backtrace: a 1016-byte zero-filled full-state packet cost
  35 ms unloaded and 82 ms under load, a 3030-byte input packet 63 ms and 334 ms, so
  20 to 30 such packets a second froze the host. A packet is now cut after as many
  unknown-identity frames as the receiver has registered subjects in that pool (an
  honest packet has one frame per subject), and the warnings about what a peer sent
  (unknown identity, malformed changed-bits field, changed-bits index past the
  property count) are logged at most once per second per peer.
- Cost: none for an honest session whose receiver has registered every subject the
  sender sends. A packet with more unknown frames than the receiver has subjects is read
  only up to the cap, and the frames after it, known ones included, are dropped. The
  next tick's packet is cut the same way for as long as the condition holds: a game that
  registers subjects lazily, and a client that has not yet spawned several of the other
  bots, can lose the frames behind the cap tick after tick until enough subjects are
  registered. Not measured on a joining client.
- Test that fails without it: `netfox_host`: a packet with as many unknown frames as
  there are subjects still has its valid frame read, and one with more unknown frames
  is dropped from there on; three zero-filled 1016 byte state packets and two 3048
  byte input packets are handled in under 50 ms and produce at most one
  unknown-identity warning (counted with an engine logger).
- Not done: the warning of patch 6 about a packet over the size limit is not rate
  limited.

## 13. A public query for state received from the authority

- File: `addons/netfox/servers/network-history-server.gd`
- Function: new `has_authoritative_state(subject: Object) -> bool`
- Why: on a client there was no public way to tell state received from the host from
  state the client predicted. The public queries (`get_state_age_for` and the like)
  count predictions, and the authoritative flag is only reachable through the private
  `_rb_state_history`. The query is true once any rollback or synchronized state
  received from the subject's authority has been merged for it in this session, and
  always true on the peer that is the authority (`is_multiplayer_authority()`). It is
  recorded in `_merge_rollback_state` and `_merge_synchronizer_state`, which only
  received snapshots go through, cleared by `reset()` (called by `NetworkTime.stop()`)
  and per node by `deregister()`.
- Cost: one set insert per authoritative subject per merged snapshot.
- Test that fails without it: `netfox_diffs` (client: false with only local
  predictions, true after the first received state, false after `NetworkTime.stop()`,
  true again after the first state of the next session) and `netfox_host` (true at once
  for a subject the host owns). The restart is a stop followed by a new state; the test
  client is never connected, so `NetworkTime.start()` is not run.

## The diffs

The blocks below are the whole set, one per file.

`addons/netfox/network-time-synchronizer.gd`, carries patches 2 and 7:

```diff
diff --git a/addons/netfox/network-time-synchronizer.gd b/addons/netfox/network-time-synchronizer.gd
--- a/addons/netfox/network-time-synchronizer.gd
+++ b/addons/netfox/network-time-synchronizer.gd
@@ -117,6 +117,8 @@
 var _rtt: float = 0.
 var _rtt_jitter: float = 0.
 
+const SERVER_PEER_ID: int = 1
+
 @onready var _cmd_ping := NetworkCommandServer.register_command(_handle_ping, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE)
 @onready var _cmd_pong := NetworkCommandServer.register_command(_handle_pong, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE)
 @onready var _cmd_req_time := NetworkCommandServer.register_command(_handle_request_timestamp, MultiplayerPeer.TRANSFER_MODE_RELIABLE)
@@ -249,12 +251,21 @@
 		_offset = offset - nudge
 
 func _handle_ping(sender: int, data: PackedByteArray) -> void:
-	var idx := bytes_to_var(data) as int
+	# PATCH (see addons/NETFOX_PATCHES.md): a malformed payload is not an index.
+	var decoded: Variant = bytes_to_var(data)
+	if typeof(decoded) != TYPE_INT:
+		return
+
+	var idx := decoded as int
 	var ping_received := _clock.get_time()
 
 	_cmd_pong.send(var_to_bytes([idx, ping_received, _clock.get_time()]), sender)
 
 func _handle_pong(sender: int, data: PackedByteArray) -> void:
+	# PATCH (see addons/NETFOX_PATCHES.md): only the server answers pings.
+	if sender != SERVER_PEER_ID:
+		return
+
 	var args := bytes_to_var(data)
 
 	var idx := args[0] as int
@@ -296,6 +307,11 @@
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

`addons/netfox/rollback/network-rollback.gd`, carries patch 9:

```diff
diff --git a/addons/netfox/rollback/network-rollback.gd b/addons/netfox/rollback/network-rollback.gd
--- a/addons/netfox/rollback/network-rollback.gd
+++ b/addons/netfox/rollback/network-rollback.gd
@@ -160,6 +160,9 @@
 var _tick: int = 0
 var _resim_from: int
 var _history_floor: int = 0
+
+# PATCH (see addons/NETFOX_PATCHES.md): the tick the latest tick loop started at
+var _loop_start_tick: int = 0
 
 var _rollback_from: int = -1
 var _rollback_to: int = -1
@@ -362,6 +365,7 @@
 func _ready() -> void:
 	NetfoxLogger.register_tag(_get_rollback_tag)
 
+	NetworkTime.before_tick_loop.connect(func() -> void: _loop_start_tick = NetworkTime.tick)
 	NetworkSynchronizationServer._on_input.connect(_handle_input)
 	NetworkSynchronizationServer._on_state.connect(_handle_state)
 
@@ -379,7 +383,10 @@
 		return
 
 	# Ask all rewindables to submit their earliest inputs
-	_resim_from = NetworkTime.tick
+	# PATCH (see addons/NETFOX_PATCHES.md): start from where the tick loop
+	# started. NetworkTime.tick is already past every tick the loop ran, so
+	# starting from it simulated only the last tick of a loop that ran several.
+	_resim_from = _loop_start_tick
 	before_loop.emit()
 
 	# Figure out where to start rollback from
```

`addons/netfox/schemas/network-schemas.gd`, carries patch 5:

```diff
diff --git a/addons/netfox/schemas/network-schemas.gd b/addons/netfox/schemas/network-schemas.gd
--- a/addons/netfox/schemas/network-schemas.gd
+++ b/addons/netfox/schemas/network-schemas.gd
@@ -75,7 +75,7 @@
 static func varuint() -> NetworkSchemaSerializer:
 	return _VaruintSerializer.instance
 
-static func _varbits() -> NetworkSchemaSerializer:
+static func _varbits() -> _VariableBitsetSerializer:
 	return _VariableBitsetSerializer.instance
 
 ## Serialize signed integers as 8 bits.
@@ -610,9 +610,19 @@
 			b.put_u8(byte)
 
 	func decode(b: StreamPeerBuffer) -> Variant:
+		return decode_limited(b, b.get_available_bytes() * 7)
+
+	# PATCH (see addons/NETFOX_PATCHES.md): read at most the bytes needed for
+	# max_bits bits and never past the end of the buffer. Returns null when the
+	# bitset is longer than that or the buffer ends first, so a run of
+	# continuation bytes cannot cost more than the caller allows.
+	func decode_limited(b: StreamPeerBuffer, max_bits: int) -> Variant:
 		var bools := []
 
-		while true:
+		for __ in (max_bits + 6) / 7:
+			if b.get_available_bytes() == 0:
+				return null
+
 			var byte := b.get_u8()
 
 			bools.append(byte & 0x01)
@@ -625,9 +635,9 @@
 
 			# Stop if no more data to read
 			if byte & 0x80 == 0:
-				break
+				return _Bitset.of_bools(bools)
 
-		return _Bitset.of_bools(bools)
+		return null
 
 class _Float16Serializer extends NetworkSchemaSerializer:
 	func encode(v: Variant, b: StreamPeerBuffer) -> void:
```

`addons/netfox/serializers/base-snapshot-serializer.gd`, carries patch 12:

```diff
diff --git a/addons/netfox/serializers/base-snapshot-serializer.gd b/addons/netfox/serializers/base-snapshot-serializer.gd
--- a/addons/netfox/serializers/base-snapshot-serializer.gd
+++ b/addons/netfox/serializers/base-snapshot-serializer.gd
@@ -6,6 +6,9 @@
 var _identity_server: _NetworkIdentityServer
 var _schemas: _NetworkSchema
 
+# PATCH (see addons/NETFOX_PATCHES.md): peer to the time (msec) of its last warning
+var _last_warning_msec := {}
+
 static var _default_filter := func(subject: Object): return true
 static var _logger := NetfoxLogger._for_netfox("DenseSnapshotSerializer")
 
@@ -37,3 +40,15 @@
 	if not _identity_server:
 		_identity_server = NetworkIdentityServer
 	return _identity_server
+
+# PATCH (see addons/NETFOX_PATCHES.md): a warning about something a peer sent is
+# logged at most once per second per peer, so a peer cannot fill the log, and
+# spend the host's time on printing, by sending the same bad packet over and over
+func _warn_peer(peer: int, text: String, values: Array = []) -> void:
+	var now := Time.get_ticks_msec()
+	if now - (_last_warning_msec.get(peer, -_WARNING_INTERVAL_MSEC) as int) < _WARNING_INTERVAL_MSEC:
+		return
+	_last_warning_msec[peer] = now
+	_logger.warning(text, values)
+
+const _WARNING_INTERVAL_MSEC := 1000
```

`addons/netfox/serializers/dense-snapshot-serializer.gd`, carries patch 12:

```diff
diff --git a/addons/netfox/serializers/dense-snapshot-serializer.gd b/addons/netfox/serializers/dense-snapshot-serializer.gd
--- a/addons/netfox/serializers/dense-snapshot-serializer.gd
+++ b/addons/netfox/serializers/dense-snapshot-serializer.gd
@@ -61,6 +61,11 @@
 	var tick := buffer.get_u32()
 	var snapshot := _Snapshot.new(tick)
 
+	# PATCH (see addons/NETFOX_PATCHES.md): an honest packet has a frame per
+	# subject, so a packet with more frames of unknown identity than there are
+	# subjects is not honest; drop the rest of it
+	var unknown_frames_left := properties.get_subjects_raw().size()
+
 	while buffer.get_available_bytes() > 0:
 		# Read identity reference, data size, and data
 		var idref := netref.decode(buffer) as _NetworkIdentityReference
@@ -71,7 +76,10 @@
 		var identifier := _get_identity_server()._resolve_reference(peer, idref)
 		if not identifier:
 			# TODO(#563): Handle unknown IDs gracefully
-			_logger.warning("Received unknown identity reference %s from #%s, skipping data", [idref, peer])
+			_warn_peer(peer, "Received unknown identity reference %s from #%s, skipping data", [idref, peer])
+			unknown_frames_left -= 1
+			if unknown_frames_left < 0:
+				break
 			continue
 		var node := identifier.get_subject() as Node
 		assert(is_instance_valid(node), "Where node?")
```

`addons/netfox/serializers/redundant-snapshot-serializer.gd`, carries patch 6:

```diff
diff --git a/addons/netfox/serializers/redundant-snapshot-serializer.gd b/addons/netfox/serializers/redundant-snapshot-serializer.gd
--- a/addons/netfox/serializers/redundant-snapshot-serializer.gd
+++ b/addons/netfox/serializers/redundant-snapshot-serializer.gd
@@ -3,6 +3,9 @@
 
 var _dense_serializer: _DenseSnapshotSerializer
 
+# PATCH (see addons/NETFOX_PATCHES.md): the most snapshots an honest packet carries.
+var max_snapshots := NetworkRollback.input_redundancy
+
 static func _static_init() -> void:
 	_logger = NetfoxLogger._for_netfox("RedundantSnapshotSerializer")
 
@@ -38,7 +41,12 @@
 
 	var snapshots := [] as Array[_Snapshot]
 	while buffer.get_available_bytes() > 0:
+		# PATCH (see addons/NETFOX_PATCHES.md): bound the work one packet can cause
+		if snapshots.size() >= max_snapshots:
+			break
 		var snapshot_size := varuint.decode(buffer)
+		if snapshot_size <= 0 or snapshot_size > buffer.get_available_bytes():
+			break
 		var snapshot_buffer := StreamPeerBuffer.new()
 		snapshot_buffer.data_array = buffer.get_partial_data(snapshot_size)[1]
 
```

`addons/netfox/serializers/sparse-snapshot-serializer.gd`, carries patches 5 and 12:

```diff
diff --git a/addons/netfox/serializers/sparse-snapshot-serializer.gd b/addons/netfox/serializers/sparse-snapshot-serializer.gd
--- a/addons/netfox/serializers/sparse-snapshot-serializer.gd
+++ b/addons/netfox/serializers/sparse-snapshot-serializer.gd
@@ -69,20 +69,30 @@
 		# Read header, including identity reference
 		var idref := netref.decode(buffer) as _NetworkIdentityReference
 		var node_data_size := varuint.decode(buffer) as int
-		var changed_bits := varbits.decode(buffer) as _Bitset
-		node_buffer.data_array = buffer.get_partial_data(node_data_size)[1]
 
 		# Resolve to identifier
 		var identifier := _get_identity_server()._resolve_reference(peer, idref)
 		if not identifier:
 			# TODO(#563): Handle unknown IDs gracefully
-			_logger.warning("Received unknown identity reference %s, skipping data", [idref])
+			_warn_peer(peer, "Received unknown identity reference %s from #%s, skipping data", [idref, peer])
 			break
 		var node := identifier.get_subject() as Node
+		var node_props := properties.get_properties_of(node)
 
+		# PATCH (see addons/NETFOX_PATCHES.md): an honest changed-bits field has
+		# one bit per property, and names no property the node does not have
+		var changed_bits := varbits.decode_limited(buffer, node_props.size()) as _Bitset
+		if changed_bits == null:
+			_warn_peer(peer, "Received malformed changed-bits field from #%s, skipping data", [peer])
+			break
+		var changed_indices := changed_bits.get_set_indices()
+		if not changed_indices.is_empty() and changed_indices.back() >= node_props.size():
+			_warn_peer(peer, "Received a changed-bits index past the property count from #%s, skipping data", [peer])
+			break
+		node_buffer.data_array = buffer.get_partial_data(node_data_size)[1]
+
 		# Read changed properties
-		var node_props := properties.get_properties_of(node)
-		for idx in changed_bits.get_set_indices():
+		for idx in changed_indices:
 			var property := node_props[idx]
 			var value := _read_property(node, property, node_buffer)
 			snapshot.set_property(node, property, value)
```

`addons/netfox/servers/data/network-identifier.gd`, carries patch 8:

```diff
diff --git a/addons/netfox/servers/data/network-identifier.gd b/addons/netfox/servers/data/network-identifier.gd
--- a/addons/netfox/servers/data/network-identifier.gd
+++ b/addons/netfox/servers/data/network-identifier.gd
@@ -20,7 +20,10 @@
 	return _ids.get(peer, -1)
 
 func set_id_for(peer: int, id: int) -> void:
-	assert(not _ids.has(peer) or _ids[peer] == id, "ID for peer #%d is already set!" % [peer])
+	# PATCH (see addons/NETFOX_PATCHES.md): a peer can send any id, so ignore a
+	# conflicting one instead of asserting.
+	if _ids.has(peer) and _ids[peer] != id:
+		return
 	_ids[peer] = id
 	on_id.emit(peer, id)
 
```

`addons/netfox/servers/data/per-object-history.gd`, carries patch 10:

```diff
diff --git a/addons/netfox/servers/data/per-object-history.gd b/addons/netfox/servers/data/per-object-history.gd
--- a/addons/netfox/servers/data/per-object-history.gd
+++ b/addons/netfox/servers/data/per-object-history.gd
@@ -54,6 +54,22 @@
 	# NOTE: May return null if tick too old
 	return history.get_at(tick) as _ObjectSnapshot
 
+# PATCH (see addons/NETFOX_PATCHES.md): the latest authoritative snapshot of
+# `subject` strictly before `tick`, skipping local predictions
+func get_latest_auth_snapshot_before(tick: int, subject: Object) -> _ObjectSnapshot:
+	if not _data.has(subject):
+		return null
+
+	var history := _data[subject] as _HistoryBuffer
+	var at := tick - 1
+	while history.has_latest_at(at):
+		var index := history.get_latest_index_at(at)
+		var snapshot := history.get_at(index) as _ObjectSnapshot
+		if snapshot != null and snapshot.is_auth():
+			return snapshot
+		at = index - 1
+	return null
+
 func restore_latest(tick: int) -> bool:
 	var any_applied := false
 	for subject in _subjects:
```

`addons/netfox/servers/data/snapshot.gd`, carries patch 4:

```diff
diff --git a/addons/netfox/servers/data/snapshot.gd b/addons/netfox/servers/data/snapshot.gd
--- a/addons/netfox/servers/data/snapshot.gd
+++ b/addons/netfox/servers/data/snapshot.gd
@@ -124,6 +124,7 @@
 
 	for subject in invalid_subjects:
 		_data.erase(subject)
+		_auth_subjects.erase(subject)
 
 func has_subject(subject: Object, require_auth: bool = false) -> bool:
 	if not _data.has(subject):
```

`addons/netfox/servers/network-history-server.gd`, carries patches 1, 3 (the server-only bound), 10 and 13:

```diff
diff --git a/addons/netfox/servers/network-history-server.gd b/addons/netfox/servers/network-history-server.gd
--- a/addons/netfox/servers/network-history-server.gd
+++ b/addons/netfox/servers/network-history-server.gd
@@ -21,6 +21,10 @@
 
 var _ignored_subjects := _Set.new()
 
+# PATCH (see addons/NETFOX_PATCHES.md): subjects that state from their authority
+# has been merged for in this session
+var _authoritative_subjects := _Set.new()
+
 # Source of truth for history
 var _rb_input_history := _PerObjectHistory.new(_rb_history_size)
 var _rb_state_history := _PerObjectHistory.new(_rb_history_size)
@@ -65,6 +69,8 @@
 	_rb_input_properties.erase_subject(node)
 	_sync_state_properties.erase_subject(node)
 
+	_authoritative_subjects.erase(node)
+
 	# Erase from per-object history
 	_rb_state_history.erase_subject(node)
 	_rb_input_history.erase_subject(node)
@@ -90,6 +96,7 @@
 	_sync_state_snapshots = _HistoryBuffer.new(_sync_history_size)
 
 	_ignored_subjects.clear()
+	_authoritative_subjects.clear()
 
 ## Do not record [param subject]
 ## [br][br]
@@ -135,6 +142,18 @@
 	else:
 		return tick - latest_input
 
+## Return true if [param subject] has state that came from its authority
+## [br][br]
+## On a peer that is not the authority, rollback and synchronized state of a
+## subject is predicted locally until the authority's state arrives. This is
+## true once any state received from the authority has been merged for
+## [param subject] in this session, and always true on the authority itself. It
+## is false again after [method _NetworkTime.stop], which calls [method reset].
+func has_authoritative_state(subject: Object) -> bool:
+	if subject is Node and (subject as Node).is_multiplayer_authority():
+		return true
+	return _authoritative_subjects.has(subject)
+
 ## Record currently registered rollback state properties for [param subject] at
 ## [param tick].
 func push_rollback_state(subject: Node, tick: int) -> void:
@@ -199,18 +218,48 @@
 	_merge_snapshot(snapshot, _rb_input_snapshots, true)
 	return _merge_history(snapshot, _rb_input_history, true)
 
-func _merge_rollback_state(snapshot: _Snapshot) -> bool:
+func _merge_rollback_state(snapshot: _Snapshot, is_diff: bool = false) -> bool:
 	if not _can_merge_tick(snapshot.tick, _rb_state_history):
 		return false
+	_mark_authoritative(snapshot)
+	if is_diff:
+		_complete_diff(snapshot, _rb_state_history)
 	_merge_snapshot(snapshot, _rb_state_snapshots)
 	return _merge_history(snapshot, _rb_state_history)
 
-func _merge_synchronizer_state(snapshot: _Snapshot) -> bool:
+func _merge_synchronizer_state(snapshot: _Snapshot, is_diff: bool = false) -> bool:
 	if not _can_merge_tick(snapshot.tick, _sync_history):
 		return false
+	_mark_authoritative(snapshot)
+	if is_diff:
+		_complete_diff(snapshot, _sync_history)
 	_merge_snapshot(snapshot, _sync_state_snapshots, true)
 	return _merge_history(snapshot, _sync_history)
 
+# PATCH (see addons/NETFOX_PATCHES.md): remember which subjects state came in for
+func _mark_authoritative(snapshot: _Snapshot) -> void:
+	for subject in snapshot.get_auth_subjects():
+		_authoritative_subjects.add(subject)
+
+# PATCH (see addons/NETFOX_PATCHES.md): a diff holds only what changed since the
+# last state the sender sent. Make it whole by adding the properties of the
+# latest authoritative snapshot before its tick, so merging it never lets this
+# peer's own prediction for the tick fill in the properties it left out. A
+# subject that already has an authoritative snapshot at the tick (an earlier
+# diff or a full state) is layered on as before.
+func _complete_diff(snapshot: _Snapshot, history: _PerObjectHistory) -> void:
+	for subject in snapshot.get_subjects():
+		if not snapshot.is_auth(subject) or history.is_auth(snapshot.tick, subject):
+			continue
+
+		var base := history.get_latest_auth_snapshot_before(snapshot.tick, subject)
+		if base == null:
+			continue
+
+		for property in base._data:
+			if not snapshot.has_property(subject, property):
+				snapshot.set_property(subject, property, base._data[property])
+
 func _record(tick: int, history: _PerObjectHistory, snapshots: _HistoryBuffer, property_pool: _PropertyPool, only_auth: bool, auth_filter: Callable) -> void:
 	var snapshot := snapshots.get_at(tick, _Snapshot.new(tick)) as _Snapshot
 	if not snapshots.has_at(tick):
@@ -296,6 +345,26 @@
 	return has_updated
 
 func _can_merge_tick(tick: int, history: _PerObjectHistory) -> bool:
+	# PATCH (see addons/NETFOX_PATCHES.md): a server refuses ticks that are too
+	# far ahead of its own clock. The history buffers hold only history_limit
+	# ticks, so a snapshot stamped further ahead pushes the buffer's old edge
+	# past the current tick and discards what this peer just recorded. Commands
+	# arrive before NetworkTime runs its loop, and after a short main-thread
+	# hitch NetworkTime.tick lags the clock; honest inputs are stamped with the
+	# real time. So the bound is measured from the clock (never from less than
+	# NetworkTime.tick) and never reaches the history size of the buffers it
+	# guards (history_limit, or the state synchronizer's own) ticks past
+	# NetworkTime.tick. Clients only take the server's snapshots, which they
+	# trust (see the synchronization server).
+	if multiplayer.is_server():
+		var reference_tick := maxi(NetworkTime.tick, NetworkTime.seconds_to_ticks(NetworkTimeSynchronizer.get_time()))
+		var latest_tick := reference_tick + NetworkTime.max_ticks_per_frame + NetworkRollback.input_delay
+		var history_size := _sync_history_size if history == _sync_history else _rb_history_size
+		latest_tick = mini(latest_tick, NetworkTime.tick + history_size - 1)
+		if tick > latest_tick:
+			_logger.trace("Dropping snapshot @%d from too far in the future", [tick])
+			return false
+
 	if tick >= NetworkRollback.history_start:
 		return true
 
```

`addons/netfox/servers/network-synchronization-server.gd`, carries patches 3, 4, 6, 10 and 11:

```diff
diff --git a/addons/netfox/servers/network-synchronization-server.gd b/addons/netfox/servers/network-synchronization-server.gd
--- a/addons/netfox/servers/network-synchronization-server.gd
+++ b/addons/netfox/servers/network-synchronization-server.gd
@@ -40,6 +40,7 @@
 var _input_redundancy := NetworkRollback.input_redundancy
 
 var _rb_sent_state_history := {} # peer to _HistoryBuffer of _Snapshot
+var _rb_last_full_tick := {} # PATCH: peer to (subject to tick of the last full state sent)
 
 var _last_sync_state_sent := _Snapshot.new(0)
 var _sync_enable_diffs := ProjectSettings.get_setting("netfox/state_synchronizer/enable_diff_states", true) as bool
@@ -132,6 +133,9 @@
 
 ## Deregister any and all settings associated with [param node]
 func deregister(node: Node) -> void:
+	for subjects: Dictionary in _rb_last_full_tick.values():
+		subjects.erase(node)
+
 	_rb_state_properties.erase_subject(node)
 	_rb_input_properties.erase_subject(node)
 	_rb_owned_state_properties.erase_subject(node)
@@ -149,6 +153,7 @@
 ## Called by default when a peer leaves
 func erase_peer(peer: int) -> void:
 	_rb_sent_state_history.erase(peer)
+	_rb_last_full_tick.erase(peer)
 
 ## Forget what was sent to other peers, while keeping the registered properties
 ## [br][br]
@@ -157,6 +162,7 @@
 ## [method _NetworkTime.stop].
 func reset() -> void:
 	_rb_sent_state_history.clear()
+	_rb_last_full_tick.clear()
 	_last_sync_state_sent = _Snapshot.new(0)
 
 func _get_peer_rb_sent_history(peer: int) -> _HistoryBuffer:
@@ -164,25 +170,42 @@
 		_rb_sent_state_history[peer] = _HistoryBuffer.new(NetworkRollback.history_limit)
 	return _rb_sent_state_history[peer]
 
-func _get_last_sent_rollback_state(peer: int, tick: int) -> _Snapshot:
+# PATCH (see addons/NETFOX_PATCHES.md): what a diff is relative to, per subject.
+# The latest full values sent to `peer` for each of `subjects` at or before `tick`,
+# as a snapshot; a subject that was never sent is absent. This is what a client
+# that lays diffs over its latest authoritative state holds.
+func _get_last_sent_rollback_state(peer: int, subjects: Array, tick: int) -> _Snapshot:
+	var result := _Snapshot.new(tick)
 	var history: _HistoryBuffer = _rb_sent_state_history.get(peer, null)
-	if history == null or not history.has_latest_at(tick):
-		return null
-	return history.get_latest_at(tick)
+	if history == null:
+		return result
 
-func _remember_sent_rollback_state(peer: int, snapshot: _Snapshot) -> void:
-	var reference := _get_last_sent_rollback_state(peer, snapshot.tick)
-	var remembered := reference.duplicate() if reference else _Snapshot.new(snapshot.tick)
+	for subject in subjects:
+		var at := tick
+		while history.has_latest_at(at):
+			var index := history.get_latest_index_at(at)
+			var sent := history.get_at(index) as _Snapshot
+			if sent != null and sent.has_subject(subject):
+				sent.copy_subject_to(subject, result)
+				result.set_auth(subject, true)
+				break
+			at = index - 1
+	return result
 
-	# `snapshot` might be a diff state, hence the merging
-	for subject in snapshot.get_subjects():
-		for property in snapshot.get_subject_properties(subject):
-			remembered.set_property(subject, property, snapshot.get_property(subject, property))
-		remembered.set_auth(subject, snapshot.is_auth(subject))
-	remembered.tick = snapshot.tick
+# PATCH (see addons/NETFOX_PATCHES.md): remember the full values of the `subjects`
+# that were sent for the tick of `snapshot`, and only those. A subject that was not
+# sent for a tick has no entry there, so what a later diff is relative to stays the
+# latest thing that was sent, however that tick is re-simulated afterwards.
+func _remember_sent_rollback_state(peer: int, snapshot: _Snapshot, subjects: Array) -> void:
+	var history := _get_peer_rb_sent_history(peer)
+	var remembered := history.get_at(snapshot.tick, _Snapshot.new(snapshot.tick)) as _Snapshot
 
-	_get_peer_rb_sent_history(peer).set_at(snapshot.tick, remembered)
+	for subject in subjects:
+		snapshot.copy_subject_to(subject, remembered)
+		remembered.set_auth(subject, snapshot.is_auth(subject))
 
+	history.set_at(snapshot.tick, remembered)
+
 # Prepare snapshot to be sent to `peer`
 # Only contains visible subjects' auth properties
 func _make_peer_snapshot(snapshot: _Snapshot, peer: int, properties: _PropertyPool) -> _Snapshot:
@@ -269,43 +292,68 @@
 		# Nothing to send
 		return
 
-	# Figure out whether to send full- or diff state
-	var is_full := _rb_full_scheduler.is_now()
-	if not _rb_enable_diffs:
-		is_full = true
-
 	for peer in multiplayer.get_peers():
 		var peer_snapshot := _make_peer_snapshot(snapshot, peer, _rb_owned_state_properties)
 		if peer_snapshot.is_empty():
 			continue
 
-		var peer_is_full := is_full
-		var reference_snapshot := _get_last_sent_rollback_state(peer, tick)
-		if reference_snapshot == null:
-			peer_is_full = true
+		# PATCH (see addons/NETFOX_PATCHES.md): full or diff state is decided per
+		# subject, so every subject gets a full state at least once per interval
+		var reference_snapshot: _Snapshot = null
+		if _rb_enable_diffs:
+			reference_snapshot = _get_last_sent_rollback_state(peer, peer_snapshot.get_subjects(), tick)
+		var full_subjects := _pick_full_state_subjects(peer, peer_snapshot, reference_snapshot, tick)
 
-		if peer_is_full:
-			var packets := _dense_serializer.write_for(peer, peer_snapshot, _rb_owned_state_properties)
+		if not full_subjects.is_empty():
+			var packets: Array[PackedByteArray]
+			if full_subjects.size() == peer_snapshot.get_subjects().size():
+				packets = _dense_serializer.write_for(peer, peer_snapshot, _rb_owned_state_properties)
+			else:
+				var filter := func(subject): return full_subjects.has(subject)
+				packets = _dense_serializer.write_for(peer, peer_snapshot, _rb_owned_state_properties, filter)
 			for packet in packets:
 				_cmd_full_state.send(packet, peer)
 
-			_remember_sent_rollback_state(peer, peer_snapshot)
 			NetworkPerformance.push_full_state_props(peer_snapshot.size())
 			NetworkPerformance.push_sent_state_props(peer_snapshot.size())
-		else:
-			var diff := _Snapshot.make_patch(reference_snapshot, peer_snapshot)
-			if diff.is_empty():
-				# Nothing changed, don't send anything
-				continue
 
-			var packets := _sparse_serializer.write_for(peer, diff, _rb_owned_state_properties)
-			for packet in packets:
-				_cmd_diff_state.send(packet, peer)
+		var sent_subjects := full_subjects.duplicate()
+		if reference_snapshot != null:
+			var diff := _Snapshot.make_patch(reference_snapshot, peer_snapshot)
+			for subject in full_subjects:
+				diff.erase_subject(subject)
 
-			_remember_sent_rollback_state(peer, diff)
-			NetworkPerformance.push_full_state_props(peer_snapshot.size())
-			NetworkPerformance.push_sent_state_props(diff.size())
+			# Nothing changed, don't send anything
+			if not diff.is_empty():
+				var packets := _sparse_serializer.write_for(peer, diff, _rb_owned_state_properties)
+				for packet in packets:
+					_cmd_diff_state.send(packet, peer)
 
+				NetworkPerformance.push_full_state_props(peer_snapshot.size())
+				NetworkPerformance.push_sent_state_props(diff.size())
+				sent_subjects.append_array(diff.get_subjects())
+
+		if _rb_enable_diffs:
+			_remember_sent_rollback_state(peer, peer_snapshot, sent_subjects)
+
+# PATCH (see addons/NETFOX_PATCHES.md): the subjects of `peer_snapshot` to send in
+# full: all of them with diffs off, one the peer has not been sent yet, and one
+# that has gone `full_state_interval` ticks (not calls) without a full state
+func _pick_full_state_subjects(peer: int, peer_snapshot: _Snapshot, reference: _Snapshot, tick: int) -> Array:
+	var result := []
+	if not _rb_last_full_tick.has(peer):
+		_rb_last_full_tick[peer] = {}
+	var last_full := _rb_last_full_tick[peer] as Dictionary
+
+	for subject in peer_snapshot.get_subjects():
+		var is_due := not _rb_enable_diffs or reference == null or not reference.has_subject(subject)
+		if not is_due and _rb_full_interval > 0:
+			is_due = not last_full.has(subject) or tick - last_full[subject] >= _rb_full_interval
+		if is_due:
+			last_full[subject] = tick
+			result.append(subject)
+	return result
+
 func _synchronize_sync_state(tick: int) -> void:
 	# We don't own sync state, nothing to synchronize
 	if _sync_owned_state_properties.is_empty():
@@ -391,7 +439,29 @@
 	elif is_instance_valid(multiplayer):
 		multiplayer.peer_disconnected.connect(erase_peer)
 
+# PATCH (see addons/NETFOX_PATCHES.md): who may send snapshots, and how big
+# they may be. On a client only the server sends snapshots, so anything else is
+# dropped. Packets are cut by PacketBuffer to max_sync_packet_size, so a packet
+# over the headroom below, per snapshot it may carry, is not honest.
+const _SERVER_PEER_ID := 1
+const _PACKET_SIZE_HEADROOM := 2
+
+func _is_acceptable(sender: int, data: PackedByteArray, snapshots_per_packet: int) -> bool:
+	if not multiplayer.is_server() and sender != _SERVER_PEER_ID:
+		_logger.trace("Dropping snapshot packet from #%d, only the server sends them", [sender])
+		return false
+
+	# A size of zero or less means no limit, as in PacketBuffer
+	var limit := _max_packet_size * _PACKET_SIZE_HEADROOM * snapshots_per_packet
+	if _max_packet_size > 0 and data.size() > limit:
+		_logger.warning("Dropping %d byte packet from #%d, over the limit of %d bytes (netfox/general/max_sync_packet_size)", [data.size(), sender, limit])
+		return false
+	return true
+
 func _handle_input(sender: int, data: PackedByteArray) -> void:
+	if not _is_acceptable(sender, data, _input_redundancy):
+		return
+
 	var buffer := StreamPeerBuffer.new()
 	buffer.data_array = data
 
@@ -399,12 +469,17 @@
 
 	for snapshot in snapshots:
 		snapshot.sanitize(sender)
+		if snapshot.is_empty():
+			continue
 
 		_logger.trace("Ingesting input: %s", [snapshot])
 		if NetworkHistoryServer._merge_rollback_input(snapshot):
 			_on_input.emit(snapshot)
 
 func _handle_full_state(sender: int, data: PackedByteArray) -> void:
+	if not _is_acceptable(sender, data, 1):
+		return
+
 	var buffer := StreamPeerBuffer.new()
 	buffer.data_array = data
 
@@ -413,37 +488,52 @@
 	_ingest_state(sender, snapshot)
 
 func _handle_diff_state(sender: int, data: PackedByteArray) -> void:
+	if not _is_acceptable(sender, data, 1):
+		return
+
 	var buffer := StreamPeerBuffer.new()
 	buffer.data_array = data
 
 	var diff := _sparse_serializer.read_from(sender, _rb_state_properties, buffer)
 	_logger.trace("Received diff state for @%d", [diff.tick])
 
-	_ingest_state(sender, diff)
+	_ingest_state(sender, diff, true)
 
 func _handle_full_sync(sender: int, data: PackedByteArray) -> void:
+	if not _is_acceptable(sender, data, 1):
+		return
+
 	var buffer := StreamPeerBuffer.new()
 	buffer.data_array = data
 
 	var snapshot := _dense_serializer.read_from(sender, _sync_state_properties, buffer, true)
 	snapshot.sanitize(sender)
+	if snapshot.is_empty():
+		return
 
 	NetworkHistoryServer._merge_synchronizer_state(snapshot)
 	_logger.trace("Ingested sync state: %s", [snapshot])
 
 func _handle_diff_sync(sender: int, data: PackedByteArray) -> void:
+	if not _is_acceptable(sender, data, 1):
+		return
+
 	var buffer := StreamPeerBuffer.new()
 	buffer.data_array = data
 
 	var snapshot := _sparse_serializer.read_from(sender, _sync_state_properties, buffer)
 	snapshot.sanitize(sender)
+	if snapshot.is_empty():
+		return
 
-	NetworkHistoryServer._merge_synchronizer_state(snapshot)
+	NetworkHistoryServer._merge_synchronizer_state(snapshot, true)
 	_logger.trace("Ingested sync diff: %s", [snapshot])
 
-func _ingest_state(sender: int, snapshot: _Snapshot) -> void:
+func _ingest_state(sender: int, snapshot: _Snapshot, is_diff: bool = false) -> void:
 	snapshot.sanitize(sender)
+	if snapshot.is_empty():
+		return
 
-	if NetworkHistoryServer._merge_rollback_state(snapshot):
+	if NetworkHistoryServer._merge_rollback_state(snapshot, is_diff):
 		_on_state.emit(snapshot)
 	_logger.trace("Ingested state: %s", [snapshot])
```

## Mutation table

Each patch removed in turn (or one of its parts, as named), the named test run, then
the patch restored. "FAIL" means the test exited 1 or printed a SCRIPT ERROR.

| Patch | What was removed | Test | Result |
|---|---|---|---|
| 1 | the whole bound (upstream) | input_flood | FAIL, a far-future packet freezes the ticks (timeout) |
| 1 | reference clock term (previous patch, bound from `NetworkTime.tick`) | host_hitch | FAIL, 10 and 29 input ticks lost at 700 and 950 ms (1, 11, 21 in an earlier run) |
| 1 | same | input_flood | FAIL, the cut checks |
| 1 | bound set to 7 | input_flood | FAIL, snapshot at the bound refused |
| 1 | bound set to 9 | input_flood | FAIL, snapshot past the bound accepted |
| 1 | bound set to 40 | input_flood | FAIL, snapshot past the bound accepted |
| 1 | bound set to 63 | input_flood | FAIL, snapshot past the bound accepted |
| 1 | the history size cut | input_flood | FAIL, input and sync cut checks |
| 1 | the cut uses `history_limit` for sync state too | input_flood | FAIL, sync cut check |
| 2 | check in `_handle_set_timestamp` | clock_hijack | FAIL, host clock moved |
| 2 | check in `_handle_pong` | clock_hijack | FAIL, client clock moved by the forged pong |
| 3 | the server-only sender check | netfox_client | FAIL, 5 handlers took a non-server packet |
| 3 | `is_server()` condition on the bound (bound on clients too) | netfox_client | FAIL, server input 100 ticks ahead dropped |
| 4 | the `is_empty` checks | netfox_host | FAIL, 7 checks |
| 4 | `_auth_subjects.erase` in `sanitize` | netfox_host | FAIL, 1 check |
| 5 | the changed-bits index check | netfox_host | FAIL, 1 check and 3 SCRIPT ERRORs |
| 5 | the bit cap (limited by bytes available only) | netfox_host | FAIL, 341 ms for 1,000,000 bytes (limit 50) |
| 6 | zero-size / size-past-end check | netfox_host | FAIL, 3 checks |
| 6 | snapshot count cap | netfox_host | FAIL, 50 snapshots yielded |
| 6 | packet size cap in the handlers | netfox_host | FAIL, the padded input packet is merged |
| 6 | size limit 0 not treated as "no limit" | netfox_host | FAIL, input and state packets dropped |
| 7 | the type check | netfox_host | SCRIPT ERROR x3 (scene exits 0, `run_all.sh` fails) |
| 8 | the ignore (assert restored) | netfox_host | SCRIPT ERROR (scene exits 0, `run_all.sh` fails) |
| 9 | range starts at `NetworkTime.tick` (upstream) | slow_frames | FAIL, 43 of 62 ticks never simulated, 230 px instead of 429 px |
| 9 | same | host_hitch | FAIL, ticks stored but never simulated (2, 0, 20) and lost (15, 22, 0) at 400, 700, 950 ms in that run |
| 10 | `_complete_diff` for rollback state | netfox_diffs | FAIL, 4 checks (a=2, b=99 where the host has b=1) |
| 10 | `_complete_diff` for sync state | netfox_diffs | FAIL, sync diff stored without b |
| 10 | per-subject reference (latest record, not latest record holding the subject) | full_state_coverage | FAIL, the diff after a re-simulation is not what the client needs |
| 11 | the periodic per-subject full state | full_state_coverage | FAIL, 1 full state in 120 ticks for A and B, longest gap 69 for C |
| 11 | same | host_diffs | FAIL, the client bot gets 1 full state in 209 ticks |
| 12 | the unknown-frame cap | netfox_host | FAIL, the frames after the cap are read |
| 12 | the warning rate limit | netfox_host | FAIL, 6 and 4 warnings (at most 1) |

