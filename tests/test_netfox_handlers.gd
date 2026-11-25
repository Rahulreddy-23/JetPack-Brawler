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
## (count) and those that report a dropped oversized packet (dropped). Lines
## (warnings and errors) that contain one of the keys of `lines` are counted
## per key, and printed lines that start with "Received ID #" in `id_lines`.
class WarningCounter extends Logger:
	var count: int = 0
	var dropped: int = 0
	var lines: Dictionary = {}
	var id_lines: int = 0
	## Lines the engine prints for invalid UTF-8 ("Unicode parsing error"), one per bad byte.
	var bad_utf8: int = 0
	## Every error (not warning) reported, the engine's decoder errors included.
	var errors: int = 0

	func _log_error(_function: String, _file: String, _line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_ERROR:
			errors += 1
		if "Unicode parsing error" in code or "Unicode parsing error" in rationale:
			bad_utf8 += 1
		for needle: String in lines:
			if needle in code or needle in rationale:
				lines[needle] = (lines[needle] as int) + 1
		if error_type != Logger.ERROR_TYPE_WARNING:
			return
		if "unknown identity" in code or "unknown identity" in rationale:
			count += 1
		if "Dropping" in code or "Dropping" in rationale:
			dropped += 1

	func _log_message(message: String, _error: bool) -> void:
		if "Received ID #" in message:
			id_lines += 1
		if "Unicode parsing error" in message:
			bad_utf8 += 1

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
		await _peer_log_checks()
		_declared_length_checks()
		_text_cost_checks()
		_variant_type_checks()
		_variant_shape_checks()
		_frame_size_checks()
		_command_prefix_checks()
	else:
		await get_tree().process_frame
		_check(not multiplayer.is_server(), "running as a client")
		_check(NetworkTime.tick < 5, "client tick is still at the start (%d)" % NetworkTime.tick)
		_client_checks()
	_identity_and_ping_checks()
	if mode == "host":
		_stop_checks()

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

var _crash_length: PackedByteArray = PackedByteArray([0xff, 0xff, 0xff, 0x7f])
var _negative_length: PackedByteArray = PackedByteArray([0xff, 0xff, 0xff, 0xff])
const UNKNOWN_COMMAND_LINE: String = "Received unknown command"
const TICKRATE_LINE: String = "differs from tickrate"
const REFUSED_ID_LINE: String = "Refusing identity packet"
const ID_ENTRIES: int = 10000
const HUGE_ID_ENTRIES: int = 200000

# What a peer can make the host log with one bad packet over and over: an unknown
# command index, a tickrate that differs, an identity packet. Each is logged once
# per peer per second, and an identity packet over the limits is not read at all.
# Peers 9 and 10 sent nothing before.
func _peer_log_checks() -> void:
	var handshake: NetworkTickrateHandshake = NetworkTime._tickrate_handshake
	var ids: _NetworkIdentityServer = NetworkIdentityServer
	_check(handshake.mismatch_action == NetworkTickrateHandshake.WARN, "control: the tickrate mismatch action is the default, a warning")
	_warnings.lines = {UNKNOWN_COMMAND_LINE: 0, TICKRATE_LINE: 0, REFUSED_ID_LINE: 0}
	_warnings.id_lines = 0

	# Unknown command index: still ignored, one line per peer per second
	var start: int = Time.get_ticks_msec()
	for i: int in 1000:
		NetworkCommandServer._handle_command(9, 250, PackedByteArray())
	var elapsed: int = Time.get_ticks_msec() - start
	var seen: int = _warnings.lines[UNKNOWN_COMMAND_LINE]
	_check(seen == 1 and elapsed < TIME_BOUND_MSEC, "1000 unknown-command packets from one peer: %d lines (exactly 1), %d ms (limit %d)" % [seen, elapsed, TIME_BOUND_MSEC])
	NetworkCommandServer._handle_command(10, 250, PackedByteArray())
	seen = _warnings.lines[UNKNOWN_COMMAND_LINE]
	_check(seen == 2, "unknown command: a second peer gets its own first line (%d lines, expected 2)" % seen)

	# Tickrate mismatch: still only a warning, one line per peer per second
	start = Time.get_ticks_msec()
	for i: int in 1000:
		handshake._handle_tickrate_mismatch(9, NetworkTime.tickrate + 1)
	elapsed = Time.get_ticks_msec() - start
	seen = _warnings.lines[TICKRATE_LINE]
	_check(seen == 1 and elapsed < TIME_BOUND_MSEC, "1000 tickrate mismatches from one peer: %d lines (exactly 1), %d ms (limit %d)" % [seen, elapsed, TIME_BOUND_MSEC])
	handshake._handle_tickrate_mismatch(10, NetworkTime.tickrate + 1)
	seen = _warnings.lines[TICKRATE_LINE]
	_check(seen == 2, "tickrate mismatch: a second peer gets its own first line (%d lines, expected 2)" % seen)

	# Identity packets: 10000 entries is refused unread, an honest one is taken
	var identifier: _NetworkIdentifier = ids._get_identifier_of(_probe)
	var names: Dictionary = {identifier.get_full_name(): 41}
	for i: int in ID_ENTRIES - 1:
		names["/root/NoSuchNode%d" % i] = i
	var big: PackedByteArray = ids._packet_serializer.serialize(names)
	start = Time.get_ticks_msec()
	for i: int in 3:
		ids._handle_ids(9, big)
	elapsed = Time.get_ticks_msec() - start
	seen = _warnings.lines[REFUSED_ID_LINE]
	_check(elapsed < TIME_BOUND_MSEC and seen == 1 and _warnings.id_lines == 0 and not identifier.has_id_for(9), "three identity packets of %d entries (%d bytes, limit %d): %d ms (limit %d), %d refusal lines (exactly 1), %d per-entry lines (0), nothing stored" % [ID_ENTRIES, big.size(), ids._MAX_ID_PACKET_BYTES, elapsed, TIME_BOUND_MSEC, seen, _warnings.id_lines])
	# A reliable packet can be megabytes: it is refused without being read
	var huge_names: Dictionary = {}
	for i: int in HUGE_ID_ENTRIES:
		huge_names["/root/NoSuchNode%d" % i] = i
	var huge: PackedByteArray = ids._packet_serializer.serialize(huge_names)
	start = Time.get_ticks_msec()
	ids._handle_ids(10, huge)
	elapsed = Time.get_ticks_msec() - start
	_check(elapsed < TIME_BOUND_MSEC, "one identity packet of %d entries, %d bytes: refused in %d ms (limit %d)" % [HUGE_ID_ENTRIES, huge.size(), elapsed, TIME_BOUND_MSEC])
	# Small, but over the entry limit: many short names
	var many: Dictionary = {identifier.get_full_name(): 41}
	for i: int in ids._MAX_ID_ENTRIES:
		many["/%d" % i] = i
	var small: PackedByteArray = ids._packet_serializer.serialize(many)
	ids._handle_ids(10, small)
	_check(small.size() <= ids._MAX_ID_PACKET_BYTES and not identifier.has_id_for(10), "a packet of %d entries, %d bytes (under the byte limit), is refused for its entry count" % [many.size(), small.size()])
	var honest: Dictionary = {identifier.get_full_name(): 41}
	for i: int in ids._HONEST_ID_COUNT - 1:
		honest["/root/NoSuchNode%d" % i] = i
	var packet: PackedByteArray = ids._packet_serializer.serialize(honest)
	_warnings.id_lines = 0
	ids._handle_ids(11, packet)
	_check(identifier.get_id_for(11) == 41 and _warnings.id_lines == 0, "an identity packet of %d entries, %d bytes, is accepted (id %d stored, %d per-entry lines)" % [honest.size(), packet.size(), identifier.get_id_for(11), _warnings.id_lines])
	var limit_packet: PackedByteArray = ids._packet_serializer.serialize({identifier.get_full_name(): 41, "/" + "x".repeat(ids._MAX_ID_NAME_BYTES - 1): 1})
	ids._handle_ids(12, limit_packet)
	_check(identifier.get_id_for(12) == 41, "an identity packet with a name of %d bytes is accepted" % ids._MAX_ID_NAME_BYTES)

	await get_tree().create_timer(1.1).timeout
	NetworkCommandServer._handle_command(9, 250, PackedByteArray())
	handshake._handle_tickrate_mismatch(9, NetworkTime.tickrate + 1)
	ids._handle_ids(9, big)
	_check(_warnings.lines[UNKNOWN_COMMAND_LINE] == 3 and _warnings.lines[TICKRATE_LINE] == 3 and _warnings.lines[REFUSED_ID_LINE] == 3, "after the interval the next line of each kind is logged again (%d, %d, %d lines, expected 3 each)" % [_warnings.lines[UNKNOWN_COMMAND_LINE], _warnings.lines[TICKRATE_LINE], _warnings.lines[REFUSED_ID_LINE]])

	# The tables hold only peers that were logged, and are emptied when a peer leaves or on a reset
	var command_table: Dictionary = NetworkCommandServer._unknown_command_limit._last_msec
	var tickrate_table: Dictionary = handshake._mismatch_warning_limit._last_msec
	var identity_table: Dictionary = ids._refusal_limit._last_msec
	_check(command_table.size() == 2 and tickrate_table.size() == 2 and identity_table.size() == 2, "the per-peer tables hold the peers that were logged (%d, %d, %d, expected 2 each)" % [command_table.size(), tickrate_table.size(), identity_table.size()])
	multiplayer.peer_disconnected.emit(9)
	_check(not command_table.has(9) and not tickrate_table.has(9) and not identity_table.has(9) and command_table.size() == 1 and tickrate_table.size() == 1 and identity_table.size() == 1, "a peer leaving is erased from all three tables (%d, %d, %d left, expected 1 each)" % [command_table.size(), tickrate_table.size(), identity_table.size()])
	NetworkCommandServer.reset()
	handshake.stop()
	handshake.run()
	var scratch: _NetworkIdentityServer = _NetworkIdentityServer.new(NetworkCommandServer)
	scratch._handle_ids(10, big)
	_check(scratch._refusal_limit._last_msec.size() == 1, "control: a scratch identity server logged its refusal")
	scratch.clear()
	_check(command_table.is_empty() and tickrate_table.is_empty() and scratch._refusal_limit._last_msec.is_empty(), "after a reset (command server reset, handshake stop, identity clear) the tables are empty (%d, %d, %d)" % [command_table.size(), tickrate_table.size(), scratch._refusal_limit._last_msec.size()])
	scratch.free()
	_warnings.lines = {}

## A buffer holding exactly these bytes.
func _buffer_of(bytes: PackedByteArray) -> StreamPeerBuffer:
	var buffer: StreamPeerBuffer = StreamPeerBuffer.new()
	buffer.data_array = bytes
	return buffer

## One identity entry: a string with its 4 byte length, then the id as a varuint.
func _id_entry(full_name: String, id: int) -> PackedByteArray:
	var buffer: StreamPeerBuffer = StreamPeerBuffer.new()
	buffer.put_utf8_string(full_name)
	NetworkSchemas.varuint().encode(id, buffer)
	return buffer.data_array

# The engine's get_utf8_string and get_var allocate the length a packet declares
# before they look at the bytes left: 4 bytes declaring 2 GB kill the process
# (exit 138, checked in a scratch copy). Every read of a length from a packet checks it
# against the bytes left first. Each call below would otherwise kill this process, so a
# passing run shows the calls return; the results show nothing is stored.
func _declared_length_checks() -> void:
	var ids: _NetworkIdentityServer = NetworkIdentityServer
	var serializer: _IdentityPacketSerializer = ids._packet_serializer
	var identifier: _NetworkIdentifier = ids._get_identifier_of(_probe)
	var entry: PackedByteArray = _id_entry(identifier.get_full_name(), 41)

	# Identity packets: the 4 byte packet
	ids._handle_ids(14, _crash_length)
	_check(not identifier.has_id_for(14) and serializer.deserialize(_crash_length).is_empty(), "a 4 byte identity packet declaring a 2 GB name returns and registers nothing")
	_check(serializer.deserialize(_negative_length).is_empty(), "an identity packet with a negative name length registers nothing")
	var one_more: PackedByteArray = PackedByteArray([0, 0, 0, 0])
	one_more.encode_s32(0, 5)
	one_more.append_array("abcd".to_utf8_buffer())
	_check(serializer.deserialize(one_more).is_empty(), "an identity name one byte longer than the bytes left registers nothing")
	_check(serializer.deserialize(entry).size() == 1 and serializer.deserialize(entry)[identifier.get_full_name()] == 41, "control: a whole identity entry is read")
	_check(serializer.deserialize(entry + entry.slice(0, 3)).is_empty(), "a valid identity entry then 3 bytes of the next registers nothing, not even the valid entry")
	_check(serializer.deserialize(entry + _crash_length).is_empty(), "a valid identity entry then a 2 GB name registers nothing")
	_check(serializer.deserialize(entry + entry.slice(0, entry.size() - 1)).is_empty(), "a valid identity entry then a name with no id registers nothing")
	var cut_id: PackedByteArray = _id_entry("/x", 300)
	_check(serializer.deserialize(cut_id.slice(0, cut_id.size() - 1)).is_empty(), "an identity entry whose id varuint ends in the packet's last byte, still marked as continued, registers nothing")
	ids._handle_ids(14, entry + entry.slice(0, 3))
	_check(not identifier.has_id_for(14), "the handler stores nothing from a packet cut inside its second entry")

	# The string and variant schema serializers
	var string_serializer: NetworkSchemaSerializer = NetworkSchemas.string()
	var variant_serializer: NetworkSchemaSerializer = NetworkSchemas.variant()
	_check(string_serializer.decode(_buffer_of(_crash_length)) == "", "a string declaring 2 GB in 4 bytes gives an empty string")
	_check(string_serializer.decode(_buffer_of(_negative_length)) == "", "a string with a negative length gives an empty string")
	_check(string_serializer.decode(_buffer_of(one_more)) == "", "a string one byte longer than the bytes left gives an empty string")
	var written: StreamPeerBuffer = StreamPeerBuffer.new()
	string_serializer.encode("hello", written)
	_check(string_serializer.decode(_buffer_of(written.data_array)) == "hello", "control: a string is read back")
	_check(variant_serializer.decode(_buffer_of(_crash_length)) == null, "a variant declaring 2 GB in 4 bytes gives null")
	_check(variant_serializer.decode(_buffer_of(_negative_length)) == null, "a variant with a negative length gives null")
	var crash_with_header: PackedByteArray = _crash_length + PackedByteArray([2, 0, 0, 0, 5, 0, 0, 0])
	_check(variant_serializer.decode(_buffer_of(crash_with_header)) == null, "a variant declaring 2 GB, with a type header and a value after it, gives null")
	var variant_cut: PackedByteArray = PackedByteArray([0, 0, 0, 0])
	variant_cut.encode_s32(0, 9)
	variant_cut.append_array(PackedByteArray([2, 0, 0, 0, 5, 0, 0, 0]))
	_check(variant_serializer.decode(_buffer_of(variant_cut)) == null, "a variant one byte longer than the bytes left gives null")
	written = StreamPeerBuffer.new()
	variant_serializer.encode(Vector2(3, 4), written)
	_check(variant_serializer.decode(_buffer_of(written.data_array)) == Vector2(3, 4), "control: a variant is read back as put_var wrote it")
	written = StreamPeerBuffer.new()
	written.put_var(Vector2(3, 4), false)
	_check(variant_serializer.decode(_buffer_of(written.data_array)) == Vector2(3, 4), "control: a variant written by the engine's put_var is read")
	# Arrays and dictionaries: the count is checked against the bytes left
	var big_count: StreamPeerBuffer = StreamPeerBuffer.new()
	NetworkSchemas.varuint().encode(1 << 40, big_count)
	var array_serializer: NetworkSchemaSerializer = NetworkSchemas.array_of(NetworkSchemas.uint8(), NetworkSchemas.varuint())
	var dictionary_serializer: NetworkSchemaSerializer = NetworkSchemas.dictionary(NetworkSchemas.uint8(), NetworkSchemas.uint8(), NetworkSchemas.varuint())
	var start: int = Time.get_ticks_msec()
	var array_value: Array = array_serializer.decode(_buffer_of(big_count.data_array))
	var dictionary_value: Dictionary = dictionary_serializer.decode(_buffer_of(big_count.data_array))
	var elapsed: int = Time.get_ticks_msec() - start
	_check(array_value.is_empty() and dictionary_value.is_empty() and elapsed < TIME_BOUND_MSEC, "an array and a dictionary declaring 2^40 entries are empty, read in %d ms (limit %d)" % [elapsed, TIME_BOUND_MSEC])

	# A dictionary entry takes at least two bytes: a count over half the bytes left is refused
	var five: StreamPeerBuffer = StreamPeerBuffer.new()
	NetworkSchemas.varuint().encode(5, five)
	five.put_data(PackedByteArray([1, 1, 2, 2, 3, 3, 4, 4, 5]))
	var four: StreamPeerBuffer = StreamPeerBuffer.new()
	NetworkSchemas.varuint().encode(4, four)
	four.put_data(PackedByteArray([1, 1, 2, 2, 3, 3, 4, 4]))
	var tight_refused: Dictionary = dictionary_serializer.decode(_buffer_of(five.data_array))
	var tight_read: Dictionary = dictionary_serializer.decode(_buffer_of(four.data_array))
	_check(tight_refused.is_empty() and tight_read.size() == 4, "a dictionary of 5 entries in 9 bytes is refused, one of 4 entries in 8 bytes is read (%d, %d entries)" % [tight_refused.size(), tight_read.size()])

	# The same through the real handlers: a state frame of a subject, whose
	# first property declares a 2 GB variant in 4 bytes
	var frame: StreamPeerBuffer = StreamPeerBuffer.new()
	var tick: int = NetworkTime.tick + 7
	frame.put_u32(tick)
	NetworkSchemas._netref().encode(_NetworkIdentityReference.of_full_name(identifier.get_full_name()), frame)
	NetworkSchemas.varuint().encode(crash_with_header.size(), frame)
	frame.put_data(crash_with_header)
	_probe.set_multiplayer_authority(OTHER_PEER)
	_sync._handle_full_state(OTHER_PEER, frame.data_array)
	var input: StreamPeerBuffer = StreamPeerBuffer.new()
	NetworkSchemas.varuint().encode(frame.get_size(), input)
	input.put_data(frame.data_array)
	_sync._handle_input(OTHER_PEER, input.data_array)
	_check(true, "a state packet and an input packet whose property is a 2 GB variant in 4 bytes are handled and return")

## A state frame of the probe: tick, identity, the size field as given, for a
## sparse frame the changed-bits field (both properties), then the two values.
func _state_frame(tick: int, sparse: bool, size_field: PackedByteArray, values: PackedByteArray = PackedByteArray()) -> PackedByteArray:
	var data: StreamPeerBuffer = StreamPeerBuffer.new()
	if values.is_empty():
		NetworkSchemas.variant().encode(6, data)
		NetworkSchemas.variant().encode(6, data)
	else:
		data.put_data(values)
	var frame: StreamPeerBuffer = StreamPeerBuffer.new()
	frame.put_u32(tick)
	NetworkSchemas._netref().encode(_NetworkIdentityReference.of_full_name(NetworkIdentityServer._get_identifier_of(_probe).get_full_name()), frame)
	if size_field.is_empty():
		NetworkSchemas.varuint().encode(data.get_size(), frame)
	else:
		frame.put_data(size_field)
	if sparse:
		frame.put_u8(0x03)
	frame.put_data(data.data_array)
	return frame.data_array

# A frame size larger than the rest of the packet, or negative, ends the packet:
# the frame is not read from the part that is there. A negative size was an engine
# error for every such frame. Per kind, a frame of the right size is merged (control).
func _frame_size_checks() -> void:
	var tick: int = NetworkTime.tick
	var too_big: PackedByteArray = PackedByteArray([0xc8, 0x01]) # varuint 200
	var negative: PackedByteArray = PackedByteArray([0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff]) # decodes as -1
	_probe.set_multiplayer_authority(OTHER_PEER)
	_warnings.lines = {"p_size < 0": 0}
	_sync._handle_full_state(OTHER_PEER, _state_frame(tick + 1, false, PackedByteArray()))
	_sync._handle_full_state(OTHER_PEER, _state_frame(tick + 2, false, too_big))
	_sync._handle_full_state(OTHER_PEER, _state_frame(tick + 3, false, negative))
	_check(_has_state(tick + 1) and not _has_state(tick + 2) and not _has_state(tick + 3) and _warnings.lines["p_size < 0"] == 0, "dense frames: right size merged, size 200 over the packet's rest and size -1 dropped, %d engine errors (0)" % _warnings.lines["p_size < 0"])
	_sync._handle_diff_state(OTHER_PEER, _state_frame(tick + 4, true, PackedByteArray()))
	_sync._handle_diff_state(OTHER_PEER, _state_frame(tick + 5, true, too_big))
	_sync._handle_diff_state(OTHER_PEER, _state_frame(tick + 6, true, negative))
	_check(_has_state(tick + 4) and not _has_state(tick + 5) and not _has_state(tick + 6) and _warnings.lines["p_size < 0"] == 0, "sparse frames: right size merged, size 200 over the packet's rest and size -1 dropped, %d engine errors (0)" % _warnings.lines["p_size < 0"])
	_warnings.lines = {}

# A raw command packet is the prefix, the command index and the data.
func _command_prefix_checks() -> void:
	var transport: Node = NetworkCommandServer._packet_transport
	var prefix: PackedByteArray = NetworkCommandServer.get_command_packet_prefix()
	var received: Array = []
	var catcher: Callable = func(sender: int, idx: int, data: PackedByteArray) -> void: received.append([sender, idx, data.size()])
	transport.on_receive.connect(catcher)
	transport._handle_packet(7, prefix)
	_check(received.is_empty(), "a raw packet that is only the 3 byte prefix dispatches nothing (%d dispatched)" % received.size())
	transport._handle_packet(7, prefix.slice(0, 2))
	_check(received.is_empty(), "a raw packet shorter than the prefix dispatches nothing")
	transport._handle_packet(7, PackedByteArray([1, 2, 3, 250]))
	_check(received.is_empty(), "a raw packet without the prefix dispatches nothing")
	transport._handle_packet(7, prefix + PackedByteArray([250, 9]))
	_check(received.size() == 1 and received[0] == [7, 250, 1], "control: a raw packet with the prefix, an index and one data byte dispatches once, from peer 7 as index 250 with 1 byte (got %s)" % [received])
	transport.on_receive.disconnect(catcher)

## The bytes of a string variant (type, byte length, the bytes, padding) as bytes_to_var reads it.
func _string_variant(text_bytes: PackedByteArray) -> PackedByteArray:
	var inner: PackedByteArray = PackedByteArray()
	inner.resize(8)
	inner.encode_u32(0, TYPE_STRING)
	inner.encode_u32(4, text_bytes.size())
	inner.append_array(text_bytes)
	while inner.size() % 4 != 0:
		inner.append(0)
	return inner

## The same with the 4 byte length in front, as put_var writes it.
func _framed(inner: PackedByteArray) -> PackedByteArray:
	var framed: PackedByteArray = PackedByteArray()
	framed.resize(4)
	framed.encode_u32(0, inner.size())
	framed.append_array(inner)
	return framed

func _bad_bytes(count: int) -> PackedByteArray:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(count)
	bytes.fill(0xff)
	return bytes

# The engine prints an error line for every invalid UTF-8 byte it decodes, so a
# string a peer can make the host decode costs a line per byte, whatever bounds the
# packet size has. The engine's lines are counted in process (an engine logger
# receives them). Each decoder below must refuse such a string before decoding it.
func _text_cost_checks() -> void:
	var ids: _NetworkIdentityServer = NetworkIdentityServer
	var identifier: _NetworkIdentifier = ids._get_identifier_of(_probe)
	var entry: PackedByteArray = _id_entry(identifier.get_full_name(), 41)
	_warnings.bad_utf8 = 0

	# Identity packets: a name of 14,000 bad bytes is one entry under the packet cap
	var name_field: PackedByteArray = PackedByteArray([0, 0, 0, 0])
	name_field.encode_s32(0, 14000)
	var bad_name: PackedByteArray = name_field + _bad_bytes(14000) + PackedByteArray([5])
	var start: int = Time.get_ticks_msec()
	ids._handle_ids(15, bad_name)
	var elapsed: int = Time.get_ticks_msec() - start
	_check(bad_name.size() <= ids._MAX_ID_PACKET_BYTES and _warnings.bad_utf8 == 0 and elapsed < TIME_BOUND_MSEC, "an identity packet of one 14000 byte name of bad UTF-8, %d bytes (under the %d byte limit): %d engine error lines (0), %d ms (limit %d)" % [bad_name.size(), ids._MAX_ID_PACKET_BYTES, _warnings.bad_utf8, elapsed, TIME_BOUND_MSEC])
	# The same bad bytes in names of the allowed length: 100 entries of 128 bytes, under both limits
	var many_bad: PackedByteArray = PackedByteArray()
	var bad_field: PackedByteArray = PackedByteArray([0, 0, 0, 0])
	bad_field.encode_s32(0, ids._MAX_ID_NAME_BYTES)
	for i: int in 100:
		many_bad.append_array(bad_field + _bad_bytes(ids._MAX_ID_NAME_BYTES) + PackedByteArray([1]))
	_warnings.bad_utf8 = 0
	start = Time.get_ticks_msec()
	ids._handle_ids(15, many_bad)
	elapsed = Time.get_ticks_msec() - start
	_check(many_bad.size() <= ids._MAX_ID_PACKET_BYTES and _warnings.bad_utf8 == 0 and elapsed < TIME_BOUND_MSEC, "an identity packet of 100 names of %d bad UTF-8 bytes, %d bytes (under both limits): %d engine error lines (0), %d ms (limit %d)" % [ids._MAX_ID_NAME_BYTES, many_bad.size(), _warnings.bad_utf8, elapsed, TIME_BOUND_MSEC])
	var long_name: PackedByteArray = _id_entry("/" + "x".repeat(ids._MAX_ID_NAME_BYTES), 7)
	ids._handle_ids(16, entry + long_name)
	_check(not identifier.has_id_for(16), "an identity packet with a name of %d bytes is refused whole, the valid entry before it included" % (ids._MAX_ID_NAME_BYTES + 1))
	ids._handle_ids(17, entry + _id_entry("/caf\u00e9", 7))
	_check(not identifier.has_id_for(17), "an identity packet with a name that is not ASCII (valid UTF-8) is refused whole")
	ids._handle_ids(18, entry + _id_entry("/" + "x".repeat(ids._MAX_ID_NAME_BYTES - 1), 7))
	_check(identifier.get_id_for(18) == 41, "control: names of 1 and %d ASCII bytes are accepted" % ids._MAX_ID_NAME_BYTES)
	var many: PackedByteArray = PackedByteArray()
	for i: int in 2000:
		many.append_array(_id_entry("/%d" % i, i))
	_check(ids._packet_serializer.deserialize(many, ids._MAX_ID_ENTRIES + 1).size() == ids._MAX_ID_ENTRIES + 1, "a packet of 2000 entries is read up to %d entries and no further" % (ids._MAX_ID_ENTRIES + 1))
	_check(ids._packet_serializer.deserialize(many).size() == 2000, "control: without the limit the same packet reads all 2000")

	# The clock commands: a ping, pong or timestamp is a small fixed payload
	var synchronizer: Node = NetworkTimeSynchronizer
	var big_string: PackedByteArray = _string_variant(_bad_bytes(200000))
	_warnings.bad_utf8 = 0
	start = Time.get_ticks_msec()
	synchronizer._handle_ping(OTHER_PEER, big_string)
	elapsed = Time.get_ticks_msec() - start
	_check(_warnings.bad_utf8 == 0 and elapsed < TIME_BOUND_MSEC, "a ping that is a string variant of 200000 bad bytes: %d engine error lines (0), %d ms (limit %d)" % [_warnings.bad_utf8, elapsed, TIME_BOUND_MSEC])
	_warnings.bad_utf8 = 0
	start = Time.get_ticks_msec()
	synchronizer._handle_pong(SERVER_PEER, big_string)
	synchronizer._handle_pong(SERVER_PEER, var_to_bytes([1, "a", "b"]))
	synchronizer._handle_set_timestamp(SERVER_PEER, big_string)
	synchronizer._handle_set_timestamp(SERVER_PEER, var_to_bytes("not a time"))
	elapsed = Time.get_ticks_msec() - start
	_check(_warnings.bad_utf8 == 0 and elapsed < TIME_BOUND_MSEC, "a pong and a timestamp from the server that are bad strings: %d engine error lines (0), %d ms (limit %d)" % [_warnings.bad_utf8, elapsed, TIME_BOUND_MSEC])
	_check(synchronizer._is_scalar_payload(var_to_bytes(5), TYPE_INT) and synchronizer._is_scalar_payload(var_to_bytes(1 << 40), TYPE_INT) and synchronizer._is_pong_payload(var_to_bytes([1 << 40, 1234567.891, 1e300])) and synchronizer._is_pong_payload(var_to_bytes([3, 0.5, 1.25])) and synchronizer._is_scalar_payload(var_to_bytes(1234567.891), TYPE_FLOAT) and synchronizer._is_scalar_payload(var_to_bytes(0.5), TYPE_FLOAT), "control: an honest ping (also with a 64 bit index), pong and timestamp (a float of either width) pass the size and type check")
	_check(not synchronizer._is_scalar_payload(var_to_bytes("ab"), TYPE_INT) and not synchronizer._is_scalar_payload(var_to_bytes(5), TYPE_FLOAT) and not synchronizer._is_scalar_payload(PackedByteArray(), TYPE_INT) and not synchronizer._is_pong_payload(var_to_bytes([1, 2])), "a ping of the wrong type, an empty one and a pong of 2 elements fail the size and type check")
	# A size inside the old window that does not match the header: 8 bytes with the 64 bit flag set
	var flagged_int: PackedByteArray = PackedByteArray([2, 0, 1, 0, 5, 0, 0, 0])
	var flagged_float: PackedByteArray = PackedByteArray([3, 0, 1, 0, 0, 0, 0, 0])
	var long_int: PackedByteArray = PackedByteArray([2, 0, 0, 0, 5, 0, 0, 0, 0, 0, 0, 0])
	_warnings.errors = 0
	synchronizer._handle_ping(OTHER_PEER, flagged_int)
	synchronizer._handle_ping(OTHER_PEER, long_int)
	synchronizer._handle_set_timestamp(SERVER_PEER, flagged_float)
	_check(not synchronizer._is_scalar_payload(flagged_int, TYPE_INT) and not synchronizer._is_scalar_payload(long_int, TYPE_INT) and not synchronizer._is_scalar_payload(flagged_float, TYPE_FLOAT) and _warnings.errors == 0, "a ping of 8 bytes with the 64 bit flag, one of 12 bytes without it, and a timestamp of 8 bytes with it are refused: %d engine errors (0)" % _warnings.errors)

	# A string-typed property in a state packet and in an input packet
	var properties: StreamPeerBuffer = StreamPeerBuffer.new()
	properties.put_data(_framed(_string_variant(_bad_bytes(2000))))
	NetworkSchemas.variant().encode(6, properties)
	var tick: int = NetworkTime.tick + 6
	_probe.set_multiplayer_authority(OTHER_PEER)
	_warnings.bad_utf8 = 0
	start = Time.get_ticks_msec()
	_sync._handle_full_state(OTHER_PEER, _state_frame(tick + 1, false, PackedByteArray(), properties.data_array))
	_sync._handle_diff_state(OTHER_PEER, _state_frame(tick + 2, true, PackedByteArray(), properties.data_array))
	var input: StreamPeerBuffer = StreamPeerBuffer.new()
	var frame: PackedByteArray = _state_frame(tick + 3, false, PackedByteArray(), properties.data_array)
	NetworkSchemas.varuint().encode(frame.size(), input)
	input.put_data(frame)
	_sync._handle_input(OTHER_PEER, input.data_array)
	elapsed = Time.get_ticks_msec() - start
	_check(_warnings.bad_utf8 == 0 and elapsed < TIME_BOUND_MSEC, "a string property of 2000 bad bytes in a state packet, a diff state packet and an input packet: %d engine error lines (0), %d ms (limit %d)" % [_warnings.bad_utf8, elapsed, TIME_BOUND_MSEC])

## The value of the variant fallback as put_var frames it, with a chosen header and body.
func _framed_value(header: int, body: PackedByteArray) -> PackedByteArray:
	var inner: PackedByteArray = PackedByteArray()
	inner.resize(4)
	inner.encode_u32(0, header)
	inner.append_array(body)
	return _framed(inner)

# get_var prints error lines (two per value) for a header it does not know and for a
# body shorter than its type needs, so the decoder checks both before it calls get_var.
func _variant_shape_checks() -> void:
	var serializer: NetworkSchemaSerializer = NetworkSchemas.variant()
	var flag: int = 1 << 16
	# Body bytes of each allowed type, without and with the 64 bit flag, as the engine reads them
	var bodies: Dictionary = {TYPE_NIL: [0, 0], TYPE_BOOL: [4, 4], TYPE_INT: [4, 8], TYPE_FLOAT: [4, 8], TYPE_VECTOR2: [8, 16], TYPE_VECTOR2I: [8, 8], TYPE_RECT2: [16, 32], TYPE_RECT2I: [16, 16], TYPE_VECTOR3: [12, 24], TYPE_VECTOR3I: [12, 12], TYPE_TRANSFORM2D: [24, 48], TYPE_VECTOR4: [16, 32], TYPE_VECTOR4I: [16, 16], TYPE_PLANE: [16, 32], TYPE_QUATERNION: [16, 32], TYPE_AABB: [24, 48], TYPE_BASIS: [36, 72], TYPE_TRANSFORM3D: [48, 96], TYPE_PROJECTION: [64, 128], TYPE_COLOR: [16, 16]}
	var exact_ok: int = 0
	var short_refused: int = 0
	var long_aligned: int = 0
	var cases: int = 0
	_warnings.errors = 0
	for type: int in bodies:
		for form: int in 2:
			var header: int = type | (flag if form == 1 else 0)
			var need: int = bodies[type][form]
			cases += 1
			var exact: StreamPeerBuffer = _buffer_of(_framed_value(header, _zero_bytes(need)))
			var value: Variant = serializer.decode(exact)
			if (typeof(value) == type or type == TYPE_NIL) and exact.get_available_bytes() == 0:
				exact_ok += 1
			else:
				print("  exact size not accepted: type ", type, " form ", form, " got ", value)
			if need > 0:
				var short: StreamPeerBuffer = _buffer_of(_framed_value(header, _zero_bytes(need - 1)))
				if serializer.decode(short) == null and short.get_available_bytes() == 0:
					short_refused += 1
				else:
					print("  one byte short not refused: type ", type, " form ", form)
			else:
				short_refused += 1
			# A declared size larger than the type needs is consumed in full: the next value is read in place
			var longer: StreamPeerBuffer = _buffer_of(_framed_value(header, _zero_bytes(need + 8)) + _framed_value(TYPE_INT, PackedByteArray([77, 0, 0, 0])))
			var first: Variant = serializer.decode(longer)
			if (typeof(first) == type or type == TYPE_NIL) and serializer.decode(longer) == 77:
				long_aligned += 1
			else:
				print("  longer size not aligned: type ", type, " form ", form)
	_check(exact_ok == cases and short_refused == cases and long_aligned == cases and _warnings.errors == 0, "every allowed type, with and without the 64 bit flag (%d cases): the exact size is accepted (%d), one byte short is refused (%d), 8 bytes too many is read in full and the next value is in place (%d), %d engine errors (0)" % [cases, exact_ok, short_refused, long_aligned, _warnings.errors])
	# Header types at or above the engine's type count, and ones that a shift would wrap: refused, no engine error
	_warnings.errors = 0
	var refused_types: int = 0
	for bad_type: int in [21, 38, 39, 64, 65, 66, 128, 129, 255]:
		var buffer: StreamPeerBuffer = _buffer_of(_framed_value(bad_type, _zero_bytes(16)))
		if serializer.decode(buffer) == null and buffer.get_available_bytes() == 0:
			refused_types += 1
		else:
			print("  type not refused: ", bad_type)
	_check(refused_types == 9 and _warnings.errors == 0, "header types 21, 38, 39, 64, 65, 66, 128, 129 and 255 are refused and skipped: %d of 9, %d engine errors (0)" % [refused_types, _warnings.errors])

	# Whole packets of 8 byte values through the real handlers: a declared size of 4 with an
	# int header and no body, and a header type of 65 (the shift would read it as a bool)
	var tick: int = NetworkTime.tick + 6
	var identifier: _NetworkIdentifier = NetworkIdentityServer._get_identifier_of(_probe)
	_probe.set_multiplayer_authority(OTHER_PEER)
	var shapes: Dictionary = {"no body": TYPE_INT, "type 65": 65}
	for shape: String in shapes:
		var state: PackedByteArray = _value_packet(tick + 1, identifier, shapes[shape], _sync._max_packet_size * 2)
		var input_body: PackedByteArray = _value_packet(tick + 2, identifier, shapes[shape], _sync._max_packet_size * 2 * NetworkRollback.input_redundancy - 8)
		var input: StreamPeerBuffer = StreamPeerBuffer.new()
		NetworkSchemas.varuint().encode(input_body.size(), input)
		input.put_data(input_body)
		_warnings.errors = 0
		var start: int = Time.get_ticks_msec()
		_sync._handle_full_state(OTHER_PEER, state)
		_sync._handle_input(OTHER_PEER, input.data_array)
		var elapsed: int = Time.get_ticks_msec() - start
		_check(state.size() > 900 and input_body.size() > 3900 and _warnings.errors == 0 and elapsed < TIME_BOUND_MSEC, "a state packet of %d bytes and an input packet of %d bytes made of 8 byte values (%s): %d engine errors (0), %d ms (limit %d)" % [state.size(), input.get_size(), shape, _warnings.errors, elapsed, TIME_BOUND_MSEC])

## A packet of frames of the probe, each holding two 8 byte values (a declared size of 4
## and the header only), as many as fit under limit bytes. The probe is named by its id.
func _value_packet(tick: int, identifier: _NetworkIdentifier, header: int, limit: int) -> PackedByteArray:
	var frame_header: StreamPeerBuffer = StreamPeerBuffer.new()
	NetworkSchemas._netref().encode(_NetworkIdentityReference.of_id(identifier.get_local_id()), frame_header)
	var values: PackedByteArray = _framed_value(header, PackedByteArray()) + _framed_value(header, PackedByteArray())
	var frame: StreamPeerBuffer = StreamPeerBuffer.new()
	frame.put_data(frame_header.data_array)
	NetworkSchemas.varuint().encode(values.size(), frame)
	frame.put_data(values)
	var packet: PackedByteArray = PackedByteArray([0, 0, 0, 0])
	packet.encode_u32(0, tick)
	while packet.size() + frame.get_size() <= limit:
		packet.append_array(frame.data_array)
	return packet

func _zero_bytes(count: int) -> PackedByteArray:
	var zeros: PackedByteArray = PackedByteArray()
	zeros.resize(count)
	return zeros

# The variant fallback decodes only fixed-size values, and skips what it refuses.
func _variant_type_checks() -> void:
	var serializer: NetworkSchemaSerializer = NetworkSchemas.variant()
	var honest: Array = [null, true, false, 0, -5, 12345, 1 << 40, 0.37, -1e300, Vector2(3.5, -4.25), Vector2i(3, -4), Rect2(1, 2, 3, 4), Rect2i(1, 2, 3, 4), Vector3(1, 2, 3), Vector3i(1, 2, 3), Transform2D(0.5, Vector2(1, 2)), Vector4(1, 2, 3, 4), Vector4i(1, 2, 3, 4), Plane(Vector3.UP, 2.0), Quaternion(0, 0, 0, 1), AABB(Vector3.ONE, Vector3.ONE), Basis.IDENTITY, Transform3D.IDENTITY, Projection.IDENTITY, Color(0.25, 0.5, 0.75, 1.0)]
	var round_trips: int = 0
	for value: Variant in honest:
		var buffer: StreamPeerBuffer = StreamPeerBuffer.new()
		serializer.encode(value, buffer)
		var read: StreamPeerBuffer = _buffer_of(buffer.data_array)
		if serializer.decode(read) == value and read.get_available_bytes() == 0:
			round_trips += 1
		else:
			print("  round trip failed for ", value, " of type ", typeof(value))
	_check(round_trips == honest.size(), "every fixed-size type round trips through the variant serializer (%d of %d)" % [round_trips, honest.size()])
	var refused_values: Array = ["text", &"name", NodePath("a/b"), PackedStringArray(["a"]), ["a"], {"a": 1}, PackedByteArray([1, 2, 3]), [1, 2], PackedInt32Array([1]), PackedVector2Array([Vector2.ONE])]
	var refused: int = 0
	for value: Variant in refused_values:
		var buffer: StreamPeerBuffer = StreamPeerBuffer.new()
		buffer.put_var(value, false)
		var read: StreamPeerBuffer = _buffer_of(buffer.data_array)
		if serializer.decode(read) == null and read.get_available_bytes() == 0:
			refused += 1
		else:
			print("  not refused: ", value, " of type ", typeof(value))
	_check(refused == refused_values.size(), "strings, names, paths, containers and packed arrays are read as null and skipped (%d of %d)" % [refused, refused_values.size()])
	# What follows a refused value is still read in place
	var sequence: StreamPeerBuffer = StreamPeerBuffer.new()
	sequence.put_data(_framed(_string_variant("abc".to_utf8_buffer())))
	sequence.put_var(77, false)
	var read_sequence: StreamPeerBuffer = _buffer_of(sequence.data_array)
	_check(serializer.decode(read_sequence) == null and serializer.decode(read_sequence) == 77, "a refused value is skipped, and the value after it is read in place")

	# Every property this game synchronises, read from its scenes, is of an allowed type
	var allowed: Array = [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_VECTOR2]
	var seen: Dictionary = {}
	var checked: int = 0
	var bad: PackedStringArray = PackedStringArray()
	for scene_path: String in ["res://scenes/bot.tscn", "res://scenes/world_object.tscn", "res://scenes/pickup_spot.tscn"]:
		var root: Node = (load(scene_path) as PackedScene).instantiate()
		var stack: Array[Node] = [root]
		while not stack.is_empty():
			var node: Node = stack.pop_back()
			stack.append_array(node.get_children())
			for list_name: String in ["state_properties", "input_properties", "properties"]:
				if not list_name in node:
					continue
				var base: Node = (node.get("root") as Node) if "root" in node else node.get_parent()
				for entry: String in node.get(list_name) as Array:
					var parts: PackedStringArray = entry.split(":")
					var target: Node = base.get_node_or_null(parts[0]) if parts[0] != "" else base
					var value: Variant = target.get(parts[1]) if target != null else null
					checked += 1
					seen[type_string(typeof(value))] = true
					if not typeof(value) in allowed:
						bad.append("%s %s" % [scene_path, entry])
					elif typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_BOOL or typeof(value) == TYPE_VECTOR2:
						var buffer: StreamPeerBuffer = StreamPeerBuffer.new()
						serializer.encode(value, buffer)
						if serializer.decode(_buffer_of(buffer.data_array)) != value:
							bad.append("round trip %s %s" % [scene_path, entry])
		root.free()
	_check(checked > 50 and bad.is_empty(), "the %d synchronised properties of the bot, world object and pickup scenes are all of the types %s and round trip (types seen: %s; bad: %s)" % [checked, "bool, int, float, Vector2", ", ".join(PackedStringArray(seen.keys())), ", ".join(bad)])

	# What the restriction costs: the time of 20000 decodes of a Vector2 property
	var writer: StreamPeerBuffer = StreamPeerBuffer.new()
	for i: int in 20000:
		serializer.encode(Vector2(3.5, -4.25), writer)
	var reader: StreamPeerBuffer = _buffer_of(writer.data_array)
	var start: int = Time.get_ticks_usec()
	for i: int in 20000:
		serializer.decode(reader)
	var micros: int = Time.get_ticks_usec() - start
	_check(micros < 100000, "20000 Vector2 decodes through the variant serializer take %d us (limit 100000)" % micros)

# NetworkTime.stop() is what resets a session: it must empty the per-peer log
# tables of the command server and of the tickrate handshake. Run last, as it stops the clock.
func _stop_checks() -> void:
	var command_table: Dictionary = NetworkCommandServer._unknown_command_limit._last_msec
	var tickrate_table: Dictionary = NetworkTime._tickrate_handshake._mismatch_warning_limit._last_msec
	NetworkCommandServer._handle_command(13, 250, PackedByteArray())
	NetworkTime._tickrate_handshake._handle_tickrate_mismatch(13, NetworkTime.tickrate + 1)
	var identity_table: Dictionary = NetworkIdentityServer._refusal_limit._last_msec
	NetworkIdentityServer._handle_ids(13, _crash_length)
	var held: bool = command_table.has(13) and tickrate_table.has(13) and identity_table.has(13)
	NetworkTime.stop()
	_check(held and command_table.is_empty() and tickrate_table.is_empty() and identity_table.is_empty(), "NetworkTime.stop() empties the command server, handshake and identity tables (peer held before: %s, %d, %d and %d entries after)" % [held, command_table.size(), tickrate_table.size(), identity_table.size()])

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
