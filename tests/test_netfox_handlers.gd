extends Node
## Calls netfox's five synchronisation handlers (input, full and diff state,
## full and diff sync), its clock ping handler and its identity table with
## chosen senders, ticks and bytes, and checks what the shared history buffers
## and the process do. Run once as a host and once as a client:
##   godot --headless --path . res://tests/test_netfox_handlers.tscn -- --mode=host --port=N
##   godot --headless --path . res://tests/test_netfox_handlers.tscn -- --mode=client --port=N
## Host mode serves on the port. Client mode connects to the port with nothing
## listening, so it stays a client with its tick at 0, which is the case of a
## client whose clock has not caught up. Exits 0 when all checks pass, 1
## otherwise (also on timeout). Script errors in netfox code show up as
## SCRIPT ERROR in the output and fail tests/run_all.sh.

const Probe: GDScript = preload("res://tests/netfox_probe.gd")
const TIMEOUT_SECONDS: float = 40.0
const SOCKET_BACKLOG_PEERS: int = 4
## A hostile packet must be handled in far less than this; honest handling takes
## well under a millisecond.
const TIME_BOUND_MSEC: int = 50
const BIG_PACKET_BYTES: int = 65536
const HUGE_BITS_BYTES: int = 1000000
const OTHER_PEER: int = 2
const THIRD_PEER: int = 3
const SERVER_PEER: int = 1

