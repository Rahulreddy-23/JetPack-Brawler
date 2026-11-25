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
- `tests/test_hole_rule.tscn` [hole_rule]: one process; probe subjects with a hole in their input: skipped while the hole is open, simulated from it when it is filled in time, left unsimulated and its carry-over made the state of record once it expires; input later than the allowance is refused (exactly the allowance accepted, one tick more refused, a stream of 60-tick-old input refused with no tick older than the allowance simulated and one warning per peer in the log); the refusal count of a peer; the reordered join (first inputs refused once their ticks were passed); the cost of the expired-hole scan.
- `tests/net_late_input.sh` [late_input_1, late_input_2, late_input_refused, silent_peer, pause_input]: two processes (three with OBSERVER=1); the simulator holds a window of the client's packets so that later ones overtake them (`--sim-hold-ms`): inside the allowance no state sent for a tick may be replaced and the client may never show its own bot wrong; past it (EXPECT_REFUSED=1) the straggler is refused, the bot is not simulated on its tick and the client's wrong display is bounded; with a one way delay of 600 ms (EXPECT_SILENT=1) every input is refused, the bot is never simulated and the refusals are counted and warned about; PAUSE_MS stops the client for a second.
- `tests/net_lost_input.sh` [lost_input]: two processes; the simulator drops the packets that carry one input tick (`--sim-drop-ms`); the host's bot stands still at most the input allowance + a few ticks.
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
  large honest property is not lost silently. This warning is rate limited by patch
  14.
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
  as before (the walk back through earlier ticks is for diffs only). The sender part records less
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
  carry-forward from a guess at the tick before; a second diff for the same tick; the
  same for sync state; a merge not marked as a diff is not completed while the same
  merge marked as a diff is, for rollback and sync state; and after a lost diff the
  client's value is still wrong and is right again at the full state one interval
  later) and `full_state_coverage` (after a re-simulation the diff for a subject
  carries every property that differs from what was last sent for it, not from a
  stale carry).

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
- Also: when every subject of a snapshot is sent in full, the dense write is called
  without the per-subject filter (a work saving only; the output is the same).
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
- Not done: nothing known. The warning of patch 6 about a packet over the size limit
  is rate limited separately, by patch 14.

## 13. A public query for state received from the authority

- File: `addons/netfox/servers/network-history-server.gd`
- Function: new `has_authoritative_state(subject: Variant) -> bool` (a Variant, so that a
  freed node can be passed and gives false; GDScript refuses a freed object for an
  `Object` parameter before the function body runs)
- Why: on a client there was no public way to tell state received from the host from
  state the client predicted. The public queries (`get_state_age_for` and the like)
  count predictions, and the authoritative flag is only reachable through the private
  `_rb_state_history`. The query is true once any rollback or synchronized state
  received from the subject's authority has been merged for it in this session, and
  always true on the peer that is the authority (`is_multiplayer_authority()`). It is
  recorded in `_merge_rollback_state` and `_merge_synchronizer_state`, which only
  received snapshots go through, cleared by `reset()` (called by `NetworkTime.stop()`)
  and per node by `deregister()`. A change of state authority does not clear it: the
  synchronizer deregisters properties, not the node. That is harmless while only peer 1
  owns state.
- Cost: one set insert per authoritative subject per merged snapshot.
- Test that fails without it: `netfox_diffs` (client: false with only local
  predictions, true after the first received state, false after `NetworkTime.stop()`,
  true again after the first state of the next session; a snapshot whose tick is refused
  leaves it false; a received sync state sets it; `deregister(node)` clears it; a freed
  subject gives false without an error) and `netfox_host` (true at once for a subject
  the host owns; state from peer 2 for a subject peer 3 owns leaves it false, from peer
  3 sets it, which shows sanitising happens before marking; the host owns neither
  subject, so the authority shortcut does not hide the result). The restart is a stop followed by a new state; the test
  client is never connected, so `NetworkTime.start()` is not run.

## 14. The warning about a packet over the size limit is rate limited

- File: `addons/netfox/servers/network-synchronization-server.gd` (`_is_acceptable`,
  `erase_peer`, `reset`, new `_last_size_warning_msec`)
- Why: patch 6 logs a warning for every packet it drops for size, and any ENet peer
  can send one before it is accepted into the match. 1000 packets of 2048 bytes took
  45 ms and printed 8003 log lines on a Mac debug build, and a phone host is several
  times slower. The first oversized packet from a peer is still logged (an honest
  drop is seen, and `net_smoke` fails on it); after that at most one warning per peer
  per second. The packet is dropped either way.
- Choice: a dictionary of its own in the synchronization server, not the `_warn_peer`
  of patch 12. `_warn_peer` is a method of the snapshot serializers, which share one
  per-peer timer between their warnings (an oversized packet would silence an
  unknown-identity warning for the next second, and the other way round), it logs
  under the serializer's name, and the size check runs before any serializer is
  called. The mechanism is the same: the time of the peer's last warning, one second.
- Bookkeeping: one integer per peer that sent an oversized packet, removed in
  `erase_peer` (called when the peer leaves) and `reset` (called by
  `NetworkTime.stop()`). A peer that is not accepted still gets a connection and
  therefore a leave event, so the dictionary does not outlive the connections.
  (The `_last_warning_msec` of the serializers, patch 12, is not cleared by these
  two functions; at most one integer per peer id that sent a bad frame, not changed
  here.)
- Cost: none for an honest session.
- Test that fails without it: `netfox_host`: 1000 oversized packets from one peer
  inside a second produce exactly one warning (counted with an engine logger); a
  second peer still gets its own first warning; an oversized packet that starts with a
  valid state is still dropped while its warning is suppressed; after the interval the
  next warning is logged again; after `erase_peer` and after `reset` the next packet
  of that peer is logged at once; and the dictionary holds only the peers warned since
  the reset.

## 15. A hole in a subject's input: the host waits for it, then stops waiting, and invents nothing

