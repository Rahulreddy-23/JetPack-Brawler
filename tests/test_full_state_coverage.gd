extends Node
## With diff states on, every subject a host sends rollback state for must get a
## full state at least once per full_state_interval ticks. The host's own full-state
## schedule used to count calls to _synchronize_state, which come once or more per
## tick (a re-simulation sends the tick again), and fire the full state on whatever
## call happened to be due: with two passes per tick that was always the first pass,
## before a client-input subject has its input and is in the snapshot, so such a
## subject was almost never sent in full.
## This host has one connected peer (an in-process client on its own SceneMultiplayer,
## only there to make get_peers() non-empty) and three probe subjects:
##   A, in every pass;
##   B, only in the second pass of each tick (its input arrives late);
##   C, from tick LATE_START on (it spawns, or its input first arrives, mid-run).
## It calls the real _synchronize_state for a run of ticks with the sends captured,
## then checks the gaps between full states for each subject, and that diffs are
## still sent between them. Run:
##   godot --headless --path . res://tests/test_full_state_coverage.tscn
## Port: TEST_PORT, default below. Exits 0 when all checks pass, 1 otherwise.

const Probe: GDScript = preload("res://tests/netfox_probe.gd")
const TIMEOUT_SECONDS: float = 30.0
const DEFAULT_PORT: int = 25119
const FIRST_TICK: int = 5000
const TICKS: int = 120
const LATE_START: int = FIRST_TICK + 50

## Records the subjects written to full-state packets for the rollback state.
class Recorder extends _DenseSnapshotSerializer:
	var full: Array[Dictionary] = []
	var watched: _PropertyPool = null

	func write_for(peer: int, snapshot: _Snapshot, properties: _PropertyPool, filter: Callable = _default_filter) -> Array[PackedByteArray]:
		if properties == watched:
			for subject: Object in properties.get_subjects():
				if filter.call(subject) and snapshot.is_auth(subject):
					full.append({"subject": subject, "tick": snapshot.tick})
		return super.write_for(peer, snapshot, properties, filter)

## Records the properties of every subject written to a diff-state packet.
class DiffRecorder extends _SparseSnapshotSerializer:
	var diffs: Array[Dictionary] = []
	var watched: _PropertyPool = null

	func write_for(peer: int, snapshot: _Snapshot, properties: _PropertyPool, filter: Callable = _default_filter) -> Array[PackedByteArray]:
		if properties == watched:
			for subject: Object in snapshot.get_subjects():
				diffs.append({"subject": subject, "tick": snapshot.tick, "properties": snapshot.get_subject_properties(subject)})
		return super.write_for(peer, snapshot, properties, filter)

## Takes the place of the command server for the two state commands, so nothing
## is put on the network.
class Capture extends _NetworkCommandServer:
	var sent: int = 0

	func send_command(_idx: int, _data: PackedByteArray, _target_peer: int = 0, _mode: MultiplayerPeer.TransferMode = MultiplayerPeer.TRANSFER_MODE_RELIABLE, _channel: int = 0) -> void:
		sent += 1

var _failures: int = 0
var _probes: Dictionary = {}

func _ready() -> void:
	get_tree().create_timer(TIMEOUT_SECONDS).timeout.connect(_on_timeout)
	_run()

func _port() -> int:
	var text: String = OS.get_environment("TEST_PORT")
	return text.to_int() if text.is_valid_int() else DEFAULT_PORT

func _on_timeout() -> void:
	print("FAIL timeout, test did not finish")
	get_tree().quit(1)

func _check(ok: bool, label: String) -> void:
	if ok:
		print("PASS ", label)
	else:
		_failures += 1
		print("FAIL ", label)

func _make_probe(probe_name: String) -> Node:
	var probe: Node = Probe.new()
	add_child(probe)
	probe.register(probe_name)
	_probes[probe_name] = probe
	return probe

# The snapshot the host's rollback loop would hold for one pass of a tick.
func _set_pass(tick: int, names: Array[String]) -> void:
	var snapshot: _Snapshot = _Snapshot.new(tick)
	for probe_name: String in names:
		var probe: Node = _probes[probe_name]
		snapshot.set_property(probe, Probe.PROP_A, tick)
		snapshot.set_property(probe, Probe.PROP_B, tick % 7)
		snapshot.set_auth(probe, true)
	NetworkHistoryServer._rb_state_snapshots.set_at(tick, snapshot)

# The state of the named subjects at a tick, as [a, b] pairs, in one pass.
func _set_state(tick: int, values: Dictionary) -> void:
	var snapshot: _Snapshot = _Snapshot.new(tick)
	for probe_name: String in values:
		var probe: Node = _probes[probe_name]
		snapshot.set_property(probe, Probe.PROP_A, (values[probe_name] as Array)[0])
		snapshot.set_property(probe, Probe.PROP_B, (values[probe_name] as Array)[1])
		snapshot.set_auth(probe, true)
	NetworkHistoryServer._rb_state_snapshots.set_at(tick, snapshot)