## Counts the warnings the engine reports that mention unknown identities
## (count) and those that report a dropped oversized packet (dropped).
class WarningCounter extends Logger:
	var count: int = 0
	var dropped: int = 0

	func _log_error(_function: String, _file: String, _line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != Logger.ERROR_TYPE_WARNING:
			return
		if "unknown identity" in code or "unknown identity" in rationale:
			count += 1
		if "Dropping" in code or "Dropping" in rationale:
			dropped += 1

	func _log_message(_message: String, _error: bool) -> void:
		pass

var _probe: Node = null
var _warnings: WarningCounter = WarningCounter.new()
var _failures: int = 0
var _sync: _NetworkSynchronizationServer = null
var _history: _NetworkHistoryServer = null

func _ready() -> void:
	get_tree().create_timer(TIMEOUT_SECONDS).timeout.connect(_on_timeout)
	_run()

func _on_timeout() -> void:
	print("FAIL timeout, test did not finish")
	get_tree().quit(1)

func _check(ok: bool, label: String) -> void:
	if ok:
		print("PASS ", label)
	else:
		_failures += 1
		print("FAIL ", label)

func _has_input(tick: int) -> bool:
	return _history._rb_input_snapshots.has_at(tick)

func _has_state(tick: int) -> bool:
	return _history._rb_state_snapshots.has_at(tick)

func _has_sync(tick: int) -> bool:
	return _history._sync_state_snapshots.has_at(tick)

## Time a callable in milliseconds.
func _msec(work: Callable) -> int:
	var start: int = Time.get_ticks_msec()
	work.call()
	return Time.get_ticks_msec() - start

func _run() -> void:
	var mode: String = "host"
	var port: int = 0
	for arg: String in OS.get_cmdline_user_args():
		match arg.get_slice("=", 0):
			"--mode":
				mode = arg.get_slice("=", 1)
			"--port":
				port = arg.get_slice("=", 1).to_int()
	_sync = NetworkSynchronizationServer
	_history = NetworkHistoryServer
	OS.add_logger(_warnings)

	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var err: Error = peer.create_server(port, SOCKET_BACKLOG_PEERS) if mode == "host" else peer.create_client("127.0.0.1", port)
	if err != OK:
		print("FAIL could not create the %s peer: %s" % [mode, error_string(err)])
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	_probe = Probe.new()
	add_child(_probe)
	_probe.register()
	if mode == "host":
		while NetworkTime.tick < 5:
			await get_tree().process_frame
		_check(multiplayer.is_server(), "running as a host")
		_check(NetworkHistoryServer.has_authoritative_state(_probe), "host: a subject it owns has authoritative state at once")
		_host_checks()
		_unknown_identity_checks()
		_no_limit_checks()
		await _size_warning_checks()
	else:
		await get_tree().process_frame
		_check(not multiplayer.is_server(), "running as a client")
		_check(NetworkTime.tick < 5, "client tick is still at the start (%d)" % NetworkTime.tick)
		_client_checks()
	_identity_and_ping_checks()

	print("%d failures" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)

# A host. Packets from clients must be validated and must not move the shared
# buffers unless they carry something the sender owns.
func _host_checks() -> void:
	var ahead: int = NetworkTime.tick + 3

	# Honest packets are merged, so the checks below can fail for the right reason.
	_probe.set_multiplayer_authority(OTHER_PEER)
	_sync._handle_input(OTHER_PEER, _probe.input_packet(ahead, 7))
	_check(_has_input(ahead), "control: input from the owner is merged")
	_sync._handle_full_state(OTHER_PEER, _probe.full_state_packet(ahead, 7))
	_check(_has_state(ahead), "control: full state from the owner is merged")
	_sync._handle_diff_state(OTHER_PEER, _probe.diff_state_packet(ahead + 1, 7))
	_check(_has_state(ahead + 1), "control: diff state from the owner is merged")
	_sync._handle_full_sync(OTHER_PEER, _probe.full_sync_packet(ahead, 7))
	_check(_has_sync(ahead), "control: full sync from the owner is merged")
	_sync._handle_diff_sync(OTHER_PEER, _probe.diff_sync_packet(ahead + 1, 7))
	_check(_has_sync(ahead + 1), "control: diff sync from the owner is merged")

	# Item 3: a sender that owns nothing in the packet changes nothing.
	_probe.set_multiplayer_authority(THIRD_PEER)
	var snapshot: _Snapshot = _probe.snapshot_at(ahead, 1)
	snapshot.sanitize(OTHER_PEER)
	_check(snapshot.is_empty() and not snapshot.is_auth(_probe) and snapshot.get_auth_subjects().is_empty(), "sanitize removes a foreign subject and its auth mark")
	var tick: int = NetworkTime.tick + 6
	_sync._handle_input(OTHER_PEER, _probe.input_packet(tick, 9))
	_check(not _has_input(tick), "input that is empty after sanitising is not merged")
	_sync._handle_full_state(OTHER_PEER, _probe.full_state_packet(tick, 9))
	_check(not _has_state(tick), "full state that is empty after sanitising is not merged")
	_sync._handle_diff_state(OTHER_PEER, _probe.diff_state_packet(tick, 9))
	_check(not _has_state(tick), "diff state that is empty after sanitising is not merged")
	_sync._handle_full_sync(OTHER_PEER, _probe.full_sync_packet(tick, 9))
	_check(not _has_sync(tick), "full sync that is empty after sanitising is not merged")
	_sync._handle_diff_sync(OTHER_PEER, _probe.diff_sync_packet(tick, 9))
	_check(not _has_sync(tick), "diff sync that is empty after sanitising is not merged")

	# The public query only follows what sanitising let through: a subject owned by
	# peer 3 is not authoritative here (the host owns neither) after a packet for it
	# from peer 2, and is after one from peer 3.
	var other: Node = Probe.new()
	add_child(other)
	other.register("OwnedByThirdPeer")
	other.set_multiplayer_authority(THIRD_PEER)
	var query_tick: int = NetworkTime.tick + 4
	_sync._handle_full_state(OTHER_PEER, other.full_state_packet(query_tick, 1))
	_check(not NetworkHistoryServer.has_authoritative_state(other), "host: state from peer 2 for a subject peer 3 owns does not set the query")
	_sync._handle_full_state(THIRD_PEER, other.full_state_packet(query_tick + 1, 1))
	_check(NetworkHistoryServer.has_authoritative_state(other), "host: state from its owner sets it")

	# Item 4a: a changed-bits index past the node's property count.
	_probe.set_multiplayer_authority(OTHER_PEER)
	tick = NetworkTime.tick + 8
	var bad_bits: PackedByteArray = _probe.crafted_diff_packet(tick, PackedByteArray([0x7C]), 8)
	var buffer: StreamPeerBuffer = StreamPeerBuffer.new()
	buffer.data_array = bad_bits
	var parsed: _Snapshot = _sync._sparse_serializer.read_from(OTHER_PEER, _sync._rb_state_properties, buffer)
	_check(parsed != null and parsed.is_empty(), "a changed-bits index past the property count reads as an empty snapshot")
	_sync._handle_diff_state(OTHER_PEER, bad_bits)
	_check(not _has_state(tick), "a diff with an out-of-range changed-bits index merges nothing")

	# Item 4b: a long run of continuation bytes must not cost real time.
	buffer.data_array = _probe.crafted_diff_packet(tick, Probe.filled(HUGE_BITS_BYTES, 0xFF), 0)
	var start: int = Time.get_ticks_msec()
	var decoded: _Snapshot = _sync._sparse_serializer.read_from(OTHER_PEER, _sync._rb_state_properties, buffer)
	var elapsed: int = Time.get_ticks_msec() - start
	_check(decoded != null and decoded.is_empty() and elapsed < TIME_BOUND_MSEC, "a %d byte run of 0xFF bit bytes is read in %d ms (limit %d)" % [HUGE_BITS_BYTES, elapsed, TIME_BOUND_MSEC])

	# Item 5: one packet must not buy tens of thousands of loop iterations.
	var zeros: PackedByteArray = Probe.filled(BIG_PACKET_BYTES, 0)
	buffer.data_array = zeros
	start = Time.get_ticks_msec()
	var redundant: Array[_Snapshot] = _sync._redundant_serializer.read_from(OTHER_PEER, _sync._rb_input_properties, buffer, true)
	elapsed = Time.get_ticks_msec() - start
	_check(elapsed < TIME_BOUND_MSEC and redundant.is_empty(), "a zero-filled %d byte redundant packet is read in %d ms into %d snapshots (limit %d ms, none expected)" % [BIG_PACKET_BYTES, elapsed, redundant.size(), TIME_BOUND_MSEC])
	# A snapshot size that is zero, or larger than what is left, ends the packet.
	var odd: StreamPeerBuffer = StreamPeerBuffer.new()
	NetworkSchemas.varuint().encode(100, odd)
	odd.put_u32(tick)
	buffer.data_array = odd.data_array
	_check(_sync._redundant_serializer.read_from(OTHER_PEER, _sync._rb_input_properties, buffer, true).is_empty(), "a snapshot size past the end of the packet yields no snapshot")
	odd.clear()
	NetworkSchemas.varuint().encode(0, odd)
	NetworkSchemas.varuint().encode(4, odd)
	odd.put_u32(tick)
	buffer.data_array = odd.data_array
	_check(_sync._redundant_serializer.read_from(OTHER_PEER, _sync._rb_input_properties, buffer, true).is_empty(), "a snapshot size of zero ends the packet")
	# Fifty valid, empty snapshots in one packet: an honest packet has at most input_redundancy.
	var many: StreamPeerBuffer = StreamPeerBuffer.new()
	for i: int in 50:
		NetworkSchemas.varuint().encode(4, many)
		many.put_u32(tick + i)
	buffer.data_array = many.data_array
	redundant = _sync._redundant_serializer.read_from(OTHER_PEER, _sync._rb_input_properties, buffer, true)
	_check(redundant.size() == NetworkRollback.input_redundancy, "a packet of 50 snapshots yields %d, the redundancy setting is %d" % [redundant.size(), NetworkRollback.input_redundancy])
	# The size cap on the input path: a valid snapshot from the owner followed by
	# padding past the limit is dropped whole, while the serializer alone would read
	# the snapshot and stop at the padding.
	var padded: PackedByteArray = _probe.input_packet(NetworkTime.tick + 7, 4)
	var too_big: PackedByteArray = padded + Probe.filled(_sync._max_packet_size * 2 * NetworkRollback.input_redundancy, 0)
	_sync._handle_input(OTHER_PEER, too_big)
	_check(not _has_input(NetworkTime.tick + 7), "an input packet over the size limit is dropped whole, though its first snapshot is valid")
	_sync._handle_input(OTHER_PEER, padded)
	_check(_has_input(NetworkTime.tick + 7), "control: the same snapshot without the padding is merged")
	elapsed = _msec(func() -> void: _sync._handle_input(OTHER_PEER, zeros))
	_check(elapsed < TIME_BOUND_MSEC, "a zero-filled %d byte input packet is handled in %d ms" % [BIG_PACKET_BYTES, elapsed])
	elapsed = _msec(func() -> void: _sync._handle_full_state(OTHER_PEER, zeros))
	_check(elapsed < TIME_BOUND_MSEC, "a zero-filled %d byte state packet is handled in %d ms" % [BIG_PACKET_BYTES, elapsed])
	elapsed = _msec(func() -> void: _sync._handle_diff_sync(OTHER_PEER, zeros))
	_check(elapsed < TIME_BOUND_MSEC, "a zero-filled %d byte sync diff packet is handled in %d ms" % [BIG_PACKET_BYTES, elapsed])

# max_sync_packet_size of zero or less means no limit, as in PacketBuffer.
func _no_limit_checks() -> void:
	var saved: int = _sync._max_packet_size
	_sync._max_packet_size = 0
	var tick: int = NetworkTime.tick + 2
	_probe.set_multiplayer_authority(OTHER_PEER)
	_sync._handle_input(OTHER_PEER, _probe.input_packet(tick, 3))
	_check(_has_input(tick), "with max_sync_packet_size 0 (no limit) an input packet is not dropped for size")
	_sync._handle_full_state(OTHER_PEER, _probe.full_state_packet(tick, 3))
	_check(_has_state(tick), "with max_sync_packet_size 0 (no limit) a state packet is not dropped for size")
	_sync._max_packet_size = saved

# Oversized packets are dropped, and the warning about them is logged once per
# peer per second, so a peer cannot fill the log. Peers 7 and 8 sent nothing before.
func _size_warning_checks() -> void:
	var big: PackedByteArray = Probe.filled(_sync._max_packet_size * 2 + 1, 0)
	var tick: int = NetworkTime.tick + 1
	var untouched: bool = not _has_state(tick)
	_warnings.dropped = 0
	for i: int in 1000:
		_sync._handle_full_state(7, big)
	_check(_warnings.dropped == 1, "1000 oversized packets from one peer: %d warnings (exactly 1)" % _warnings.dropped)
	_sync._handle_full_state(8, big)
	_check(_warnings.dropped == 2, "a second peer still gets its own first warning (%d warnings, expected 2)" % _warnings.dropped)
	_probe.set_multiplayer_authority(7)
	_sync._handle_full_state(7, _probe.full_state_packet(tick, 5) + big)
	_check(untouched and not _has_state(tick), "an oversized packet that starts with a valid state is still dropped while its warning is suppressed")
	await get_tree().create_timer(1.1).timeout
	_sync._handle_full_state(7, big)
	_check(_warnings.dropped == 3, "after the interval the next one is logged again (%d warnings, expected 3)" % _warnings.dropped)
	_sync._handle_full_state(7, big)
	_sync.erase_peer(7)
	_sync._handle_full_state(7, big)
	_check(_warnings.dropped == 4, "after the peer is erased its next oversized packet is logged (%d warnings, expected 4)" % _warnings.dropped)
	_sync._handle_full_state(8, big)
	_check(_warnings.dropped == 5, "the interval is kept per peer: peer 8 logs again after its own second (%d warnings, expected 5)" % _warnings.dropped)
	_sync._handle_full_state(8, big)
	_sync.reset()
	_sync._handle_full_state(8, big)
	_check(_warnings.dropped == 6, "after a reset the next oversized packet is logged (%d warnings, expected 6)" % _warnings.dropped)
	_check(_sync._last_size_warning_msec.size() == 1, "the bookkeeping holds only the peers warned since the reset (%d)" % _sync._last_size_warning_msec.size())

# A frame whose identity no registered subject has, with an empty body.
func _unknown_frame(buffer: StreamPeerBuffer, number: int) -> void:
	NetworkSchemas._netref().encode(_NetworkIdentityReference.of_full_name("/root/NoSuchSubject%d" % number), buffer)
	NetworkSchemas.varuint().encode(0, buffer)

# A full-state packet with `unknown` frames of unknown identity, then the probe's own frame.
func _unknown_then_valid(tick: int, unknown: int) -> PackedByteArray:
	var buffer: StreamPeerBuffer = StreamPeerBuffer.new()
	buffer.put_u32(tick)
	for number: int in unknown:
		_unknown_frame(buffer, number)
	buffer.put_data(_probe.full_state_packet(tick, 5).slice(4))
	return buffer.data_array

# Packets made of frames that name nothing the host has.
func _unknown_identity_checks() -> void:
	var tick: int = NetworkTime.tick + 5
	var subjects: int = _sync._rb_state_properties.get_subjects().size()
	_probe.set_multiplayer_authority(OTHER_PEER)
	_sync._handle_full_state(OTHER_PEER, _unknown_then_valid(tick, subjects))
	_check(_has_state(tick), "a packet with as many unknown frames as there are subjects (%d) still has its valid frame read" % subjects)
	tick += 1
	_sync._handle_full_state(OTHER_PEER, _unknown_then_valid(tick, subjects + 10))
	_check(not _has_state(tick), "a packet with %d unknown frames, more than the %d subjects, is dropped from there on" % [subjects + 10, subjects])

	var limit: int = _sync._max_packet_size * 2
	var zeros_state: PackedByteArray = Probe.filled(limit, 0)
	_warnings.count = 0
	var start: int = Time.get_ticks_msec()
	_sync._handle_full_state(OTHER_PEER, zeros_state)
	_sync._handle_full_state(OTHER_PEER, zeros_state)
	_sync._handle_full_state(OTHER_PEER, zeros_state)
	var elapsed: int = Time.get_ticks_msec() - start
	_check(elapsed < TIME_BOUND_MSEC and _warnings.count <= 1, "three zero-filled %d byte state packets: %d ms (limit %d), %d unknown-identity warnings (at most 1)" % [limit, elapsed, TIME_BOUND_MSEC, _warnings.count])

	# An input packet of the largest honest size whose one snapshot is zeros.
	var body: int = _sync._max_packet_size * 2 * NetworkRollback.input_redundancy - 2
	var input: StreamPeerBuffer = StreamPeerBuffer.new()
	NetworkSchemas.varuint().encode(body, input)
	input.put_data(Probe.filled(body, 0))
	_warnings.count = 0
	start = Time.get_ticks_msec()
	_sync._handle_input(OTHER_PEER, input.data_array)
	_sync._handle_input(OTHER_PEER, input.data_array)
	elapsed = Time.get_ticks_msec() - start
	_check(elapsed < TIME_BOUND_MSEC and _warnings.count <= 1, "two %d byte input packets of one zero-filled snapshot: %d ms (limit %d), %d unknown-identity warnings (at most 1)" % [input.get_size(), elapsed, TIME_BOUND_MSEC, _warnings.count])

# A client whose tick has not caught up. It takes snapshots from the server only,
# and takes them whatever tick they are stamped with.
func _client_checks() -> void:
	var near: int = NetworkTime.tick + 3
	var far: int = NetworkTime.tick + 30
	var very_far: int = NetworkTime.tick + 100

	# Item 2: anything not from peer 1 is dropped, even when the sender owns the
	# subject, so only the sender check can stop it.
	_probe.set_multiplayer_authority(OTHER_PEER)
	_sync._handle_input(OTHER_PEER, _probe.input_packet(near, 5))
	_check(not _has_input(near), "client drops input from a peer that is not the server")
	_sync._handle_full_state(OTHER_PEER, _probe.full_state_packet(near, 5))
	_check(not _has_state(near), "client drops full state from a peer that is not the server")
	_sync._handle_diff_state(OTHER_PEER, _probe.diff_state_packet(near, 5))
	_check(not _has_state(near), "client drops diff state from a peer that is not the server")
	_sync._handle_full_sync(OTHER_PEER, _probe.full_sync_packet(near, 5))
	_check(not _has_sync(near), "client drops full sync from a peer that is not the server")
	_sync._handle_diff_sync(OTHER_PEER, _probe.diff_sync_packet(near, 5))
	_check(not _has_sync(near), "client drops diff sync from a peer that is not the server")

	# The server's snapshots are merged, stamped near or well ahead of the tick.
	_probe.set_multiplayer_authority(SERVER_PEER)
	_sync._handle_input(SERVER_PEER, _probe.input_packet(near, 5))
	_check(_has_input(near), "client merges input stamped near its tick, from the server")
	_sync._handle_input(SERVER_PEER, _probe.input_packet(far, 5))
	_check(_has_input(far), "client merges input stamped %d ticks ahead, from the server" % (far - NetworkTime.tick))
	_sync._handle_input(SERVER_PEER, _probe.input_packet(very_far, 5))
	_check(_has_input(very_far), "client merges input stamped %d ticks ahead, past history_limit, from the server" % (very_far - NetworkTime.tick))
	_sync._handle_full_state(SERVER_PEER, _probe.full_state_packet(near, 5))
	_check(_has_state(near), "client merges full state stamped near its tick, from the server")
	_sync._handle_full_state(SERVER_PEER, _probe.full_state_packet(far, 5))
	_check(_has_state(far), "client merges full state stamped %d ticks ahead, from the server" % (far - NetworkTime.tick))
	_sync._handle_diff_state(SERVER_PEER, _probe.diff_state_packet(far + 1, 5))
	_check(_has_state(far + 1), "client merges diff state stamped %d ticks ahead, from the server" % (far + 1 - NetworkTime.tick))
	_sync._handle_full_sync(SERVER_PEER, _probe.full_sync_packet(far, 5))
	_check(_has_sync(far), "client merges full sync stamped %d ticks ahead, from the server" % (far - NetworkTime.tick))
	_sync._handle_diff_sync(SERVER_PEER, _probe.diff_sync_packet(far + 1, 5))
	_check(_has_sync(far + 1), "client merges diff sync stamped %d ticks ahead, from the server" % (far + 1 - NetworkTime.tick))

# Items 6 and 7. Neither needs a particular role. A malformed ping must not raise
# a script error (tests/run_all.sh fails any run that prints one); a conflicting
# second id for the same node must not replace the first.
func _identity_and_ping_checks() -> void:
	NetworkTimeSynchronizer._handle_ping(OTHER_PEER, PackedByteArray([0xFF, 0xFF, 0xFF]))
	NetworkTimeSynchronizer._handle_ping(OTHER_PEER, var_to_bytes("not an index"))
	NetworkTimeSynchronizer._handle_ping(OTHER_PEER, var_to_bytes(Vector2.ONE))
	NetworkTimeSynchronizer._handle_ping(OTHER_PEER, PackedByteArray())
	print("PASS malformed ping payloads were handled")

	var identifier: _NetworkIdentifier = _NetworkIdentifier.new(_probe, "ProbeSubject", 99)
	identifier.set_id_for(OTHER_PEER, 5)
	identifier.set_id_for(OTHER_PEER, 5)
	_check(identifier.get_id_for(OTHER_PEER) == 5, "the same id registered twice is kept")
	identifier.set_id_for(OTHER_PEER, 6)
	_check(identifier.get_id_for(OTHER_PEER) == 5, "a conflicting second id for the same peer is ignored")