- Files: `addons/netfox/servers/rollback-simulation-server.gd` (`_get_nodes_to_simulate`,
  `_is_predicting`, new `_starts_from_carry_over`, `_is_hole_accepted`,
  `_get_earliest_expired_hole`, `_get_hole_allowance` and the constant
  `_INPUT_ALLOWANCE_FACTOR`, `_is_start_decided`), `addons/netfox/servers/network-history-server.gd`
  (`_record_rollback_state` passes the tick; `_merge_rollback_input` refuses late input;
  `_note_refused_input`, `get_recent_refused_input_count`, `erase_peer`, and the clear in
  `reset`), `addons/netfox/servers/network-synchronization-server.gd` (`erase_peer` calls the
  history server's) and `addons/netfox/rollback/network-rollback.gd` (`_rollback`).
- What upstream does: a client's input packets carry the last `input_redundancy` ticks, and
  they can overtake each other, so the host can hold the inputs of the ticks after a tick u
  and not the input of u itself (a hole). The host skips a node whose input for the tick is
  missing (`_get_nodes_to_simulate`; prediction is off) and `_record_rollback_state` records
  the state for the next tick as not authoritative, carrying the state of tick u over, so
  nothing is sent for it. But on the next tick the input is there and the node is simulated
  from that carried-over state: `restore_latest` takes the latest state at or before the tick,
  which is the carry-over, one step behind. The result is recorded as authoritative, because
  that decision looks only at whether the previous tick's input exists, and is sent. This
  repeats for every tick until the missing input arrives; then the host re-simulates from u
  and sends every state again, corrected. Every viewer of the bot sees, for as many ticks as
  the hole is open, a state one step behind (28.6 px at jetpack speed in the test), and if
  the two versions of a tick arrive in the other order the stale one stays in the client's
  history. (Found as dev finding D-10; reproduced with `tests/net_late_input.sh`, which
  fails identically on the unpatched addon.)
- The principle: later than the allowance is the same as lost. The host stops waiting, the
  tick stands as one where the bot did not act, and an input for it that arrives afterwards
  is refused. Nothing the host has sent is then replaced. The owner's client, which did
  simulate that tick, is corrected once, by at most the movement of the ticks it lost; that
  is what a lost input costs, and it is accepted. No input is ever made up. An earlier version
  of this patch filled an expired hole with the last known input; the review rejected it:
  after a pause of the client every tick of the pause was filled at once with stale input
  (the bot drove on by itself), one-tick presses were applied again, and the host could
  expire a hole before its straggler arrived.
- The input allowance A is `_INPUT_ALLOWANCE_FACTOR * input_redundancy` = 3 * 4 = 12 ticks,
  400 ms at 30 ticks per second, counted on the host's own clock (`NetworkTime.tick`) from the
  tick the input belongs to: the latest an honest input may arrive. It is one named constant
  used by both rules below. 12 and not 8: the bound also applies to honest input that is
  merely late and in order (a Wi-Fi stall delivers a run of packets at once, and everything in
  it older than A is refused), and the authority audit's own suggestion was about 250 ms plus
  the redundancy (11.5 ticks). With 8 a hold that makes the input arrive about 5 ticks after
  the packets that overtook it already lands past the allowance (hole at tick 152, expiry at
  host tick 161, straggler at 163). It is a first guess, to be judged after the phone test.
- The patch, on the peer that owns the state (the host):
  1. While a hole is open a node is not simulated from a carry-over. A node whose state at the
     tick is only a carry-over (non-authoritative, because it was skipped on an earlier tick)
     is not simulated, and `_is_predicting` says so, exactly like a tick with no input. So no
     state built on a stale start is recorded as authoritative or sent. When the missing input
     arrives in time, the existing path (`_handle_input` sets the earliest input, `_rollback`
     re-simulates from it) simulates from the hole on and sends the states.
  2. Expiry. A tick with no input, with a later input present, whose age
     (`NetworkTime.tick - tick`) is more than A is final: it stays unsimulated, its
     carried-over state becomes the state of record (`_is_hole_accepted`, used by
     `_is_predicting`), and the node goes on from the real inputs after it. Nothing arrives at
     that moment, so `_rollback` asks `_get_earliest_expired_hole()` for the earliest such
     tick whose carry-over is not yet the state of record and re-simulates from it. The rule
     reads only the input and state histories and `NetworkTime.tick`, which does not change
     inside a rollback loop, so every pass over the tick gives the same answer.
  3. A tick with no input before it (the first ticks of a subject that has not started to
     send) is no hole once a later input exists: the subject is simulated from its first input
     tick, with no delay.
  4. Refusal (the audit addition). On a server `_merge_rollback_input` refuses the input of a
     tick older than A (`NetworkTime.tick - tick > A`); exactly A is accepted. So what the
     host did with an expired tick is final, a peer cannot make the host simulate a long
     stretch again by sending old input (a re-simulation starts at most A ticks back), and a
     modified client's hindsight window is 400 ms where it was about 2 s (the history window).
     Upstream's own warning "Input being merged is too old!" (history window, 64 ticks) is out
     of reach for a server now, because the refusal comes first.
  5. The start is final too (`_is_start_decided`). A tick before a subject's first input is
     accepted as "no input, no hole" as soon as a later input is held, and its carried-over
     state is recorded as authoritative and sent. If the input of that tick (or of an earlier
     one) then arrives, inside the allowance, it would be simulated and the states already
     sent would be replaced (the review's probe: inputs 9 and 10 arrive first, ticks 7 and 8
     are carried over and sent, then inputs 7 and 8 arrive). So on a server input for a tick
     with no input held at or before it, whose following state is a carry-over recorded as
     authoritative, is refused. It reads only the input and state histories (nothing is
     stored), so it holds after a pause longer than the history as well, where the old inputs
     are gone from the input history (that case is the same code and has no test of its own).
     An ordinary join is not refused: before a later input is held the states of the ticks
     before the first input are not authoritative.
  6. Visibility. A client whose input always arrives later than A has every input refused, so
     no later input is ever held, no hole is ever accepted, the bot is never simulated and
     nothing is sent for it; its owner sees it move and everyone else sees it frozen, and
     without a message nobody would know why. `_note_refused_input` logs at trace level for
     every refusal and as a warning (peer id, the tick, how old it was at the host, the
     allowance) for the first refusal of a peer and then at most once a second, with
     `_PeerRateLimit` of patch 16. `NetworkHistoryServer.get_recent_refused_input_count(peer)`
     is a read-only query, in the style of `has_authoritative_state`: how many input snapshots
     of that peer the server refused in the last second (0 on a client). Every input tick
     travels in up to `input_redundancy` packets, so a peer whose every input is refused counts
     about 4 per tick, 116 a second in the test. A game can show "connection too slow" from
     it; no UI is built. The bookkeeping is a dictionary per peer that has had a refusal, with
     at most one entry per host tick of the last second (about 31 integers); a refusal costs
     one dictionary update, and the first of each host tick also drops the entries older than
     a second. A peer with no refusals costs nothing. It is erased when the peer leaves
     (`NetworkSynchronizationServer.erase_peer` calls `NetworkHistoryServer.erase_peer`, which
     also erases the limiter's entry) and cleared by `NetworkHistoryServer.reset()`, which
     `NetworkTime.stop()` calls; both are tested.
  The scan for expired holes runs once per remote input node per rollback loop, with no
  allocation: it starts at the tick before the loop (the newest state recorded) and goes back
  only while the subject's states are carry-overs.
- Host stall: the multiplayer poll runs before the tick loop in a frame (`SceneTree` polls
  first; `NetworkTime._loop` runs in `_process`), and a stalled host does not advance
  `NetworkTime.tick`. So the packets that queued up during a 400 to 950 ms freeze are merged
  in the first poll after it, while the host's tick is still the old one: their age is small
  or negative, never above A. Measured by `host_hitch` (the `INPUT_AGE` lines): the oldest
  input merged after the freezes was 1 to 2 ticks old (400 ms), 0 to 1 (700 ms) and below 0
  (950 ms: the clock is reset after a stall above the stall threshold); every input tick of
  the client was stored at all three freeze lengths (369 of 369) and the bot simulated on
  each. The catch-up ticks (8 per frame at most) run after the poll, so a stall of the host
  does not make honest input older than A. A stall of the client's network is the case the
  refusal is for: a run of packets arrives at once, and what is older than 12 ticks is
  refused.
- What is not touched: a client (`is_multiplayer_authority()` is false for the state it
  predicts, so the rules return false there; the refusal is for a server only); the host's own
  bot (its input is recorded every tick, no hole); subjects without inputs are simulated on
  every tick as before; the combat resolver runs on `after_process_tick`, which is emitted
  for every tick whether a node was simulated or not. Nodes with `enable_prediction` on keep
  upstream behaviour; the project does not use it.
- Costs, stated plainly:
  - An input that never arrives holds that bot still for up to A = 12 ticks before it carries
    on (measured by `lost_input`: 11 ticks standing still), and its state is not sent in that
    time, so other players see it stand still. Before this patch they saw a state one step
    behind instead.
  - After a pause of the client the bot moves again within that allowance of the first new
    input (the last ticks of the pause are younger than A and stay open until they expire).
  - A modified client's window to put input in the past is 400 ms (it was about 2 s).
  - The owner's own client shows its bot wrong for up to A ticks after an input that never
    arrives (it simulated the tick, the host did not), at most the movement of the ticks it
    lost, and is corrected once the host's states arrive.
  - Hits and the resolver (a correction to an earlier version of this note, which said the
    resolver sees a held bot at its last position): when a hole expires or is filled the host
    re-simulates from the hole to now, so the resolver runs again on every held tick with the
    bot on its real path; only the hole tick itself keeps the bot standing still. So "no state
    the host sent is replaced" holds for the held bot itself, but the states of other
    subjects that depended on it during the hold (an attacker's knockout count and repair,
    pickups, world objects) are sent during the hold and can be replaced afterwards: the same
    class as before this patch, over a window of up to A ticks.
  - In plain terms: any lost input, and the end of any pause, holds that bot still for
    everyone else for up to 400 ms, and then it jumps.
  - A join in which the inputs of the first ticks arrive after later ones (the review's probe,
    reproduced with 150 ms of jitter: 5 refusals, first stored input at tick 30): those first
    inputs are refused, and the owner's client, which simulated those ticks, shows its bot
    wrong once (one loop, 1.8 px) before the host's states correct it. Nothing the host sent
    is replaced. `late_input` reports `JOIN_REORDERED` and does not count those ticks (up to
    two after the first input stored); any other wrong tick still fails it.
  - A client whose input always arrives later than A is out of sync for good (see 6): its
    owner sees its bot move, everyone else sees it frozen at its last carried-over state.
  - The scan for expired holes: per rollback loop, per remote input, two state lookups and one
    input lookup in a normal session (the tick before the loop is authoritative), more while a
    subject's input is missing (one more per tick it has been missing, at most the history
    window). Timed in `hole_rule` with six remote inputs, several of them with a long run of
    missing input: 240 microseconds per call (the review measured 1.4 to 1.7 ms for the first
    version of the scan and about 6 microseconds per call in a normal session); `hole_rule`
    fails above 500.
- Tests that fail without it (run_all names): `hole_rule` (one process; a probe subject
  registered with the real history and simulation servers: first input without delay, hole
  open, hole filled in time, expiry by the host's clock whatever input follows, nothing made
  up and a one-tick press applied once, the expiry stays after simulating again, a straggler
  after the expiry refused and changing nothing, exactly A accepted and A + 1 refused, a
  stream of 60-tick-old input refused with no tick older than A simulated and one warning per
  peer in the log instead of one per snapshot, the refusal count of a peer: counted, 0 for a
  peer not refused, 0 a second later, erased when the peer leaves, cleared on reset; the
  reordered join: inputs 10 and 11 first, the carried-over states of 8 and 9 authoritative,
  inputs 8 and 9 then refused and nothing replaced; an ordinary join after the host passed some
  ticks still accepted and simulated from its first tick; scan time), `late_input_1` and `_2`
  (two processes, `_2` with a third client watching; the simulator holds the client's packets
  of a 150 ms window an extra 183 and 217 ms; the test reports how many ticks after its own
  tick the hole's input arrived and fails if that is within 3 ticks of A; zero states sent and replaced, zero loops
  with the client's own bot wrong, the bot simulated from its first input tick),
  `late_input_refused` (a hold of 600 ms, 18 ticks, past A: the hole's input is refused, the bot is not
  simulated on that tick, zero states replaced, the client's wrong display ends within
  A + `input_redundancy` ticks of the hole, and host and client agree afterwards; with a third
  client watching), `pause_input` (the client is stopped for a second with SIGSTOP: the host
  never simulates the bot on a tick it has no input for, the bot does not move across them,
  and the client's wrong display is bounded the same way), `silent_peer` (a one way delay of
  600 ms, so that every input of the client is later than A: the host stores none, never
  simulates the bot, sends no state for it, counts the refusals for the peer and warns at most
  once a second, while the client moves its own bot), `lost_input` (the simulator drops
  the packets of a 140 ms window for good: the bot stands still on the host for at most A +
  the number of lost inputs + 2 ticks, then goes on, and host and client agree 20 ticks after
  the last lost input), `host_hitch` (every client input tick still stored at 400, 700 and
  950 ms freezes, with the age of the oldest input merged reported).
- Measured: `tests/net_late_input.sh`, no run spanning a pause of the machine.
  - Inside the allowance: holds of 183 and 217 ms (window 150 ms) made the hole's input arrive
    6 to 7 and 7 to 8 ticks after its own tick; 5 of 5 runs each passed with the whole
    `run_all.sh` suite running on the same machine (margin to A = 12: 4 ticks at the least;
    the test fails below 3). The earlier 250 ms hold made it arrive 8 to 9 ticks after its
    tick, a margin of 3 when idle and about 1 when busy, and a hold of 317 ms 10 to 11, so
    neither is a test. In all runs: 0 states sent and then replaced (full state signature),
    0 loops with the client's own bot shown wrong, the bot first simulated on its first input
    tick, and the third client received 0 wrong states (its longest silence for the bot was 7
    client ticks, then a catch-up of 4 to 5 ticks and 11 to 15 px).
  - Beyond the allowance: a hold of 600 ms (18 ticks; 5 of 5 runs passed under the same load;
    a hold of 500 ms, 15 ticks, is only 3 ticks past A and was replaced): the hole's input
    is refused (1 or 2 ticks never stored), the bot is not simulated on them, 0 states sent and
    replaced, the owner's client shows its bot wrong for 12 to 13 ticks (ticks hole + 1 to
    hole + 12 or 13, at most 23.5 px), which ends when the host's states for the following
    ticks arrive (the bound in the test is A + `input_redundancy` ticks after the hole), and
    host and client agree on every later settled tick (`TRACE_DIFF` lists 1 or 2 ticks, right
    after the hole). The third client: 0 wrong states, longest silence 11 client ticks, then a
    catch-up of 3 ticks and 6.6 px.
  - A client whose input always arrives later than A (`silent_peer`, a one way delay of 600
    ms; with 450 ms the input arrives 12 ticks after its tick, right at A, and only some of it
    is refused, so that is not a test): all 8 warnings in about 10 seconds are for that peer
    (one a second), the first one reading "Refusing input @112 from peer #...: 38 ticks old
    at the host (the allowance is 12)"; `get_recent_refused_input_count` read 116 at the end;
    the host stored 0 inputs, simulated the bot on 0 ticks and sent no state for it, so its bot
    stayed at its spawn point (0 px travelled) for everyone else, while on its owner's client
    it travelled 277.6 px. Nothing else on the client says anything is wrong: its own bot is
    displayed from its own prediction and no state ever corrects it.
  - A pause of the client of one second (SIGSTOP; 2 runs, and 5 of 5 under load): 31 and 32 ticks without input,
    0 simulated by the host, the bot did not move across any of them, 0 loops with the client's
    own bot wrong. On the first version of this patch (750c6e0) the same test fails: 31 ticks
    simulated without input, the bot moves on every one of them, and the client shows it wrong
    for 5 loops, up to 409.6 px.
  - A lost input (`lost_input`, 3 runs): the bot stands still on the host for 11 ticks, then
    goes on; host and client agree 20 ticks after the lost tick.
  - Host stall (`host_hitch`, 3 runs): every client input tick stored (369 to 370 of 370), the
    oldest input merged 2, 1 and -3 ticks old at the 400, 700 and 950 ms freezes (1, 0 and -4 in
    the third run).
  - Smoke test under simulated jitter on both sides (`SIM_JITTER_MS`, same compare rule, the
    tree without this patch against the tree with it): at 300 ms the unpatched tree fails 10 of
    10 runs (the client's settled position differs from the host's final one, 12.8 to 39.3 px);
    with the patch 0 of 10 fail, 7 pass and 3 are inconclusive. At 150 ms the unpatched tree
    passes 20 of 20; with the patch 18 pass, 0 fail and 2 are inconclusive. The inconclusive
    runs are not passes: the one examined at 150 ms had a logged stall (a busy machine); at
    300 ms the host had not simulated some tick of the bot (a tick whose input arrived later
    than the allowance, or never; jitter on both sides plus the client's lead can pass 12 ticks)
    and the dash that the rule needs to compare was within 8 ticks of it. With 75 ms of latency
    on top of 300 ms jitter a run failed the rule "the host lacked the client's input for more
    than 2 ticks": 4 of 135 ticks had no input within the allowance.
  - Timeline from a real log of the host (`TICK_LOG=1`, hold of 217 ms, hole at tick 156): at
    host tick 157 to 164 the bot is not simulated and stays at x = 2397.81; at host tick 162
    the inputs of ticks 157 to 160 are there but the bot is still not simulated (they sit
    behind the hole); the hole's input arrives at host tick 164 (8 ticks after its tick), and
    in the loop at 165 ticks 156 to 163 are simulated again in one pass (x 2395.68 to 2380.75)
    and the bot is simulated on every tick after. For a pause: the last input before it is for
    tick 111; the bot stands still at x = 2489.54 from host tick 112; the first input after it
    (tick 143) arrives at host tick 145 and is not simulated; at host tick 155 the hole at tick
    142 is older than 12 ticks, and ticks 143 to 153 are simulated in one loop: the bot moves
    again 10 ticks after the first new input.

## 16. Reads that take a length from a packet, and log lines a peer can drive without limit

Part A, the crash. Part A2, strings that cost a line per byte. Part A3, the name of a subject in a snapshot frame. Part B, the sweep of every other read. Part C, the log lines. Part D, what is not fixed. Part E, every place peer bytes become text.

### A. A 4 byte packet kills the host

- Files: `addons/netfox/serializers/identity-packet-serializer.gd` (`deserialize`),
  `addons/netfox/schemas/network-schemas.gd` (`_VariantSerializer`, `_StringSerializer`,
  `_ArraySerializer`, `_DictionarySerializer`),
  `addons/netfox/servers/network-command-server.gd` (`_PacketTransport._handle_packet`),
  `addons/netfox/serializers/dense-snapshot-serializer.gd` and
  `addons/netfox/serializers/sparse-snapshot-serializer.gd` (`read_from`)
- Why: in Godot 4.7.2 `StreamPeerBuffer.get_utf8_string()` and `get_var()` read a 32 bit
  length from the buffer and allocate that much before they check how many bytes are
  left. A buffer of `[0xff, 0xff, 0xff, 0x7f]` (2 GB declared) ends the process with
  SIGBUS: probed outside the project, exit code 138 for both, and the unpatched
  `netfox_host` test dies with exit 138 on its first such call (mutation table).
  Two paths reach it from a peer, both before anything is validated:
  1. Command 0 is the identity packet (`NetworkIdentityServer._handle_ids`), which any
     connected peer may send, one not yet accepted into the match included. The
     deserializer called `get_utf8_string()` on it. 4 bytes were enough.
  2. Every property of the game is read by the variant serializer (`get_var`): the
     project registers no schema (`set_schema`, `merge_schema` and `register_schema`
     are never called in `scripts/`, `scenes/` or the autoloads), so every state, input
     and sync property uses the fallback. A state or input packet with one frame of a
     known subject whose first property is those 4 bytes reaches `get_var` in
     `read_from`, before the sender is checked for ownership. This path was not in the
     external report; it is the wider one.
- The fix: the 4 byte length is read, refused if negative or larger than the bytes left,
  and only then are exactly that many bytes read. The variant serializer reads the
  length itself, checks it, and then lets `get_var(false)` decode from the same place
  (the format is the one `put_var(v, false)` writes; objects are not built). The first
  version of this patch decoded with `bytes_to_var` on a copy of the bytes, which was
  slower; see A2. The string serializer checks the same way.
- A malformed identity packet registers nothing. The reviewer's version (geminiceo
  `5af3bfe`) stops at the first bad entry and keeps the entries before it. That is
  harmless (each kept entry is a complete name and id, as in a shorter packet), but a
  packet that is cut or malformed anywhere is not an honest client's, so
  `deserialize` returns an empty dictionary for it, and an id whose varuint ends in the
  last byte while still marked as continued is also a cut packet (a half id would
  otherwise be stored as a wrong id, 0 at worst, the marker of a name reference).
  An empty name is read as an empty name.
- The size cap of Part C does not protect against this: a 4 byte packet is under any cap.
  The length check is what protects, and the tests call the deserializer without the
  cap in front of it.
- The raw command packet: `_PacketTransport._handle_packet` accepted a packet that was
  exactly the 3 byte prefix, read the missing command index as 0 (`get_u8` on nothing)
  and dispatched command 0 with an empty payload. It now requires the index byte.
- Array and dictionary schemas: the count read from the packet was used for
  `array.resize` and as a loop bound. A count over the bytes left (each item takes at
  least one byte, each dictionary entry at least two) is now an empty result. Neither
  can be reached today (no schema is registered, as above), they are bounded because an
  unused decoder that crashes on a short packet is one `set_schema` call from reachable.
- Frames in a state packet: the size of a frame (`node_data_size`) is now checked
  against the bytes left, and the packet ends there if it is larger or negative.
  `get_partial_data` itself is safe for a size past the end (probed: it returns the 4
  bytes there are, in 0 ms, for 2^31 - 1 and for 2^32 + 5) but a negative size is an
  engine error for every such frame (probed), and a frame declared larger than the
  packet was read from what remained.

### A2. A string costs a line per invalid byte

- Files: `addons/netfox/serializers/identity-packet-serializer.gd`,
  `addons/netfox/servers/network-identity-server.gd`,
  `addons/netfox/network-time-synchronizer.gd`, `addons/netfox/schemas/network-schemas.gd`
- Why: Godot prints one engine line ("Unicode parsing error ... Invalid UTF-8 leading
  byte") for every invalid byte of a string it decodes. So any string a peer can make the
  host decode costs a line per byte, whatever the bounds on the packet are. Three places
  decoded a peer's string without a bound of their own. Measured by calling the real
  handlers (Mac, headless, debug build), lines counted in process by an engine logger:
  1. Identity packet, one name of 14,000 bytes of 0xff (a packet of 14,005 bytes, under
     the 14,522 byte cap): 14,000 lines, 136 ms (the reviewer measured 491 ms).
     100 names of 128 bad bytes, each within the name limit and 13,300 bytes in all:
     12,800 lines, 112 to 148 ms.
  2. The ping command (`_handle_ping`): a payload that is a string variant of 200,000
     bad bytes: 200,000 lines, 1.8 s on the main thread. The pong and the timestamp
     handlers decode the same way (they take packets from the server only, but a client
     must not be stalled by a bad host packet either).
  3. The variant fallback: a state, input or sync property sent as a string of bad bytes:
     one line per byte, 2,000 lines for a 2,000 byte property, up to about 4,000 for a
     4 KB input packet, unreliable, and decoded before the ownership check.
  After this each of these costs 0 lines and 0 to 1 ms.
- Identity names: `deserialize` refuses the whole packet (reads as no entries) if a name is
  longer than `MAX_NAME_BYTES` (128, which `_MAX_ID_NAME_BYTES` is now taken from, and was
  declared but not enforced per name before) or has a byte of 0x80 or more, judged on the
  raw bytes before decoding, and stops after `_MAX_ID_ENTRIES + 1` entries instead of
  reading the rest. A packet that reads as nothing but is not empty is refused with the
  same rate limited warning as an oversized one. Assumption, stated in the code: node
  paths in this project are ASCII. A node named with other characters would not be
  synchronised. A NUL byte inside a name truncates it when it is read as ASCII; that is
  harmless, because a peer can only set its own id mapping, and a truncated name either
  matches no node or names one the peer could have named in full. The honest sessions refuse nothing: `net_smoke` (also its lag and jitter
  runs), `net_full` and `net_world_objects_join` now fail on the text "Refusing identity
  packet", and an instrumented run over seven session scripts (349 packets) saw no
  refusal and names of 37 bytes at most.
- Clock commands: the payload of a ping is `var_to_bytes(int)`, of a pong
  `var_to_bytes([int, float, float])`, of a timestamp `var_to_bytes(float)`. The handlers
  refuse a payload whose header type is not int or float, before decoding, and whose size
  is not exactly 8 bytes (12 with the header's 64 bit flag, bit 16): any other size is a
  malformed variant that prints a line or two when decoded (the first version only
  bounded the size from above, and an int header with the flag and a 4 byte body passed).
  A pong must have an array header, a count of 3, and at most 44 bytes (4 byte headers
  and 8 bytes for each 64 bit number), and be an array of an int and two floats once
  decoded. A pong that passes can still hold a string of up to about 30 bytes, or be
  cut inside an element, so up to about 30 lines a packet, from the server only.
- Variant fallback: only fixed-size values are decoded. The type is read from the 4 byte
  header after the length (without decoding) and the value is decoded only if it is nil,
  bool, int, float, or one of the math types and Color: Vector2, Vector2i, Rect2, Rect2i,
  Vector3, Vector3i, Transform2D, Vector4, Vector4i, Plane, Quaternion, AABB, Basis,
  Transform3D, Projection, Color (the types of Godot 4.7 with numbers 0 to 20 except
  String). These carry no length and no string, so decoding costs a fixed time and at
  most one line per packet, never one per byte. Everything else (String, StringName,
  NodePath, RID, Object, Callable, Signal, Dictionary, Array and the packed arrays,
  which may hold strings or a length) is skipped, the buffer moves past its declared
  length, and the property reads as null. This is a deliberate restriction of netfox for
  this project: a property of a string or container type needs a registered schema with a
  bounded decoder of its own (and the string, array and dictionary schemas of this addon
  are bounded by length only: see Part D). Every property this game synchronises is of an
  allowed type. The 69 properties of the three scenes with a synchroniser, read from the
  scenes by the test and each round-tripped:
  - Vector2 (14): bot global_position (in the lists of two synchronisers), velocity,
    dash_dir, aim_dir, Vitals:last_hit_push, Arsenal:shot_dir, Arsenal:melee_dir,
    Gadgets:gadget_dir, Input:move, Input:aim; world object global_position (two lists)
    and velocity.
  - float (10): bot fuel, thrust_level, dash_left, dash_cooldown_left, jet_buffer,
    dash_buffer, wall_grace_left, drop_left, Vitals:health, Vitals:last_hit_damage.
  - bool (10): bot jet_held_prev, Vitals:knocked_out, Input:jet, dash, fire, melee, gadget,
    swap; world object active, landed.
  - int (35): the other bot state (wall_nx, facing, the counters and ticks of Vitals,
    Arsenal and Gadgets), the world object's kind, owner_peer, spawn_tick, arm_tick,
    fuse_tick, explode_tick, launches, blasts, and the pickup spot's ready_tick.
- Header type and body size: the fixed-size check above still let `get_var` fail, at two
  engine error lines a value, in two shapes. The type was read as `header & 0xff`, so
  it could be 0 to 255, and the allow-list was tested by a shift, which wraps in
  GDScript for a count of 64 or more (`6 >> 65` is 3): a header type of 65 was tested as
  type 1 (bool) and allowed, and `get_var` then failed on a type the engine does not
  know. And an allowed type with a declared size shorter than its body (a size of 4 with
  an int header and no body) was let through. A packet of 4,056 bytes of such 8 byte
  values cost 1,016 error lines and 25 ms. Now the type must be at most `TYPE_COLOR`
  before it is shifted, and the declared size must hold the 4 byte header and the body
  of the type, from two constant tables (without the header's 64 bit flag and with it).
  Probed for each allowed type with the flag clear and set, and with the other 15 flag
  bits set: the smallest body the engine decodes with no error is, in bytes, nil 0; bool 4;
  int and float 4, 8 with the flag; Vector2 8, 16; Vector2i 8; Rect2 16, 32; Rect2i 16;
  Vector3 12, 24; Vector3i 12; Transform2D 24, 48; Vector4 16, 32; Vector4i 16; Plane 16,
  32; Quaternion 16, 32; AABB 24, 48; Basis 36, 72; Transform3D 48, 96; Projection 64,
  128; Color 16. Only the flag (bit 16) changes the size, and only for int, float and the
  types made of floats. Longer bodies decode with no error. A declared size larger than
  the type needs is consumed in full (the decoder seeks past `size` bytes, `get_var` reads
  that many and ignores the extra), so the reader stays aligned: the test reads a value
  with 8 bytes too many and then the next value in place. With both checks `get_var`
  cannot fail on a value the decoder passes to it; the test runs every allowed type in
  both forms at its exact size (accepted), one byte short (refused, skipped) and 8
  bytes too long (aligned), with 0 engine errors, and header types 21, 38, 39, 64, 65,
  66, 128, 129 and 255 (refused). After this the packets of 8 byte values cost 0 engine
  error lines in 2 ms for a state packet and an input packet at the size caps.
- Speed: after the length and the type are checked the value is decoded by `get_var(false)`
  after a seek back, which allocates nothing more than the unpatched code did (the length
  is below the bytes left). The first version of this patch decoded with `get_data` and
  `bytes_to_var` and was slower. 20,000 decodes of a bool, an int, a float, a Vector2 and
  a Vector2i, median of 7, Mac debug build, in microseconds: a bare `get_var(false)` loop
  1,240 to 1,340; the unpatched serializer method (one call around `get_var`) 3,820 to
  4,100; the first version of the patch 9,610 to 10,260; this version, with the type and
  size checks of the paragraph above, 9,460 to 9,680. Through `_NetworkSchema.decode`,
  the call the synchronisers actually make: unpatched 16,260 to 16,850, this version
  22,250 to 22,860, 1.37 to 1.40 times. Per property that is about 0.3 microseconds more
  on a Mac, about 0.15 ms for a full client state of 520 properties; a phone will be
  several times that, not measured. The serializer alone is 2.4 times the unpatched
  serializer, more than 1.5: the extra is the calls of the checks (the first round of this
  patch, before the type and size checks, was 2.0 times; a variant with one 64 bit read
  for the length and type was tried and was no faster).

### A3. The name of a subject in a snapshot frame

- File: `addons/netfox/schemas/network-schemas.gd` (`_CStringSerializer.decode`)
- Why: the first sweep (Part B) looked for reads whose length comes from the packet, and
  passed this decoder as "bounded by the bytes left". It is bounded in bytes but not in
  error lines. `_NetworkIdentityReferenceSerializer.decode` calls it whenever a frame's
  subject reference has id 0, which means "named by full name" (what a late joiner sends
  before it knows ids). The dense, sparse and redundant snapshot serializers read a
  reference at the start of every frame, in input, state and sync packets, before the
  sender's ownership is checked. The name was collected up to a NUL and decoded with
  `get_string_from_utf8()`, which prints a line per invalid byte. A packet that is id 0
  followed by 0xff bytes cost, measured by calling the real handlers (Mac, headless, debug
  build), counting the engine's lines in process:

  | Packet | Before | After |
  |---|---|---|
  | full state, 1,016 bytes (the cap) | 1,011 lines, 9 ms | 0 lines, 0 ms |
  | diff state, 1,016 bytes | 1,011 lines, 12 ms | 0 lines, 0 ms |
  | full sync, 1,016 bytes | 1,011 lines, 11 ms | 0 lines, 0 ms |
  | diff sync, 1,016 bytes | 1,011 lines, 11 ms | 0 lines, 0 ms |
  | input, 4,058 bytes (the cap) | 4,051 lines, 36 ms | 0 lines, 0 ms |
  | 33 frames with a 3 byte bad name each | 9 lines | 0 lines |

  The reviewer measured 15,000 lines and 100 ms for a 15 KB packet under their own cap;
  the caps here are smaller. A direct probe: `get_string_from_utf8` on 15,000 bytes of
  0xff prints 15,000 lines in 126 ms, `get_string_from_ascii` prints none in 0 ms.
- The fix is the reviewer's idea (geminiceo `2ee2aba`), written differently. The decoder
  finds the NUL with `find`, and consumes the name in full, to and including the NUL, so
  the reader stays aligned with the rest of the frame. A name longer than
  `_IdentityPacketSerializer.MAX_NAME_BYTES` (128) is refused without being scanned (the
  reviewer's loop walked the whole name, up to the packet size, in GDScript); a name with a
  byte of 0x80 or more is refused, judged on the raw bytes; otherwise it is decoded with
  `get_string_from_ascii()`. A refused name, and a name with no NUL before the end of the
  buffer (which consumes the rest of the buffer), are the empty string, which no subject
  has. The reviewer's version returned a name with no NUL; this one does not, because an
  honest writer always ends the name.
- What a refused name does to the frame: the reference resolves to nothing. The dense
  serializer then takes the unknown-identity path of patch 12: it has read the frame's
  size field and skips that many bytes, counts the frame against the number of registered
  subjects, and stops the packet when more frames than subjects are unknown, with its
  warning rate limited (once a second a peer). The sparse serializer breaks at the first
  unknown frame. Checked by the tests below: a packet of 33 frames, each with a bad name,
  costs 0 lines and 0 ms, and a frame after a refused one is read in place. A name is
  ASCII only, like the identity names; a node named with other characters would be skipped
  on a late join (the honest session does not name its nodes so).
- Tests (`netfox_host`): the five packet kinds above through the real handlers, at the
  size caps, give 0 engine error lines and under 50 ms; 33 frames with bad names give at
  most one unknown-identity warning; a name of 129 bytes, a name with a byte of 0x80, and a
  valid UTF-8 name that is not ASCII are skipped and the frame after each is merged; a
  name with no NUL is empty and prints nothing; a frame named by its full name resolves
  to its subject (the honest late-join path); the decoder reads a name of 128 bytes, gives
  empty for 129, and leaves the byte after each NUL in place. `net_full` and
  `net_world_objects_join` (a late joiner) pass, and they fail on a refused identity
  packet.

### B. The sweep: every read on network data whose size or count comes from the packet

Probed outside the project (`godot --headless -s`, one process per case, killed after
20 s; the script is not part of the repository):

| Call | Input | Result |
|---|---|---|
| `get_utf8_string()` | length 2^31 - 1, 4 bytes | killed, exit 138 (SIGBUS) |
| `get_utf8_string()` | length -1 | engine error, empty string |
| `get_utf8_string()` | length one more than the bytes left | engine error, empty string |
| `get_var(false)` | length 2^31 - 1, 4 bytes | killed, exit 138 (SIGBUS) |
| `get_var(false)` | length 2^30 - 1, 4 bytes | engine error, null, no crash |
| `get_var(false)` | length -1 | engine error, null |
| `get_partial_data(n)` | n = 2^31 - 1 or 2^32 + 5, 4 bytes in the buffer | returns the 4 bytes, 0 ms |
| `get_partial_data(-5)` | | engine error, empty |
| `get_data(2^31 - 1)` | 4 bytes in the buffer | error code returned, no crash |
| `bytes_to_var` | ARRAY, typed ARRAY, DICTIONARY, STRING, PACKED_BYTE_ARRAY, PACKED_VECTOR2_ARRAY, PACKED_STRING_ARRAY declaring 2^31 - 1 items, PACKED_INT32_ARRAY declaring 2^30 - 1; ARRAY and DICTIONARY also with a few valid items after the count | engine error, null, no allocation from the declared count, no crash |
| `bytes_to_var` | 100,000 nested arrays | "Variant is too deep. Bailing.", no crash |
| `bytes_to_var` | an object | refused (ERR_UNAUTHORIZED) |
| `bytes_to_var` | 2 bytes | engine error, null |

Each place in the addon that reads a size or count from a packet:

| Site | What the packet decides | Status |
|---|---|---|
| `identity-packet-serializer.gd` `deserialize`: name length (`get_utf8_string`) | allocation | crash; bounded now by this patch (length checked, atomic) |
| the same, the name's bytes (`get_string_from_utf8`) | one error line per invalid byte | bounded now (A2): a name over 128 bytes or with a byte of 0x80 or more refuses the packet, checked on the raw bytes |
| the same, id (varuint) | up to 10 bytes | bounded by the 10 iteration loop upstream; now also must end inside the packet |
| `network-identity-server.gd` `_handle_ids` | size and entry count of the packet | unbounded before; bounded now by this patch (Part C) |
| `network-schemas.gd` `_VariantSerializer.decode` (`get_var`) | allocation, and a line per invalid byte of a string | crash, reachable from every state, input and sync packet; bounded now (A, A2): length checked, only fixed-size types decoded |
| `_StringSerializer.decode` (`get_utf8_string`) | allocation | crash; not reachable today (no schema is registered); bounded now |
| `_ArraySerializer.decode`, `_DictionarySerializer.decode` | resize and loop count | unbounded; not reachable today (no schema is registered: `grep` of `scripts`, `scenes`, `project.godot` for `NetworkSchemas`, `array_of`, `set_schema`, `merge_schema`, `register_schema` finds none, and in the addon the only callers of `register_schema` are `set_schema` and `merge_schema` of the two synchronizers); bounded now by the bytes left |
| `_CStringSerializer.decode` | loop, and a line per invalid byte of the name | bounded in bytes upstream, but not in error lines (the first version of this table stopped there); fixed in A3 |
| `_VaruintSerializer.decode` | loop | at most 10 iterations, upstream; may yield a negative number, handled by its users below |
| `_VariableBitsetSerializer.decode` | bytes read | patch 5 |
| `_NetworkIdentityReferenceSerializer.decode` | id or name | the two above |
| `dense-snapshot-serializer.gd` `read_from`: frame size | `get_partial_data` | probed: clamps, negative is an engine error; bounded now by this patch; unknown frames by patch 12 |
| `sparse-snapshot-serializer.gd` `read_from`: frame size | `get_partial_data` | the same; the changed-bits field by patch 5 |
| `redundant-snapshot-serializer.gd` `read_from`: snapshot size and count | `get_partial_data`, loop | patch 6 |
| `network-synchronization-server.gd` handlers: packet size | everything above | patch 6 |
| `tickset-serializer.gd` `deserialize` (`RewindableAction._submit_state`) | loop over the bytes | bounded by the bytes; the RPC is `authority` mode, so only the host can call it on a client; the node is not used in this project |
| `network-time-synchronizer.gd`: `bytes_to_var` in `_handle_ping`, `_handle_pong`, `_handle_set_timestamp` | decoded variant | probed above: no crash, no allocation from a declared size, but one error line per invalid byte of a string (a ping of 200,000 bad bytes cost 1.8 s; an earlier version of this table said "one engine error per packet", which was wrong). Bounded now (A2): the payload must be of the honest size and header type before it is decoded. A pong and a set time only from the server (patch 2), the type of a ping is checked after decoding (patch 7) |
| `_StringSerializer.decode` (`get_string_from_utf8`) | a line per invalid byte | not reachable today (no schema is registered); bounded by the packet only. See Part D |
| `network-command-server.gd` `_PacketTransport._handle_packet`: command index and rest | one byte, then `get_partial_data(available)` | the index byte was assumed; required now by this patch. `get_partial_data(available)` cannot exceed the packet |
| `network-command-server.gd` RPC transports | `idx` and `data` | typed RPC arguments; the data goes to the handlers above |
| `network-tickrate-handshake.gd` `_submit_tickrate(tickrate: int)`, `network-time.gd` `_submit_sync_success()` | one typed int, none | no read from a buffer |
| `get_string`, `get_data` | | not used in the addon outside this patch, which checks the length first |

Not reachable from a peer: nothing else in `addons/` reads a network buffer.

### C. Log lines a peer can drive without limit

- Files: new `addons/netfox.internals/peer-rate-limit.gd` (`_PeerRateLimit`),
  `addons/netfox/servers/network-command-server.gd` (`_handle_command`, new
  `erase_peer` and `reset`), `addons/netfox/time/network-tickrate-handshake.gd`
  (`_handle_tickrate_mismatch`, `run`, `stop`, new `erase_peer`),
  `addons/netfox/servers/network-identity-server.gd` (`_handle_ids`, `erase_peer`,
  `clear`) and `addons/netfox/network-time.gd` (`stop` calls the command server's
  `reset`)
- Why: three handlers log for every packet they get, from any connected device, one of
  which is not yet accepted into the match. Measured by calling the real handlers
  (Mac, headless, debug build):
  1. An unknown command index logged an error line and a `push_error` per packet:
     1000 packets took 52 ms and made 1000 lines.
  2. A tickrate that differs logged a warning and a `push_warning` per packet: 1000
     packets took 55 ms and made 1000 lines.
  3. An identity packet logged one INFO line per entry (the project's netfox log level is
     INFO) and had no size limit: one packet of 10,000 names (258,762 bytes) took 149 ms
     and made 10,000 lines; a reliable packet can be megabytes.
- Rate limit (1 and 2): `_PeerRateLimit.allow(peer)` is true for the first call for a
  peer and then at most once per second per peer, the mechanism of patch 14 in a
  class of its own, because three files need it. The patch 12 `_warn_peer` is a method
  of the snapshot serializers and was not reachable from them. After this, 1000
  packets cost 0 to 3 ms and make one line each. The packet is handled as before:
  an unknown command is ignored, a mismatch is a warning (or the other configured
  actions, which are not limited here: disconnect ends the connection, signal and
  adjust log nothing a peer can repeat). Each table is erased when the peer leaves
  (command server: `NetworkEvents.on_peer_leave`, as the identity server;
  handshake: `multiplayer.peer_disconnected`, connected in `run`, disconnected in
  `stop`) and cleared on a reset (command server and identity server: `reset`, both
  called by `NetworkTime.stop()`; handshake: `stop`; the identity server's `clear` clears
  the table too).
- Identity packets (3): the per-entry INFO line is now a TRACE line and there is one
  DEBUG line per packet with the entry count and the sender. Chosen over one INFO line
  per packet because a peer can send small packets as fast as the network carries
  them, and an INFO line per packet would still be a line per packet; at debug and
  trace the project's log level prints nothing, and the cost of a packet is bounded by
  the limits below. The ids of an honest session can still be seen by lowering the
  netfox log level. After this the 10,000 entry packet is refused in 0 ms with one
  warning.
- Identity packets (3), limits: a packet is refused (one warning per peer per second,
  nothing stored) when it is over `_MAX_ID_PACKET_BYTES` bytes, which is checked before
  it is read, or when it has more than `_MAX_ID_ENTRIES` entries. An honest client
  registers 4 pickup spots, 24 world object slots and for each of up to 5 bots the bot,
  Vitals, Arsenal, Gadgets and Input: 4 + 24 + 5 * 5 = 53 entries. The limit is twice
  that, 106 entries, and each entry may take 4 + 128 + 5 bytes (string length, a name of
  up to 128 bytes, a varuint), 14,522 bytes in all. Measured by recording every
  identity packet in `net_full`, `net_world_objects_join`, `net_smoke`, `net_rejoin`,
  `net_combat`, `net_world_objects` and `net_fire` (349 packets): the largest had 26
  entries in 893 bytes (an earlier run: 21 entries, 705 bytes), the longest name 37
  bytes, and none was refused. The limits are about 4 and 16 times what a real session
  sends. The numbers are this project's (netfox is used by this game only); another
  game with more nodes must raise `_HONEST_ID_COUNT`.
- Cost: none for an honest session.
- Test that fails without it: `netfox_host`. Part A: the 4 byte identity packet through
  the handler and through `deserialize` (without the cap in front) returns and registers
  nothing; a negative length, a name one byte longer than the bytes left, a valid entry
  followed by 3 bytes of the next, a valid entry followed by a 2 GB name, a valid entry
  followed by a name with no id, and an id still marked as continued in the last byte
  all register nothing; the same lengths give an empty string and null from the string
  and variant serializers, which read back what they wrote (and what `put_var` wrote);
  an array and a dictionary declaring 2^40 entries are empty in under 50 ms; a state
  packet and an input packet whose first property is a 2 GB variant in 4 bytes are
  handled and return; dense and sparse frames of size 200 (over the rest) and -1 are
  dropped with no engine error while a right-sized frame is merged; a raw packet that is
  the prefix alone, shorter, or without the prefix dispatches nothing and one with an
  index dispatches once. A crash cannot be asserted in a process: the test shows that
  the calls return, and the mutation table shows that each kills the process (exit 138)
  with its fix removed. Part C: 1000 unknown-command packets from one peer give one
  line in under 50 ms, a second peer gets its own, and the next line is logged after
  the interval; the same for 1000 tickrate mismatches; three identity packets of 10,000
  entries are refused in under 50 ms with one warning, no per-entry line and nothing
  stored; one of 200,000 entries (about 5 MB) is refused in under 50 ms; a packet of
  107 short names (under the byte limit) is refused for its count; a packet of 53
  entries and one with a 128 byte name are accepted with no per-entry line; the three
  per-peer tables hold the logged peers, lose a peer that leaves (a `peer_disconnected`
  signal is emitted), and are empty after the command server's `reset`, the
  handshake's `stop` and the identity server's `clear`, and after `NetworkTime.stop()`
  (last in the run, as it stops the clock).
- Tests for A2 (`netfox_host`, each asserting the engine's error lines, counted in process
  by an engine logger, as well as the time): one 14,000 byte bad name and 100 bad names
  of 128 bytes give 0 lines in under 50 ms; a name of 129 bytes and a name that is valid
  UTF-8 but not ASCII refuse the whole packet; a packet of 2,000 entries is read up to
  107 entries; a ping that is a 200,000 byte bad string, and a pong and a timestamp
  from the server that are bad strings, give 0 lines in under 50 ms; the size and type
  check passes an honest ping (also with a 64 bit index), pong and timestamp and fails
  the wrong type; a string property of 2,000 bad bytes in a state, a diff state and an
  input packet gives 0 lines; 25 fixed-size values (all the allowed types) round trip;
  10 string, name, path, container and packed values read as null and leave the buffer
  at its end; the value after a refused one is read in place; every property of the
  bot, world object and pickup scenes is of an allowed type and round trips; a
  dictionary of 5 entries in 9 bytes is refused and 4 in 8 are read; a variant that
  declares 2 GB and has a header and a value after it gives null; the identity limiter
  table is empty after `NetworkTime.stop()`.

### D. What is not fixed

This patch bounds the cost of a packet. It does not make the host safe against a peer
that sends a lot of packets. All three items of the list below must be dealt with
before strangers can join (a match of friends on one hotspot does not need them).
- Before strangers can join: any command or input flood at the network's own rate. There
  is no per-peer packet rate limit anywhere in the addon or in the game: a peer can send
  identity packets (each one now cheap but not free: parsed up to 14,522 bytes and 107
  entries), unknown commands, tickrate messages and input packets (up to 4,064 bytes
  and the frames in them, 225 or so frames of two values) as fast as ENet carries them,
  and the host spends its time reading them. The rate limited log lines bound the
  output, not the work.
- Before strangers can join: Godot's own `SceneMultiplayer` layer below netfox. A
  malformed remote call prints about a line, and the path strings of RPC and node-path
  caches may cost a line per invalid byte. This was not probed.
- Before strangers can join: the string schema of this addon (`_StringSerializer`)
  decodes UTF-8 and has the same cost per invalid byte (a line each); it is bounded by
  the packet size only and is not registered anywhere in this project, so it cannot be
  reached today. It must not be registered for peer input until it checks its bytes as
  the identity names do. The array and dictionary schemas are bounded by their counts
  only, with the same limit. A pong may still hold a string of about 30 bytes (from the
  server only).
- Every measurement is from a Mac debug build, headless. A phone host writing its log to
  the system log will be slower per line, and the CPU of a budget phone several times
  slower per call. Nothing here was measured on a device or over a real network.

### E. Every place peer bytes become text

Searched for in `addons/netfox`, `addons/netfox.internals` (there is no `netfox.extras`)
and `scripts/`: `get_string_from_utf8`, `get_string_from_ascii`, `get_string_from_utf16`,
`utf32`, `wchar`, `get_utf8_string`, `get_string`, `String(` and `str(` on decoded data,
`NodePath(`, `StringName(`, `bytes_to_var`, `get_var`, `JSON`, `Expression`, and every
`get_node`, `get_node_or_null`, `has_node`, `find_child` and `get_node_and_resource`.

| Site | Reachable from a peer | Cost per byte | Status |
|---|---|---|---|
| `network-schemas.gd` `_CStringSerializer.decode` (subject name in a snapshot frame) | yes, input, state and sync packets, unaccepted peers included | one error line | fixed, A3 |
| `identity-packet-serializer.gd` `deserialize` (names in an identity packet) | yes, command 0, any connected peer | one error line | fixed, A2: raw bytes judged, ASCII decode |
| `network-schemas.gd` `_VariantSerializer.decode` (strings, names, paths, containers inside a property) | yes, every property | one error line | fixed, A2: not decoded at all, skipped |
| `network-schemas.gd` `_StringSerializer.decode` | no, no schema is registered | one error line | not fixed, not reachable; Part D |
| `network-time-synchronizer.gd` `bytes_to_var` (ping, pong, timestamp) | yes, ping from any peer, pong and timestamp from the server only | one error line | fixed for ping and timestamp (exact size and type, A2); a pong can still hold a string of about 30 bytes, from the server only |
| `network-identity-server.gd` `_handle_ids` (names to `_get_identifier_by_name`) | yes | none: a dictionary lookup of a string that is at most 128 ASCII bytes | not needed |
| `network-identity-server.gd` `_resolve_reference` (name of a frame to `_get_identifier_by_name`) | yes, through A3 | none: a dictionary lookup of at most 128 ASCII bytes | not needed |
| the unknown-identity warning of patch 12 and the debug lines that print a name (`%s` of a reference) | yes | formatting at most 128 ASCII bytes, once a second a peer for the warning; the debug line is off at the project's log level | not needed |
| node-path lookups: `property-entry.gd` `root.get_node(NodePath(path))`, `editor-utils.gd`, `rollback-synchronizer`, scripts' `get_node("Vitals")`, `get_node("Input")`, `get_node_or_null("../Arena")`, `get_node("RollbackSynchronizer")` | no: the paths come from the scene and from the synchronisers' own property lists, never from a packet. A peer's name is only ever the key of `_identifier_by_name`, so it cannot select a node that was not registered with `register_node` (the synchronised ones) | none | not needed |
| `scripts/`: `str(ammo)`, `String(node.name)` (dev probe) | no, local values | none | not needed |
| `scripts/` RPCs (`session.gd`, `match_settings.gd`) | typed: no arguments, and one int (checked for the sender) | none | not needed |
| Godot's own `SceneMultiplayer`: RPC node paths, path cache, system messages | yes | possibly a line per invalid byte of a path | not probed, not fixed; Part D |

`get_string_from_ascii()` was probed with 15,000 bytes of 0xff: 0 lines, 0 ms (the UTF-8
decode of the same bytes: 15,000 lines, 126 ms), so a decode that judges the raw bytes
first and then uses the ASCII decoder never prints per byte.

## The diffs

The blocks below are the whole set, one per file.

`addons/netfox/network-time-synchronizer.gd`, carries patches 16, 2 and 7:

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
@@ -248,15 +250,52 @@
 
 		_offset = offset - nudge
 
+# PATCH (see addons/NETFOX_PATCHES.md): the payloads of the clock commands are
+# var_to_bytes of an int (ping), of an array of an int and two floats (pong) and of
+# a float (timestamp). Anything of another size or type is refused before it is
+# decoded: the engine prints an error line for every invalid UTF-8 byte of a string
+# variant, so a ping of 200,000 bad bytes cost 1.7 s and 200,000 lines. A ping and a
+# timestamp are one number, so their size is exactly 8 bytes, or 12 if the header has
+# the 64 bit flag (bit 16): any other size is a malformed variant, which prints a line
+# or two when decoded. A pong is an array, its size is at most the largest honest one:
+# a 4 byte header and a 4 byte count and, for each of its 3 elements, a 4 byte header
+# and 8 bytes.
+const _PONG_MAX_BYTES := 4 + 4 + 3 * (4 + 8)
+
+func _is_scalar_payload(data: PackedByteArray, type: int) -> bool:
+	if data.size() < 8:
+		return false
+	var header := data.decode_u32(0)
+	return (header & 0xff) == type and data.size() == (12 if header & 0x10000 else 8)
+
+func _is_pong_payload(data: PackedByteArray) -> bool:
+	return data.size() >= 8 and data.size() <= _PONG_MAX_BYTES and (data.decode_u32(0) & 0xff) == TYPE_ARRAY and (data.decode_u32(4) & 0x7fffffff) == 3
+
 func _handle_ping(sender: int, data: PackedByteArray) -> void:
-	var idx := bytes_to_var(data) as int
+	# PATCH: a malformed payload is not an index.
+	if not _is_scalar_payload(data, TYPE_INT):
+		return
+	var decoded: Variant = bytes_to_var(data)
+	if typeof(decoded) != TYPE_INT:
+		return
+
+	var idx := decoded as int
 	var ping_received := _clock.get_time()
 
 	_cmd_pong.send(var_to_bytes([idx, ping_received, _clock.get_time()]), sender)
 
 func _handle_pong(sender: int, data: PackedByteArray) -> void:
-	var args := bytes_to_var(data)
+	# PATCH (see addons/NETFOX_PATCHES.md): only the server answers pings.
+	if sender != SERVER_PEER_ID:
+		return
 
+	# PATCH: a pong is an array of an int and two floats, and nothing else
+	if not _is_pong_payload(data):
+		return
+	var args: Variant = bytes_to_var(data)
+	if typeof(args) != TYPE_ARRAY or (args as Array).size() != 3 or typeof(args[0]) != TYPE_INT or typeof(args[1]) != TYPE_FLOAT or typeof(args[2]) != TYPE_FLOAT:
+		return
+
 	var idx := args[0] as int
 	var ping_received := args[1] as float
 	var pong_sent := args[2] as float
@@ -296,6 +335,14 @@
 	_cmd_set_time.send(var_to_bytes(_clock.get_time()), sender)
 
 func _handle_set_timestamp(sender: int, data: PackedByteArray) -> void:
+	# PATCH (see addons/NETFOX_PATCHES.md): only the server may set our clock.
+	# Without this, any peer could set the host's reference clock.
+	if sender != SERVER_PEER_ID:
+		return
+
+	# PATCH: a timestamp is a float, and nothing else
+	if not _is_scalar_payload(data, TYPE_FLOAT):
+		return
 	var timestamp := bytes_to_var(data) as float
 
 	_logger.debug("Received initial timestamp @ %.4fs raw time", [_clock.get_raw_time()])
```

`addons/netfox/rollback/network-rollback.gd`, carries patches 9 and 15:

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
@@ -390,6 +397,12 @@
 	if _earliest_state >= 0 and _earliest_state <= _resim_from:
 		range_source = "latest state"
 		_resim_from = _earliest_state
+	# PATCH (see addons/NETFOX_PATCHES.md): nothing arrives when a hole in a subject's
+	# input expires, so go back to it here
+	var expired_hole := RollbackSimulationServer._get_earliest_expired_hole()
+	if expired_hole >= 0 and expired_hole <= _resim_from:
+		range_source = "expired input hole"
+		_resim_from = expired_hole
 	_resim_from = mini(_resim_from, NetworkTime.tick - 1)
 	_logger.trace("Simulating range @%d>@%d using %s", [_resim_from, NetworkTime.tick, range_source])
 
```

`addons/netfox/schemas/network-schemas.gd`, carries patches 16 and 5:

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
@@ -489,15 +489,66 @@
 	func encode(v: Variant, b: StreamPeerBuffer) -> void:
 		b.put_var(v, false)
 
+	# PATCH (see addons/NETFOX_PATCHES.md): two limits, for a decoder that reads what a
+	# peer sends.
+	# 1. get_var() allocates the length the packet declares before it checks the bytes
+	#    left, so 4 bytes declaring 2 GB kill the process. The length (a 32 bit field
+	#    before the value, as put_var writes it) is checked against the bytes left first.
+	# 2. The engine prints an error line for every invalid UTF-8 byte of a string, so a
+	#    string of 4,000 bad bytes in a state packet costs 4,000 lines. Only fixed-size
+	#    values are decoded: nil, bool, int, float and the math types and Color, which
+	#    carry no length and no string. Anything else, the strings, node paths,
+	#    containers and objects included, is skipped and read as null. A property of
+	#    such a type needs a registered schema with a bounded decoder of its own.
+	# 3. get_var itself prints error lines (two per value) for a header it does not know
+	#    or a body shorter than its type needs. The type must therefore be below
+	#    TYPE_COLOR + 1 (a shift by 64 or more wraps in GDScript, so the type 65 would
+	#    pass as the type 1), and the declared size must hold the header and the body
+	#    of that type, from the tables below. With these checks get_var fails on nothing
+	#    this decoder passes to it (probed for every allowed type, with and without the
+	#    64 bit flag). A declared size larger than the type needs is read in full and
+	#    the extra bytes are ignored, so the reader stays aligned.
+	# The checks read the 4 byte length and the 4 byte type header, then seek back and
+	# let get_var decode (which does not build objects with allow_objects false).
+	const _FIXED_SIZE_TYPES := ((1 << (TYPE_COLOR + 1)) - 1) & ~(1 << TYPE_STRING)
+	# Body bytes of each allowed type, indexed by type number, without the header's
+	# 64 bit flag (bit 16) and with it. The flag doubles int, float and the types made
+	# of floats; bool, the integer vectors and rects and Color ignore it. Only bit 16
+	# matters (probed: the other 15 flag bits change nothing). Index 4 (String) is unused.
+	const _BODY_BYTES := [0, 4, 4, 4, 0, 8, 8, 16, 16, 12, 12, 24, 16, 16, 16, 16, 24, 36, 48, 64, 16]
+	const _BODY_BYTES_64 := [0, 4, 8, 8, 0, 16, 8, 32, 16, 24, 12, 48, 32, 16, 32, 32, 48, 72, 96, 128, 16]
+
 	func decode(b: StreamPeerBuffer) -> Variant:
+		var start := b.get_position()
+		var left := b.get_available_bytes() - 4
+		if left < 4:
+			b.seek(start + b.get_available_bytes())
+			return null
+		var size := b.get_32()
+		if size < 4 or size > left:
+			b.seek(start + 4 + clampi(size, 0, left))
+			return null
+		var header := b.get_32()
+		var type := header & 0xff
+		if type > TYPE_COLOR or (_FIXED_SIZE_TYPES >> type) & 1 == 0 or size < 4 + (_BODY_BYTES_64[type] if header & 0x10000 else _BODY_BYTES[type]):
+			b.seek(start + 4 + size)
+			return null
+		b.seek(start)
 		return b.get_var(false)
 
 class _StringSerializer extends NetworkSchemaSerializer:
 	func encode(v: Variant, b: StreamPeerBuffer) -> void:
 		b.put_utf8_string(str(v))
 
+	# PATCH (see addons/NETFOX_PATCHES.md): the length is checked before it is read,
+	# as for the variant serializer above; a bad length gives an empty string
 	func decode(b: StreamPeerBuffer) -> Variant:
-		return b.get_utf8_string()
+		if b.get_available_bytes() < 4:
+			return ""
+		var size := b.get_32()
+		if size < 0 or size > b.get_available_bytes():
+			return ""
+		return (b.get_data(size)[1] as PackedByteArray).get_string_from_utf8()
 
 class _CStringSerializer extends NetworkSchemaSerializer:
 	static var instance := _CStringSerializer.new()
@@ -506,14 +557,29 @@
 		b.put_data(str(v).to_utf8_buffer())
 		b.put_u8(0)
 
+	# PATCH (see addons/NETFOX_PATCHES.md): the engine prints an error line for every
+	# invalid UTF-8 byte it decodes, and this decoder reads the name of a subject that a
+	# peer sends at the start of every frame of a snapshot (id 0 means "named by full
+	# name"), before anyone checks who the sender is. A name is now read up to its NUL
+	# in full, so the frame stays aligned, and used only if it is at most
+	# _IdentityPacketSerializer.MAX_NAME_BYTES long and ASCII, judged on the raw bytes
+	# before they are decoded. Otherwise, and when there is no NUL before the end of
+	# the buffer, the name is empty, which no subject has: the frame is skipped.
 	func decode(b: StreamPeerBuffer) -> Variant:
-		var data := PackedByteArray()
-		while b.get_available_bytes() > 0:
-			var c := b.get_u8()
-			if c == 0: break
-			data.append(c)
-
-		return data.get_string_from_utf8()
+		var raw := b.data_array
+		var start := b.get_position()
+		var end := raw.find(0, start)
+		if end < 0:
+			b.seek(raw.size())
+			return ""
+		b.seek(end + 1)
+		if end - start > _IdentityPacketSerializer.MAX_NAME_BYTES:
+			return ""
+		var name_bytes := raw.slice(start, end)
+		for byte in name_bytes:
+			if byte >= 0x80:
+				return ""
+		return name_bytes.get_string_from_ascii()
 
 class _BoolSerializer extends NetworkSchemaSerializer:
 	func encode(v: Variant, b: StreamPeerBuffer) -> void:
@@ -610,9 +676,19 @@
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
@@ -625,9 +701,9 @@
 
 			# Stop if no more data to read
 			if byte & 0x80 == 0:
-				break
+				return _Bitset.of_bools(bools)
 
-		return _Bitset.of_bools(bools)
+		return null
 
 class _Float16Serializer extends NetworkSchemaSerializer:
 	func encode(v: Variant, b: StreamPeerBuffer) -> void:
@@ -850,6 +926,10 @@
 		var array := []
 
 		var item_count = size.decode(b)
+		# PATCH (see addons/NETFOX_PATCHES.md): an item takes at least a byte, so a
+		# count over the bytes left is not honest, and would allocate and loop for it
+		if item_count < 0 or item_count > b.get_available_bytes():
+			return array
 		array.resize(item_count)
 		for i in item_count:
 			array[i] = component.decode(b)
@@ -879,6 +959,10 @@
 		var dictionary := {}
 
 		var size = size_serializer.decode(b)
+		# PATCH (see addons/NETFOX_PATCHES.md): an entry takes at least two bytes, so a
+		# count over half the bytes left is not honest, and would loop for it
+		if size < 0 or size > b.get_available_bytes() >> 1:
+			return dictionary
 		for i in size:
 			var key = key_serializer.decode(b)
 			var value = value_serializer.decode(b)
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

`addons/netfox/serializers/dense-snapshot-serializer.gd`, carries patches 16 and 12:

```diff
diff --git a/addons/netfox/serializers/dense-snapshot-serializer.gd b/addons/netfox/serializers/dense-snapshot-serializer.gd
--- a/addons/netfox/serializers/dense-snapshot-serializer.gd
+++ b/addons/netfox/serializers/dense-snapshot-serializer.gd
@@ -61,17 +61,29 @@
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
 		var node_data_size := varuint.decode(buffer) as int
+		# PATCH (see addons/NETFOX_PATCHES.md): a frame cannot be larger than the
+		# packet's rest; a negative size is an engine error for every such frame
+		if node_data_size < 0 or node_data_size > buffer.get_available_bytes():
+			break
 		node_buffer.data_array = buffer.get_partial_data(node_data_size)[1]
 
 		# Resolve to identifier
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

`addons/netfox/serializers/sparse-snapshot-serializer.gd`, carries patches 16, 5 and 12:

```diff
diff --git a/addons/netfox/serializers/sparse-snapshot-serializer.gd b/addons/netfox/serializers/sparse-snapshot-serializer.gd
--- a/addons/netfox/serializers/sparse-snapshot-serializer.gd
+++ b/addons/netfox/serializers/sparse-snapshot-serializer.gd
@@ -69,20 +69,34 @@
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
+		# PATCH (see addons/NETFOX_PATCHES.md): a frame cannot be larger than the
+		# packet's rest; a negative size is an engine error for every such frame
+		if node_data_size < 0 or node_data_size > buffer.get_available_bytes():
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

`addons/netfox/servers/network-history-server.gd`, carries patches 1, 3 (the server-only bound), 10, 13 and 15:

```diff
diff --git a/addons/netfox/servers/network-history-server.gd b/addons/netfox/servers/network-history-server.gd
--- a/addons/netfox/servers/network-history-server.gd
+++ b/addons/netfox/servers/network-history-server.gd
@@ -21,6 +21,15 @@
 
 var _ignored_subjects := _Set.new()
 
+# PATCH (see addons/NETFOX_PATCHES.md): peer to {host tick: input snapshots refused at that tick},
+# for the last second only; peer to the time of its last warning.
+var _input_refusals := {}
+var _input_refusal_limit := _PeerRateLimit.new()
+
+# PATCH (see addons/NETFOX_PATCHES.md): subjects that state from their authority
+# has been merged for in this session
+var _authoritative_subjects := _Set.new()
+
 # Source of truth for history
 var _rb_input_history := _PerObjectHistory.new(_rb_history_size)
 var _rb_state_history := _PerObjectHistory.new(_rb_history_size)
@@ -65,6 +74,8 @@
 	_rb_input_properties.erase_subject(node)
 	_sync_state_properties.erase_subject(node)
 
+	_authoritative_subjects.erase(node)
+
 	# Erase from per-object history
 	_rb_state_history.erase_subject(node)
 	_rb_input_history.erase_subject(node)
@@ -90,6 +101,9 @@
 	_sync_state_snapshots = _HistoryBuffer.new(_sync_history_size)
 
 	_ignored_subjects.clear()
+	_authoritative_subjects.clear()
+	_input_refusals.clear() # PATCH: see addons/NETFOX_PATCHES.md
+	_input_refusal_limit.clear()
 
 ## Do not record [param subject]
 ## [br][br]
@@ -134,6 +148,61 @@
 		return -1
 	else:
 		return tick - latest_input
+
+## Return true if [param subject] has state that came from its authority
+## [br][br]
+## On a peer that is not the authority, rollback and synchronized state of a
+## subject is predicted locally until the authority's state arrives. This is
+## true once any state received from the authority has been merged for
+## [param subject] in this session, and always true on the authority itself. It
+## is false again after [method _NetworkTime.stop], which calls [method reset].
+## [br][br]
+## [param subject] is a [Variant] so that a freed node can be passed and gives
+## [code]false[/code]: GDScript refuses a freed object for an [Object] parameter
+## before the function runs.
+func has_authoritative_state(subject: Variant) -> bool:
+	if not is_instance_valid(subject):
+		return false
+	if subject is Node and (subject as Node).is_multiplayer_authority():
+		return true
+	return _authoritative_subjects.has(subject)
+
+## How many input snapshots of [param peer] the server refused in the last second (as late
+## as it was refused, or before the peer's first input), or 0 on a client. Every input tick
+## travels in up to [member NetworkRollback.input_redundancy] packets, so a peer whose every
+## input is refused counts about that many per tick. A game can show "connection too slow"
+## from it. The count is erased when the peer leaves and cleared by [method reset].
+func get_recent_refused_input_count(peer: int) -> int:
+	var by_tick := _input_refusals.get(peer, {}) as Dictionary
+	var from := NetworkTime.tick - NetworkTime.tickrate
+	var count := 0
+	for tick: int in by_tick:
+		if tick > from:
+			count += by_tick[tick] as int
+	return count
+
+## Erase all data kept about [param peer]. Called when it leaves.
+func erase_peer(peer: int) -> void:
+	_input_refusals.erase(peer)
+	_input_refusal_limit.erase_peer(peer)
+
+func _note_refused_input(snapshot: _Snapshot, age: int) -> void:
+	_logger.trace("Refusing input @%d, %d ticks old", [snapshot.tick, age])
+	var peers := {}
+	for input in snapshot.get_subjects():
+		if input is Node:
+			peers[(input as Node).get_multiplayer_authority()] = true
+	var now := NetworkTime.tick
+	for peer: int in peers:
+		var by_tick := _input_refusals.get_or_add(peer, {}) as Dictionary
+		if not by_tick.has(now):
+			for tick: int in by_tick.keys():
+				if tick <= now - NetworkTime.tickrate:
+					by_tick.erase(tick)
+			by_tick[now] = 0
+		by_tick[now] = (by_tick[now] as int) + 1
+		if _input_refusal_limit.allow(peer):
+			_logger.warning("Refusing input @%d from peer #%d: %d ticks old at the host (the allowance is %d)", [snapshot.tick, peer, age, RollbackSimulationServer._get_hole_allowance()])
 
 ## Record currently registered rollback state properties for [param subject] at
 ## [param tick].
@@ -165,7 +234,7 @@
 	_record(tick, _rb_state_history, _rb_state_snapshots, _rb_state_properties, false, func(subject: Node):
 		if not subject.is_multiplayer_authority():
 			return false
-		if RollbackSimulationServer._is_predicting(input_snapshot, subject):
+		if RollbackSimulationServer._is_predicting(input_snapshot, subject, tick - 1):
 			return false
 		return true
 	)
@@ -194,23 +263,64 @@
 	return _sync_state_snapshots.get_at(tick)
 
 func _merge_rollback_input(snapshot: _Snapshot) -> bool:
+	# PATCH (see addons/NETFOX_PATCHES.md): a server stops waiting for the input of a tick
+	# after the input allowance; input stamped with a tick older than that is refused, so
+	# that what the host did with an expired tick is final. So is input for a tick before a
+	# subject's first input that the host has already passed (_is_start_decided). Logged at
+	# trace level, and as a warning at most once a second per peer (a peer can cause one
+	# refusal per snapshot); counted for get_recent_refused_input_count.
+	if multiplayer.is_server():
+		var age := NetworkTime.tick - snapshot.tick
+		if age > RollbackSimulationServer._get_hole_allowance() or RollbackSimulationServer._is_start_decided(snapshot):
+			_note_refused_input(snapshot, age)
+			return false
 	if not _can_merge_tick(snapshot.tick, _rb_input_history):
 		return false
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
@@ -296,6 +406,26 @@
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

`addons/netfox/servers/network-synchronization-server.gd`, carries patches 3, 4, 6, 10, 11, 14 and 15:

```diff
diff --git a/addons/netfox/servers/network-synchronization-server.gd b/addons/netfox/servers/network-synchronization-server.gd
--- a/addons/netfox/servers/network-synchronization-server.gd
+++ b/addons/netfox/servers/network-synchronization-server.gd
@@ -40,6 +40,8 @@
 var _input_redundancy := NetworkRollback.input_redundancy
 
 var _rb_sent_state_history := {} # peer to _HistoryBuffer of _Snapshot
+var _rb_last_full_tick := {} # PATCH: peer to (subject to tick of the last full state sent)
+var _last_size_warning_msec := {} # PATCH: peer to the time (msec) of its last oversized-packet warning
 
 var _last_sync_state_sent := _Snapshot.new(0)
 var _sync_enable_diffs := ProjectSettings.get_setting("netfox/state_synchronizer/enable_diff_states", true) as bool
@@ -132,6 +134,9 @@
 
 ## Deregister any and all settings associated with [param node]
 func deregister(node: Node) -> void:
+	for subjects: Dictionary in _rb_last_full_tick.values():
+		subjects.erase(node)
+
 	_rb_state_properties.erase_subject(node)
 	_rb_input_properties.erase_subject(node)
 	_rb_owned_state_properties.erase_subject(node)
@@ -149,6 +154,9 @@
 ## Called by default when a peer leaves
 func erase_peer(peer: int) -> void:
 	_rb_sent_state_history.erase(peer)
+	_rb_last_full_tick.erase(peer)
+	_last_size_warning_msec.erase(peer)
+	NetworkHistoryServer.erase_peer(peer) # PATCH: see addons/NETFOX_PATCHES.md
 
 ## Forget what was sent to other peers, while keeping the registered properties
 ## [br][br]
@@ -157,6 +165,8 @@
 ## [method _NetworkTime.stop].
 func reset() -> void:
 	_rb_sent_state_history.clear()
+	_rb_last_full_tick.clear()
+	_last_size_warning_msec.clear()
 	_last_sync_state_sent = _Snapshot.new(0)
 
 func _get_peer_rb_sent_history(peer: int) -> _HistoryBuffer:
@@ -164,25 +174,42 @@
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
@@ -269,43 +296,68 @@
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
+
+		var sent_subjects := full_subjects.duplicate()
+		if reference_snapshot != null:
 			var diff := _Snapshot.make_patch(reference_snapshot, peer_snapshot)
-			if diff.is_empty():
-				# Nothing changed, don't send anything
-				continue
+			for subject in full_subjects:
+				diff.erase_subject(subject)
 
-			var packets := _sparse_serializer.write_for(peer, diff, _rb_owned_state_properties)
-			for packet in packets:
-				_cmd_diff_state.send(packet, peer)
+			# Nothing changed, don't send anything
+			if not diff.is_empty():
+				var packets := _sparse_serializer.write_for(peer, diff, _rb_owned_state_properties)
+				for packet in packets:
+					_cmd_diff_state.send(packet, peer)
 
-			_remember_sent_rollback_state(peer, diff)
-			NetworkPerformance.push_full_state_props(peer_snapshot.size())
-			NetworkPerformance.push_sent_state_props(diff.size())
+				NetworkPerformance.push_full_state_props(peer_snapshot.size())
+				NetworkPerformance.push_sent_state_props(diff.size())
+				sent_subjects.append_array(diff.get_subjects())
 
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
@@ -391,7 +443,34 @@
 	elif is_instance_valid(multiplayer):
 		multiplayer.peer_disconnected.connect(erase_peer)
 
+# PATCH (see addons/NETFOX_PATCHES.md): who may send snapshots, and how big
+# they may be. On a client only the server sends snapshots, so anything else is
+# dropped. Packets are cut by PacketBuffer to max_sync_packet_size, so a packet
+# over the headroom below, per snapshot it may carry, is not honest.
+const _SERVER_PEER_ID := 1
+const _PACKET_SIZE_HEADROOM := 2
+const _SIZE_WARNING_INTERVAL_MSEC := 1000
+
+func _is_acceptable(sender: int, data: PackedByteArray, snapshots_per_packet: int) -> bool:
+	if not multiplayer.is_server() and sender != _SERVER_PEER_ID:
+		_logger.trace("Dropping snapshot packet from #%d, only the server sends them", [sender])
+		return false
+
+	# A size of zero or less means no limit, as in PacketBuffer
+	var limit := _max_packet_size * _PACKET_SIZE_HEADROOM * snapshots_per_packet
+	if _max_packet_size > 0 and data.size() > limit:
+		# At most one warning per peer per interval, so a peer cannot fill the log
+		var now := Time.get_ticks_msec()
+		if now - (_last_size_warning_msec.get(sender, -_SIZE_WARNING_INTERVAL_MSEC) as int) >= _SIZE_WARNING_INTERVAL_MSEC:
+			_last_size_warning_msec[sender] = now
+			_logger.warning("Dropping %d byte packet from #%d, over the limit of %d bytes (netfox/general/max_sync_packet_size)", [data.size(), sender, limit])
+		return false
+	return true
+
 func _handle_input(sender: int, data: PackedByteArray) -> void:
+	if not _is_acceptable(sender, data, _input_redundancy):
+		return
+
 	var buffer := StreamPeerBuffer.new()
 	buffer.data_array = data
 
@@ -399,12 +478,17 @@
 
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
 
@@ -413,37 +497,52 @@
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

`addons/netfox/servers/rollback-simulation-server.gd`, carries patch 15:

```diff
diff --git a/addons/netfox/servers/rollback-simulation-server.gd b/addons/netfox/servers/rollback-simulation-server.gd
--- a/addons/netfox/servers/rollback-simulation-server.gd
+++ b/addons/netfox/servers/rollback-simulation-server.gd
@@ -123,7 +123,7 @@
 
 	# Determine predicted nodes
 	for node in _callbacks.keys():
-		if _is_predicting(input_snapshot, node):
+		if _is_predicting(input_snapshot, node, tick):
 			_predicted_nodes.add(node)
 
 	# Run callbacks and clear group
@@ -171,11 +171,20 @@
 			# Don't simulate
 			continue
 
+		# PATCH (see addons/NETFOX_PATCHES.md): an owned node does not build on
+		# a state that is only a carry-over, see _starts_from_carry_over()
+		if input_snapshot.has_subjects(inputs, true) and _starts_from_carry_over(node, tick):
+			continue
+
 		result.append(node)
 
 	return result
 
-func _is_predicting(input_snapshot: _Snapshot, node: Node) -> bool:
+# PATCH (see addons/NETFOX_PATCHES.md): `tick` is the tick of the input snapshot, for when there
+# is no input snapshot at all for that tick
+func _is_predicting(input_snapshot: _Snapshot, node: Node, tick: int = -1) -> bool:
+	if input_snapshot:
+		tick = input_snapshot.tick
 	var input_nodes := [] as Array[Node]
 	input_nodes.assign(_input_graph.get_linked_to(node))
 
@@ -197,10 +206,112 @@
 		return false
 	if is_owned and not has_input:
 		# We own the node, node depends on input, we don't have data for input - predict
+		# PATCH (see addons/NETFOX_PATCHES.md): unless this is no hole, or the hole has
+		# expired; the node was not simulated, and its state carried over is then the state
+		# of record
+		if tick >= 0 and not is_prediction_enabled_for(node) and _is_hole_accepted(node, input_nodes, tick):
+			return false
 		return true
 	# We own the node and we have data for node's input - we're sure
+	# PATCH (see addons/NETFOX_PATCHES.md): but not if it starts from a carry-over
+	if tick >= 0 and _starts_from_carry_over(node, tick):
+		return true
 	return false
 
+# PATCH (see addons/NETFOX_PATCHES.md): true if `node`, which this peer owns, has a state
+# at `tick` that is only a carry-over: it was skipped on an earlier tick because its input
+# for that tick had not arrived, so its state at `tick` is the state before it, recorded as
+# not authoritative. Simulating from it, with the input of `tick`, would build a state
+# that is one or more steps behind and record it as authoritative.
+func _starts_from_carry_over(node: Node, tick: int) -> bool:
+	if not node.is_multiplayer_authority():
+		return false
+	var state_snapshot := NetworkHistoryServer._get_rollback_state_snapshot(tick)
+	return state_snapshot != null and state_snapshot.has_subject(node) and not state_snapshot.is_auth(node)
+
+# PATCH (see addons/NETFOX_PATCHES.md): the latest an honest input may arrive, as a multiple of
+# input_redundancy ticks counted on the host's own clock from the tick the input belongs to.
+# Later than that is the same as lost: the host stops waiting, the tick stands as one where
+# the subject did not act, and input for it that arrives afterwards is refused. It also
+# covers honest input that is merely late and in order (a stall delivers a run of packets at
+# once; what is older than the allowance in it is refused). 3 times 4 ticks is 12 ticks, 400 ms
+# at 30 ticks per second. A first guess, to be judged after the phone test.
+const _INPUT_ALLOWANCE_FACTOR := 3
+
+# PATCH (see addons/NETFOX_PATCHES.md): the input allowance in ticks (see above). After it
+# the tick is final: its hole is accepted (see _is_hole_accepted) and the host refuses input
+# stamped with it (see NetworkHistoryServer._merge_rollback_input).
+func _get_hole_allowance() -> int:
+	return _INPUT_ALLOWANCE_FACTOR * NetworkRollback.input_redundancy
+
+# PATCH (see addons/NETFOX_PATCHES.md): true if `node`, which this peer owns, was not
+# simulated on `tick` for lack of input and that is final, so that the state carried over
+# from `tick` is the state of record (the node did not act on that tick; no input is made up):
+#   - there is no input before `tick` and one after it: the subject started to send later,
+#     which is no hole; or
+#   - there is an input after `tick` and the host's own tick is more than
+#     _INPUT_ALLOWANCE_FACTOR times input_redundancy ticks past it: the hole expired.
+# It depends only on the input history and NetworkTime.tick, which does not change within a
+# rollback loop, so every pass over the tick gives the same answer.
+func _is_hole_accepted(node: Node, inputs: Array, tick: int) -> bool:
+	if not node.is_multiplayer_authority():
+		return false
+	if NetworkHistoryServer.get_latest_input_for(inputs, NetworkTime.tick + NetworkRollback.history_limit) <= tick:
+		return false
+	if NetworkHistoryServer.get_latest_input_for(inputs, tick) < 0:
+		return true
+	return NetworkTime.tick - tick > _get_hole_allowance()
+
+# PATCH (see addons/NETFOX_PATCHES.md): true if `snapshot` holds input for a tick that the host
+# has already decided had no input and no hole: nothing is held for the tick or before it, and
+# the state after the tick is a carry-over recorded as authoritative (see _is_hole_accepted, the
+# first case: a tick before a subject's first input). The host may have sent that state, so the
+# input is refused and the decision is final, like an expiry. It reads only the histories.
+func _is_start_decided(snapshot: _Snapshot) -> bool:
+	for input in snapshot.get_subjects():
+		for node in _input_graph.get_linked_from(input):
+			if not node.is_multiplayer_authority():
+				continue
+			if NetworkHistoryServer.get_latest_input_for(_input_graph.get_linked_to(node), snapshot.tick) >= 0:
+				continue
+			var state_snapshot := NetworkHistoryServer._get_rollback_state_snapshot(snapshot.tick + 1)
+			if state_snapshot != null and state_snapshot.has_subject(node) and state_snapshot.is_auth(node):
+				return true
+	return false
+
+# PATCH (see addons/NETFOX_PATCHES.md): the earliest tick whose input is missing, whose hole
+# is accepted (see above) and whose carried-over state is not yet the state of record, or -1.
+# Nothing arrives when a hole expires, and the first input of a subject arrives after the
+# ticks before it were passed, so NetworkRollback asks for this at the start of each loop
+# and re-simulates from there. Looked at once per input node of another peer, and only at the
+# ticks after the last authoritative state of the first node that input drives (the others
+# have the same chain), which is where such a hole can be.
+func _get_earliest_expired_hole() -> int:
+	var now := NetworkTime.tick
+	var oldest := maxi(NetworkRollback.history_start, 0)
+	for input: Node in _input_graph._links_from:
+		if input.is_multiplayer_authority():
+			continue
+		var nodes := _input_graph.get_linked_from(input)
+		var node := nodes[0] as Node
+		if not node.is_multiplayer_authority():
+			continue
+
+		# The states of the ticks of this loop are not recorded yet: start at the newest that is.
+		var first := now
+		while first > oldest:
+			var state_snapshot := NetworkHistoryServer._get_rollback_state_snapshot(first)
+			if state_snapshot != null and (not state_snapshot.has_subject(node) or state_snapshot.is_auth(node)):
+				break
+			first -= 1
+
+		var inputs := _input_graph.get_linked_to(node)
+		for tick in range(first, now):
+			var input_snapshot := NetworkHistoryServer._get_rollback_input_snapshot(tick)
+			if (input_snapshot == null or not input_snapshot.has_subject(input, true)) and _is_hole_accepted(node, inputs, tick) and _liveness_server.is_alive(node, tick):
+				return tick
+	return -1
+
 func _is_tick_fresh_for(node: Node, tick: int) -> bool:
 	if not _simulated_ticks.has(node):
 		return true
```

`addons/netfox.internals/peer-rate-limit.gd`, new file, carries patch 16:

```diff
diff --git a/addons/netfox.internals/peer-rate-limit.gd b/addons/netfox.internals/peer-rate-limit.gd
new file mode 100644
--- /dev/null
+++ b/addons/netfox.internals/peer-rate-limit.gd
@@ -0,0 +1,25 @@
+extends RefCounted
+class_name _PeerRateLimit
+
+# PATCH (see addons/NETFOX_PATCHES.md): lets a log line about what a peer sent
+# through at most once per interval per peer, the first one always, so a peer
+# cannot fill the log and spend the host's time on printing by repeating a bad
+# packet. A user of this class erases a peer when it leaves and clears on reset.
+
+const INTERVAL_MSEC := 1000
+
+var _last_msec := {} # peer to the time (msec) of its last line
+
+## True if a line about [param peer] may be logged now, and records that it was
+func allow(peer: int) -> bool:
+	var now := Time.get_ticks_msec()
+	if now - (_last_msec.get(peer, -INTERVAL_MSEC) as int) < INTERVAL_MSEC:
+		return false
+	_last_msec[peer] = now
+	return true
+
+func erase_peer(peer: int) -> void:
+	_last_msec.erase(peer)
+
+func clear() -> void:
+	_last_msec.clear()
```

`addons/netfox/network-time.gd`, carries patch 16:

```diff
diff --git a/addons/netfox/network-time.gd b/addons/netfox/network-time.gd
--- a/addons/netfox/network-time.gd
+++ b/addons/netfox/network-time.gd
@@ -482,6 +482,8 @@
 	NetworkHistoryServer.reset()
 	NetworkSynchronizationServer.reset()
 	RollbackSimulationServer.reset()
+	NetworkCommandServer.reset() # PATCH: see addons/NETFOX_PATCHES.md
+	NetworkIdentityServer.reset()
 
 	if multiplayer.peer_disconnected.is_connected(_handle_peer_disconnect):
 		multiplayer.peer_disconnected.disconnect(_handle_peer_disconnect)
```

`addons/netfox/serializers/identity-packet-serializer.gd`, carries patch 16:

```diff
diff --git a/addons/netfox/serializers/identity-packet-serializer.gd b/addons/netfox/serializers/identity-packet-serializer.gd
--- a/addons/netfox/serializers/identity-packet-serializer.gd
+++ b/addons/netfox/serializers/identity-packet-serializer.gd
@@ -5,6 +5,10 @@
 #
 # Used by NetworkIdentityServer, when sending local IDs to other peers
 
+# PATCH (see addons/NETFOX_PATCHES.md): the longest name an honest client sends, in
+# bytes. Names are node paths, which in this project are ASCII.
+const MAX_NAME_BYTES := 128
+
 # ids: Dictionary[full_name, local_id]
 func serialize(ids: Dictionary) -> PackedByteArray:
 	var buffer := StreamPeerBuffer.new()
@@ -19,16 +23,53 @@
 	return buffer.data_array
 
 # return: Dictionary[full_name, local_id]
-func deserialize(data: PackedByteArray) -> Dictionary:
+# PATCH: reads at most max_entries entries (all if max_entries is negative), so a
+# caller that refuses a packet of more than N entries passes N + 1.
+func deserialize(data: PackedByteArray, max_entries: int = -1) -> Dictionary:
 	var ids := {}
-	var varuint := NetworkSchemas.varuint()
 	var buffer := StreamPeerBuffer.new()
 	buffer.data_array = data
 
 	while buffer.get_available_bytes() > 0:
-		var full_name := buffer.get_utf8_string()
-		var id := varuint.decode(buffer) as int
+		if max_entries >= 0 and ids.size() >= max_entries:
+			break
+		# PATCH (see addons/NETFOX_PATCHES.md): get_utf8_string() allocates the length
+		# the packet declares before it checks the bytes left, so 4 bytes declaring 2 GB
+		# kill the process. Check the length first. A packet that is malformed or cut
+		# anywhere registers nothing, not the entries before the bad one.
+		if buffer.get_available_bytes() < 4:
+			return {}
+		var name_size := buffer.get_32()
+		if name_size < 0 or name_size > buffer.get_available_bytes():
+			return {}
+		# PATCH: the engine prints an error line for every invalid UTF-8 byte it decodes,
+		# so a name of 14,000 bytes of 0xff costs 14,000 lines and half a second. A name
+		# is refused, with its packet, if it is longer than MAX_NAME_BYTES or has a byte
+		# of 0x80 or more, judged on the raw bytes before they are decoded. Names are node
+		# paths and this project's are ASCII: a node named with other characters would
+		# not be synchronised.
+		if name_size > MAX_NAME_BYTES:
+			return {}
+		var raw := buffer.get_data(name_size)[1] as PackedByteArray
+		for byte in raw:
+			if byte >= 0x80:
+				return {}
+		var full_name := raw.get_string_from_ascii()
 
+		# The id is a varuint that must end inside the packet
+		var id := 0
+		var id_complete := false
+		for i in 10:
+			if buffer.get_available_bytes() == 0:
+				break
+			var byte := buffer.get_u8()
+			id += (byte & 0x7f) << (i * 7)
+			if byte & 0x80 == 0:
+				id_complete = true
+				break
+		if not id_complete:
+			return {}
+
 		ids[full_name] = id
 
 	return ids
```

`addons/netfox/servers/network-command-server.gd`, carries patch 16:

```diff
diff --git a/addons/netfox/servers/network-command-server.gd b/addons/netfox/servers/network-command-server.gd
--- a/addons/netfox/servers/network-command-server.gd
+++ b/addons/netfox/servers/network-command-server.gd
@@ -28,6 +28,8 @@
 
 var _use_raw := ProjectSettings.get_setting("netfox/general/use_raw_commands", false) as bool
 
+var _unknown_command_limit := _PeerRateLimit.new() # PATCH: see addons/NETFOX_PATCHES.md
+
 static var _logger := NetfoxLogger._for_netfox("NetworkCommandServer")
 
 ## Register a command at the next available ID
@@ -70,10 +72,22 @@
 func get_command_packet_prefix() -> PackedByteArray:
 	return _packet_prefix
 
+## Erase all data kept about [param peer]
+## [br][br]
+## Called by default when a peer leaves
+func erase_peer(peer: int) -> void:
+	_unknown_command_limit.erase_peer(peer)
+
+## Forget what is kept about peers, called by [method _NetworkTime.stop]
+func reset() -> void:
+	_unknown_command_limit.clear()
+
 func _handle_command(sender: int, idx: int, data: PackedByteArray) -> void:
 	var command := _commands.get(idx) as Command
 	if not command:
-		_logger.error("Received unknown command #%d!", [idx])
+		# PATCH: an unknown command is ignored, and logged at most once per second per peer
+		if _unknown_command_limit.allow(sender):
+			_logger.error("Received unknown command #%d from #%d!", [idx, sender])
 		return
 	command._handle(sender, data)
 
@@ -84,6 +98,12 @@
 	_rpc_transport.on_receive.connect(_handle_command)
 	_packet_transport.on_receive.connect(_handle_command)
 
+	# PATCH: forget peers that leave
+	if NetworkEvents.enabled:
+		NetworkEvents.on_peer_leave.connect(erase_peer)
+	elif is_instance_valid(multiplayer):
+		multiplayer.peer_disconnected.connect(erase_peer)
+
 ## Networked command
 ##
 ## Provides a convenient interface for sending and managing networked commands.
@@ -147,8 +167,9 @@
 		var buffer := StreamPeerBuffer.new()
 		buffer.data_array = packet
 
-		# Check header
-		if not is_command_packet(packet):
+		# Check header; PATCH (see addons/NETFOX_PATCHES.md): the command index byte
+		# must be there too, a bare prefix is not command 0
+		if not is_command_packet(packet) or packet.size() < _packet_prefix.size() + 1:
 			return
 
 		# Grab data
```

`addons/netfox/servers/network-identity-server.gd`, carries patch 16:

```diff
diff --git a/addons/netfox/servers/network-identity-server.gd b/addons/netfox/servers/network-identity-server.gd
--- a/addons/netfox/servers/network-identity-server.gd
+++ b/addons/netfox/servers/network-identity-server.gd
@@ -39,6 +39,24 @@
 
 const _WARN_QUEUE_SIZE := 128
 
+# PATCH (see addons/NETFOX_PATCHES.md): how big an identity packet may be. A peer
+# sends the identities of the nodes it has registered, and an honest client
+# registers a small, known number: 4 pickup spots, 24 world object slots, and for
+# each of up to 5 bots the bot, its Vitals, Arsenal, Gadgets and Input nodes.
+# That is 4 + 24 + 5 * 5 = 53 entries in total, and the largest packet seen in
+# the project's sessions (4 players, late joiners) had 26 entries in 893 bytes,
+# the longest name 37 bytes. The limits are twice the total count, and a name of
+# up to 128 bytes, so they are about 4 and 16 times what a real session sends.
+const _HONEST_ID_COUNT := 4 + 24 + 5 * 5
+const _ID_COUNT_HEADROOM := 2
+const _MAX_ID_ENTRIES := _HONEST_ID_COUNT * _ID_COUNT_HEADROOM
+# 4 bytes of string length, the name, and a varuint of at most 5 bytes
+const _MAX_ID_NAME_BYTES := _IdentityPacketSerializer.MAX_NAME_BYTES
+const _MAX_ID_ENTRY_BYTES := 4 + _MAX_ID_NAME_BYTES + 5
+const _MAX_ID_PACKET_BYTES := _MAX_ID_ENTRIES * _MAX_ID_ENTRY_BYTES
+
+var _refusal_limit := _PeerRateLimit.new() # PATCH: peer to the time of its last refusal warning
+
 func _init(p_command_server: _NetworkCommandServer = null) -> void:
 	_command_server = p_command_server
 
@@ -84,16 +102,22 @@
 	_logger.debug("Erasing data for peer #%d", [peer])
 
 	_push_queue.erase(peer)
+	_refusal_limit.erase_peer(peer)
 	_identifier_by_id.erase(peer)
 	for identifier in _identifiers.values():
 		(identifier as _NetworkIdentifier).erase_id_for(peer)
 
+## Forget what is kept about peers, called by [method _NetworkTime.stop]
+func reset() -> void:
+	_refusal_limit.clear()
+
 ## Clear all identities
 func clear() -> void:
 	_identifiers.clear()
 	_identifier_by_name.clear()
 	_identifier_by_id.clear()
 	_identifier_by_local_id.clear()
+	_refusal_limit.clear()
 	_next_id = 0
 
 ## Queue sending the numeric ID of [param node] to [param peer]
@@ -190,11 +214,25 @@
 			_identifier_by_id.erase(peer)
 
 func _handle_ids(sender: int, data: PackedByteArray) -> void:
-	var ids := _packet_serializer.deserialize(data)
+	# PATCH: a packet over the limits is refused before it is read, or after, if
+	# it is small but made of many short names; logged at most once per second per peer
+	# A packet that is cut, has a name over _MAX_ID_NAME_BYTES or a byte of 0x80 or more in
+	# a name reads as no entries at all
+	var ids := {}
+	if data.size() <= _MAX_ID_PACKET_BYTES:
+		ids = _packet_serializer.deserialize(data, _MAX_ID_ENTRIES + 1)
+	if data.size() > _MAX_ID_PACKET_BYTES or ids.size() > _MAX_ID_ENTRIES or (ids.is_empty() and not data.is_empty()):
+		if _refusal_limit.allow(sender):
+			_logger.warning("Refusing identity packet of %d bytes from #%d, over the limit of %d bytes or %d entries, or malformed, or a name over %d bytes or not ASCII", [data.size(), sender, _MAX_ID_PACKET_BYTES, _MAX_ID_ENTRIES, _MAX_ID_NAME_BYTES])
+		return
 
+	# PATCH: one line per packet, and one per entry only at trace level (it was
+	# one INFO line per entry), so the cost of a packet is bounded by the limits above
+	_logger.debug("Received %d IDs from #%d", [ids.size(), sender])
+
 	for full_name in ids:
 		var id := ids[full_name] as int
-		_logger.info("Received ID #%d for %s from #%d", [id, full_name, sender])
+		_logger.trace("Received ID #%d for %s from #%d", [id, full_name, sender])
 		var identifier := _get_identifier_by_name(full_name)
 		if not identifier:
 			# Deleted since then
```

`addons/netfox/time/network-tickrate-handshake.gd`, carries patch 16:

```diff
diff --git a/addons/netfox/time/network-tickrate-handshake.gd b/addons/netfox/time/network-tickrate-handshake.gd
--- a/addons/netfox/time/network-tickrate-handshake.gd
+++ b/addons/netfox/time/network-tickrate-handshake.gd
@@ -27,6 +27,8 @@
 ## Defaults to [constant WARN], based on project settings.
 var mismatch_action: int = ProjectSettings.get_setting(&"netfox/time/tickrate_mismatch_action", WARN)
 
+var _mismatch_warning_limit := _PeerRateLimit.new() # PATCH: see addons/NETFOX_PATCHES.md
+
 static var _logger := NetfoxLogger._for_netfox("NetworkTickrateHandshake")
 
 ## Emitted when a tickrate mismatch is encountered, and [member mismatch_action] is set to
@@ -40,6 +42,10 @@
 ## [br][br]
 ## Called by [_NetworkTime], no need to call manually.
 func run() -> void:
+	# PATCH: forget peers that leave
+	if not multiplayer.peer_disconnected.is_connected(erase_peer):
+		multiplayer.peer_disconnected.connect(erase_peer)
+
 	if _is_authority():
 		# Broadcast tickrate
 		_submit_tickrate.rpc(NetworkTime.tickrate)
@@ -56,7 +62,16 @@
 func stop() -> void:
 	if multiplayer.peer_connected.is_connected(_handle_new_peer):
 		multiplayer.peer_connected.disconnect(_handle_new_peer)
+	if multiplayer.peer_disconnected.is_connected(erase_peer):
+		multiplayer.peer_disconnected.disconnect(erase_peer)
+	_mismatch_warning_limit.clear()
 
+## Erase all data kept about [param peer]
+## [br][br]
+## Called when a peer leaves, no need to call manually.
+func erase_peer(peer: int) -> void:
+	_mismatch_warning_limit.erase_peer(peer)
+
 func _ready() -> void:
 	name = "NetworkTickrateHandshake"
 
@@ -67,12 +82,14 @@
 func _handle_tickrate_mismatch(peer: int, tickrate: int) -> void:
 	match mismatch_action:
 		WARN:
-			_logger.warning(
-				"Local tickrate %dtps differs from tickrate of peer #%d at %dtps! " +
-				"Make sure that tickrates are correctly configured in the Project settings! " +
-				"See netfox/Time/Tickrate.", [
-					NetworkTime.tickrate, peer, tickrate
-				])
+			# PATCH: logged at most once per second per peer, the packet is handled as before
+			if _mismatch_warning_limit.allow(peer):
+				_logger.warning(
+					"Local tickrate %dtps differs from tickrate of peer #%d at %dtps! " +
+					"Make sure that tickrates are correctly configured in the Project settings! " +
+					"See netfox/Time/Tickrate.", [
+						NetworkTime.tickrate, peer, tickrate
+					])
 		DISCONNECT:
 			if _is_authority():
 				_logger.warning("Peer #%d's tickrate of %dtps differs from expected %dtps! Disconnecting.", [
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
| 10 | `_handle_diff_state` does not pass `is_diff` (diffs not completed) | netfox_diffs | FAIL, 4 checks (a=2, b=99 where the host has b=1) |
| 10 | `_handle_diff_sync` does not pass `is_diff` | netfox_diffs | FAIL, sync diff stored without b |
| 10 | `is_diff` gate removed, rollback state (completion on full states too) | netfox_diffs | FAIL, a merge not marked as a diff was completed |
| 10 | `is_diff` gate removed, sync state | netfox_diffs | FAIL, a sync merge not marked as a diff was completed (a check added for it; the mutation survived the first version of the test) |
| 10 | per-subject reference (latest record, not latest record holding the subject) | full_state_coverage | FAIL, the diff after a re-simulation is not what the client needs |
| 11 | the periodic per-subject full state | full_state_coverage | FAIL, 1 full state in 120 ticks for A and B, longest gap 69 for C |
| 11 | same | host_diffs | FAIL, the client bot gets 1 full state in 209 ticks |
| 12 | the unknown-frame cap | netfox_host | FAIL, the frames after the cap are read |
| 12 | the warning rate limit | netfox_host | FAIL, 6 and 4 warnings (at most 1) |
| 13 | `_mark_authoritative` removed from the rollback state merge | netfox_diffs | FAIL, not true after the first received state, nor after a restart |
| 13 | `_mark_authoritative` removed from the sync state merge | netfox_diffs | FAIL, a received synchronized state does not set it |
| 13 | the clear in `reset()` | netfox_diffs | FAIL, still true after `NetworkTime.stop()` |
| 13 | the erase in `deregister()` | netfox_diffs | FAIL, still true after `deregister(node)` (check added; the first version of the test had none) |
| 13 | the authority shortcut | netfox_host | FAIL, false for a subject the host owns |
| 13 | marking before the `_can_merge_tick` check | netfox_diffs | FAIL, a refused tick set it (check added) |
| 13 | marking before sanitising (`_ingest_state`) | netfox_host | FAIL, state from peer 2 for a subject peer 3 owns set it (check added) |
| 13 | the `is_instance_valid` guard | not run | the check for a freed subject exists; the mutation was not run because of the risk that `is` on a freed object hangs |
| 11 | filter skipped always (also when only some subjects are full) | full_state_coverage | FAIL, 14 full states for A (at most 7; a bound added for this) |
| 11 | filter never skipped (the optimisation removed) | full_state_coverage | PASSES, by design: the result is the same, only the work differs, so no test can fail |
| 14 | the rate limit (a warning for every packet) | netfox_host | FAIL, 1000 warnings for 1000 packets (exactly 1), and 5 more checks that count warnings |
| 14 | the drop (warn, then accept the packet) | netfox_host | FAIL, the padded state packet is merged, and the padded input check of patch 6 |
| 14 | the erase in `erase_peer` and the clear in `reset` | netfox_host | FAIL, 4 checks (no warning after the peer is erased or after a reset, 3 peers kept) |
| 15 | skip: the carry-over test always false (rule 1 off) | hole_rule | FAIL, 5 checks (4 ticks simulated from the stale start state; authoritative states while the hole is open) |
| 15 | same | late_input | FAIL, 7 states sent and replaced (up to 16.6 px); the client showed its own bot wrong |
| 15 | `_is_predicting` ignores the carry-over (state recorded authoritative) | hole_rule | FAIL, 6 checks (3 ticks simulated from the stale start state; authoritative states while the hole is open) |
| 15 | node simulated although it starts from a carry-over (`_get_nodes_to_simulate` check removed) | hole_rule | FAIL, 2 checks (4 ticks simulated from the stale start state) |
| 15 | expiry: never expires | hole_rule | FAIL, 3 checks (the carried-over state is not the state of record; the subject does not go on) |
| 15 | same | lost_input | FAIL, the bot stood still on the host for 19 ticks (more than 15); host and client differ after the hole |
| 15 | same | pause_input | FAIL, host and client still differ past the bound; the client's wrong display is not bounded |
| 15 | allowance factor 2 instead of 3 | hole_rule | FAIL, the allowance is not 3 times input_redundancy |
| 15 | same | late_input | FAIL, the straggler arrived 8 ticks after its tick, within 2 of the allowance (boundary check) |
| 15 | allowance factor 0 (input older than the host's tick refused) | host_hitch | FAIL, 5 client input ticks lost at the 400 ms freeze |
| 15 | start: a tick with no input before it counts as a hole | hole_rule | FAIL, 2 checks (not simulated on its first input tick; the ticks before it are not authoritative) |
| 15 | same | late_input | PASSES: the one-process test catches it, the two-process run has no tick before the first input that matters |
| 15 | `_record_rollback_state` does not pass the tick to `_is_predicting` | hole_rule | PASSES: the tick only matters for a tick on which no subject at all has an input, which the host never has (its own bot has one every tick); kept for that case, no test reaches it |
| 15 | `_rollback` does not go back to an expired hole (`_get_earliest_expired_hole` not used) | hole_rule | FAIL, 2 checks (the carry-over never becomes the state of record) |
| 15 | same | lost_input | FAIL, the bot stood still for 20 ticks (more than 16); host and client differ after the hole |
| 15 | audit: late input is not refused | hole_rule | FAIL, 5 checks (the straggler after the expiry is simulated; exactly A + 1 ticks old is accepted; the stream causes simulation of old ticks) |
| 15 | same | late_input_refused | FAIL, 3 checks (every input arrived, no refused tick; the wrong display is not bounded) |
| 15 | audit: exactly the allowance is refused (`>=` for `>`) | hole_rule | FAIL, input exactly 12 ticks old is not accepted |
| 15 | audit: one tick more accepted (A + 1) | hole_rule | FAIL, 2 checks (13 ticks old accepted; 1 old tick simulated by the stream) |
| 15 | audit: the refusal logged as a warning | hole_rule | FAIL, 96 log lines above trace level for the stream (0 expected) |
| 15 | the carry-over test also applied to nodes this peer does not own (authority test removed) | net_smoke | PASSES: the check is defensive; no behaviour difference found (the first version of this patch failed it) |
| 15 | start: input for a tick before the first accepted input is not refused (`_is_start_decided` not used) | hole_rule | FAIL, 2 checks (the first inputs are accepted and simulated after the states of those ticks were sent) |
| 15 | start: refused whatever the state after the tick is (authority of the state not required) | hole_rule | FAIL, 2 checks (an ordinary first input after the host passed its tick is refused) |
| 15 | same | late_input | FAIL, the hold made no hole and the client showed its own bot wrong (the first inputs of the session are refused) |
| 15 | start: refused even when an input is held before the tick (`>= 0` guard removed) | hole_rule | PASSES, an equivalent mutation: with an earlier input held and an authoritative state after the tick, the input is a repeat of one held (redundancy) or older than the allowance, which is refused anyway |
| 15 | visibility: the warning is not rate limited | hole_rule | FAIL, 100 log lines for two peers (4 expected) |
| 15 | visibility: the warning is never logged | silent_peer | FAIL, 0 warnings about the refused peer (1 to 14 expected) |
| 15 | visibility: the count keeps old refusals (no one second window) | hole_rule | FAIL, the count is not 0 a second later |
| 15 | visibility: the count is not erased when the peer leaves | hole_rule | FAIL, the count is not erased when the peer leaves |
| 15 | visibility: the count is not cleared on reset | hole_rule | FAIL, the count is not cleared by reset |
| 15 | visibility: refusals are not counted | hole_rule | FAIL, 4 checks (nothing counted for the peer) |
| 15 | audit: late input is not refused | silent_peer | FAIL, 3 checks (235 inputs stored, the bot simulated on 235 ticks, no refusals counted) |
| 16 | the identity serializer back to the unpatched one (`get_utf8_string`) | netfox_host | process killed, exit 138 (SIGBUS), on the first call: the 4 byte identity packet |
| 16 | the variant serializer back to `get_var(false)` | netfox_host | process killed, exit 138, on the first 2 GB variant |
| 16 | the header type bound (`type > TYPE_COLOR`) | netfox_host | FAIL, the header types 64 to 129 pass the wrapped shift (SCRIPT ERROR x5, the table has no such index) and 5 of the 9 bad types are not refused |
| 16 | the declared size against the body size of the type | netfox_host | FAIL, 2 checks: 76 engine errors for the short values of the 40 type forms, and 1,124 engine errors, 52 ms, for a packet of values with no body |
| 16 | the 64 bit column of the size table (the flag ignored) | netfox_host | FAIL, 26 engine errors for the flagged short values |
| 16 | the exact size of a ping and a timestamp | netfox_host | FAIL, 3 engine errors (and a SCRIPT ERROR, a malformed float cast) for the 8 bytes with the flag and the 12 bytes without it |
| 16 | the element count of a pong | netfox_host | FAIL, a pong of 2 elements passes the check |
| 16 | the name decoder back to the unpatched one (UTF-8, no length or byte check) | netfox_host | FAIL, 7 checks: 1,011 lines for each 1,016 byte packet (9 to 12 ms), 4,051 lines and 36 ms for the 4,058 byte input packet, 9 lines for 33 frames with short bad names |
| 16 | the name's byte check (0x80 and over; the length check remains) | netfox_host | FAIL, 2 checks: 9 lines for 33 frames with short bad names (the floods are caught by the length check) |
| 16 | the name's length check (the byte check remains) | netfox_host | FAIL, the direct decoder test: a name of 129 bytes is read in full (the floods are caught by the byte check; a long valid name costs no lines, only time) |
| 16 | consuming the name to its NUL | netfox_host | FAIL, 7 checks: the frame after a refused name is misread, and the control diff state and diff sync merges and the frame size checks fail |
| 16 | a name with no NUL is empty | netfox_host | FAIL, 6 checks: the 0xff flood without a NUL costs an engine error line in each packet kind |
| 16 | the variant length check (`size > left`; the 4 byte packets still stop at the earlier size check) | netfox_host | process killed, exit 138, on a 2 GB length followed by a header and a value (a check was added for it; the mutation survived the first version of the test) |
| 16 | the string serializer back to `get_utf8_string()` | netfox_host | process killed, exit 138 |
| 16 | the array count check | netfox_host | SCRIPT ERROR x2 (the resize of 2^40 items; scene exits 0, `run_all.sh` fails) |
| 16 | the dictionary count check | netfox_host | hang in a loop of 2^40 iterations, killed after 90 s |
| 16 | the dictionary count against half the bytes left (compared with the bytes left) | netfox_host | FAIL, a dictionary of 5 entries in 9 bytes is read |
| 16 | the identity serializer keeps the entries before a bad one (the reviewer's `break`) | netfox_host | FAIL, a valid entry then a 2 GB name registered the first entry |
| 16 | the identity id must end inside the packet | netfox_host | FAIL, 2 checks (a cut id was stored) |
| 16 | the identity name decoded as UTF-8, no length or byte check (before A2) | netfox_host | FAIL, 4 checks: 14,000 lines and 136 ms for one 14,000 byte name, 12,800 lines for 100 names of 128 bytes |
| 16 | the identity name's byte check (0x80 and over) | netfox_host | FAIL, 2 checks: a name that is valid UTF-8 but not ASCII is accepted, and 12,800 lines for 100 bad names of 128 bytes |
| 16 | the identity name length check (over 128 bytes) | netfox_host | FAIL, a name of 129 bytes is accepted |
| 16 | the identity entry limit while reading (`_MAX_ID_ENTRIES + 1`) | netfox_host | FAIL, a packet of 2,000 entries is read in full |
| 16 | a non-empty packet that reads as no entries is not refused | netfox_host | FAIL, the identity limiter table is empty before `NetworkTime.stop()` (the 4 byte packet is no longer logged) |
| 16 | the ping size and type check | netfox_host | FAIL, 200,000 lines and 1.8 s for one ping |
| 16 | the pong size and type check | netfox_host | FAIL, 200,000 lines and 1.8 s for one pong |
| 16 | the timestamp size and type check | netfox_host | FAIL, 200,000 lines and 1.8 s, and a SCRIPT ERROR (a string cast to a float) |
| 16 | the variant type allow-list | netfox_host | FAIL, 3 checks: 2,000 lines and 19 ms for a string property, none of the 10 non-fixed values is skipped, the value after a refused one is misread |
| 16 | the dense frame size check | netfox_host | FAIL, the dense check (1 engine error for size -1; a frame over the rest read from what remained) and, as the error count carries over, the sparse check |
| 16 | the sparse frame size check | netfox_host | FAIL, the sparse check (the frame over the rest is merged, or 1 engine error for size -1) |
| 16 | the command index byte required | netfox_host | FAIL, 4 checks (the bare prefix dispatched command 0 with no data) |
| 16 | the unknown-command limit | netfox_host | FAIL, 1000 lines for 1000 packets and 5 more checks |
| 16 | the tickrate limit | netfox_host | FAIL, 1000 lines for 1000 packets and 5 more checks |
| 16 | the byte limit's early refusal (the packet is always read) | netfox_host | FAIL, a 5.7 MB packet takes 158 ms to refuse (limit 50) |
| 16 | the byte limit (only the entry count refuses) | netfox_host | FAIL, 4 checks (a 10,000 entry packet is not refused as a whole) |
| 16 | the entry count limit | netfox_host | FAIL, a 107 entry packet under the byte limit is accepted |
| 16 | the identity refusal rate limit | netfox_host | FAIL, 3 lines for 3 packets and 4 more checks |
| 16 | the per-entry line back at INFO | netfox_host | FAIL, 53 per-entry lines for one honest packet |
| 16 | the command server's erase on leave | netfox_host | FAIL, the peer is still in the table after it left |
| 16 | the handshake's erase on leave | netfox_host | FAIL, the peer is still in the table after it left |
| 16 | the identity server's erase in `erase_peer` | netfox_host | FAIL, the peer is still in the table after it left |
| 16 | the command server's `reset` clears nothing | netfox_host | FAIL, 2 checks (after `reset`, after `NetworkTime.stop()`) |
| 16 | the call to the command server's `reset` in `NetworkTime.stop()` | netfox_host | FAIL, 1 table entry left after `NetworkTime.stop()` |
| 16 | the call to the identity server's `reset` in `NetworkTime.stop()` | netfox_host | FAIL, 6 entries left in the identity table after `NetworkTime.stop()` |
| 16 | the identity server's `reset` clears nothing | netfox_host | FAIL, the same |
| 16 | the handshake's clear in `stop` | netfox_host | FAIL, 2 checks (after `stop`, after `NetworkTime.stop()`) |
| 16 | the identity server's clear in `clear` | netfox_host | FAIL, 1 entry left after `clear()` |
| 16 | the unknown-command, tickrate and identity limits together (the unpatched files of `main`) | netfox_host | FAIL, 1000 lines for 1000 packets for both, 52 and 55 ms (limit 50); the identity checks stop at a SCRIPT ERROR because the limit constants do not exist |