func _diff_properties(diff_recorder: DiffRecorder, probe_name: String, tick: int) -> Array:
	var result: Array = []
	for row: Dictionary in diff_recorder.diffs:
		if row["subject"] == _probes[probe_name] and row["tick"] == tick:
			result.append_array(row["properties"] as Array)
	return result

func _full_ticks(recorder: Recorder, probe_name: String) -> Array[int]:
	var result: Array[int] = []
	for row: Dictionary in recorder.full:
		if row["subject"] == _probes[probe_name] and not result.has(row["tick"] as int):
			result.append(row["tick"] as int)
	result.sort()
	return result

func _check_gaps(recorder: Recorder, probe_name: String, first_tick: int) -> void:
	var interval: int = NetworkSynchronizationServer._rb_full_interval
	var ticks: Array[int] = _full_ticks(recorder, probe_name)
	var worst: int = 0
	var previous: int = first_tick
	for tick: int in ticks:
		worst = maxi(worst, tick - previous)
		previous = tick
	worst = maxi(worst, FIRST_TICK + TICKS - 1 - previous)
	_check(not ticks.is_empty() and ticks[0] <= first_tick + interval and worst <= interval, "subject %s: %d full states, first at +%d, longest gap %d ticks (interval %d)" % [probe_name, ticks.size(), (ticks[0] - first_tick) if not ticks.is_empty() else -1, worst, interval])

func _run() -> void:
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	peer.create_server(_port(), 4)
	multiplayer.multiplayer_peer = peer

	# One connected peer, on a SceneMultiplayer of its own below a node of its own.
	var remote: Node = Node.new()
	remote.name = "Remote"
	add_child(remote)
	var remote_api: SceneMultiplayer = SceneMultiplayer.new()
	get_tree().set_multiplayer(remote_api, remote.get_path())
	var client: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	client.create_client("127.0.0.1", _port())
	remote_api.multiplayer_peer = client
	while multiplayer.get_peers().is_empty():
		await get_tree().process_frame

	var sync: _NetworkSynchronizationServer = NetworkSynchronizationServer
	sync._rb_enable_diffs = true
	var recorder: Recorder = Recorder.new(sync._schemas, NetworkIdentityServer)
	recorder.max_packet_size = sync._max_packet_size
	recorder.watched = sync._rb_owned_state_properties
	sync._dense_serializer = recorder
	var diff_recorder: DiffRecorder = DiffRecorder.new(sync._schemas, NetworkIdentityServer)
	diff_recorder.max_packet_size = sync._max_packet_size
	diff_recorder.watched = sync._rb_owned_state_properties
	sync._sparse_serializer = diff_recorder
	var capture: Capture = Capture.new()
	var diffs: Capture = Capture.new()
	sync._cmd_full_state = capture.register_command(func(_s: int, _d: PackedByteArray) -> void: pass)
	sync._cmd_diff_state = diffs.register_command(func(_s: int, _d: PackedByteArray) -> void: pass)

	_make_probe("A")
	_make_probe("B")
	_make_probe("C")
	_check(not multiplayer.get_peers().is_empty(), "the host has a peer to send to")

	# One call before the run shifts the parity of the call count, so that a schedule
	# that counts calls is due on the first pass of every tick.
	_set_pass(FIRST_TICK - 1, ["A"])
	sync._synchronize_state(FIRST_TICK - 1)
	for tick: int in range(FIRST_TICK, FIRST_TICK + TICKS):
		var present: Array[String] = ["A"]
		if tick >= LATE_START:
			present.append("C")
		_set_pass(tick, present)
		sync._synchronize_state(tick)
		var second: Array[String] = present.duplicate()
		second.append("B")
		_set_pass(tick, second)
		sync._synchronize_state(tick)

	_check_gaps(recorder, "A", FIRST_TICK)
	_check_gaps(recorder, "B", FIRST_TICK)
	_check_gaps(recorder, "C", LATE_START)
	_check(diffs.sent > 0, "diff states are still sent between the full states (%d diff packets, %d full packets)" % [diffs.sent, capture.sent])

	# A diff is relative to the latest thing sent for that subject, however earlier ticks
	# are re-simulated afterwards. B is sent at tick 7000 as (1, 1); tick 7001 has a pass
	# without B (its input has not arrived); tick 7000 is re-simulated and B is sent again
	# as (2, 5); then tick 7001 has B at (3, 1). What the client holds as the latest state
	# before 7001 is (2, 5), so the diff must carry both properties: b goes 5 to 1.
	_set_state(7000, {"A": [0, 0], "B": [1, 1]})
	sync._synchronize_state(7000)
	_set_state(7001, {"A": [1, 0]})
	sync._synchronize_state(7001)
	_set_state(7000, {"A": [0, 0], "B": [2, 5]})
	sync._synchronize_state(7000)
	_set_state(7001, {"A": [1, 0], "B": [3, 1]})
	sync._synchronize_state(7001)
	var carried: Array = _diff_properties(diff_recorder, "B", 7001)
	_check(carried.has(Probe.PROP_A) and carried.has(Probe.PROP_B), "after a re-simulation the diff for B at tick 7001 carries a and b (%s)" % str(carried))

	print("%d failures" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)
