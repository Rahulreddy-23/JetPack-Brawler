extends Node
## A diff state carries only the properties that changed since what the host last
## sent. A client must lay it over the last authoritative state it has, never over
## its own prediction for that tick. This runs as a client (connecting to a port
## with nothing listening, so its tick stays at 0) and feeds diffs through the
## real handlers, checking both of the client's stores: the per-object history and
## the per-tick snapshot. Run:
##   godot --headless --path . res://tests/test_netfox_diffs.tscn -- --port=N
## Exits 0 when all checks pass, 1 otherwise (also on timeout).

const Probe: GDScript = preload("res://tests/netfox_probe.gd")
const TIMEOUT_SECONDS: float = 30.0
const SERVER_PEER: int = 1
const GUESS: int = 99

var _probe: Node = null
var _failures: int = 0
var _sync: _NetworkSynchronizationServer = null

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

# What the client stores for the probe at tick: {a, b, auth} from the per-object
# history, and the same from the per-tick snapshot. Empty values when absent.
func _history_of(tick: int) -> Dictionary:
	var snapshot: _ObjectSnapshot = NetworkHistoryServer._rb_state_history.get_latest_snapshot(tick, _probe)
	if snapshot == null:
		return {}
	return {"a": snapshot.get_value(Probe.PROP_A), "b": snapshot.get_value(Probe.PROP_B), "auth": snapshot.is_auth()}

func _tick_snapshot_of(tick: int, sync: bool = false) -> Dictionary:
	var buffer: _HistoryBuffer = NetworkHistoryServer._sync_state_snapshots if sync else NetworkHistoryServer._rb_state_snapshots
	var snapshot: _Snapshot = buffer.get_at(tick)
	if snapshot == null:
		return {}
	return {"a": snapshot.get_property(_probe, Probe.PROP_A), "b": snapshot.get_property(_probe, Probe.PROP_B), "auth": snapshot.is_auth(_probe)}

# The client's own prediction for a tick: not authoritative, in both stores.
func _guess(tick: int, a: int, b: int) -> void:
	var object_snapshot: _ObjectSnapshot = NetworkHistoryServer._rb_state_history.ensure_snapshot(tick, _probe, false)
	object_snapshot.set_value(Probe.PROP_A, a)
	object_snapshot.set_value(Probe.PROP_B, b)
	var snapshot: _Snapshot = NetworkHistoryServer._rb_state_snapshots.get_at(tick)
	if snapshot == null:
		snapshot = _Snapshot.new(tick)
		NetworkHistoryServer._rb_state_snapshots.set_at(tick, snapshot)
	snapshot.set_property(_probe, Probe.PROP_A, a)
	snapshot.set_property(_probe, Probe.PROP_B, b)
	snapshot.set_auth(_probe, false)

func _full(tick: int, value: int) -> void:
	_sync._handle_full_state(SERVER_PEER, _probe.full_state_packet(tick, value))

func _diff_a(tick: int, a: int) -> void:
	_sync._handle_diff_state(SERVER_PEER, _probe.diff_packet_of(tick, {Probe.PROP_A: a}, false))

func _expect(found: Dictionary, a: int, b: int, label: String) -> void:
	_check(found.get("a") == a and found.get("b") == b and found.get("auth") == true, "%s: authoritative a=%s b=%s (want a=%d b=%d)" % [label, str(found.get("a")), str(found.get("b")), a, b])

func _run() -> void:
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	peer.create_client("127.0.0.1", LaunchArgs.parse(OS.get_cmdline_user_args()).port)
	multiplayer.multiplayer_peer = peer
	_sync = NetworkSynchronizationServer
	_probe = Probe.new()
	add_child(_probe)
	_probe.register()
	_probe.set_multiplayer_authority(SERVER_PEER)
	_check(not multiplayer.is_server(), "running as a client")

	# Public query: no state from the authority yet, only a local prediction.
	_guess(5, GUESS, GUESS)
	_check(not NetworkHistoryServer.has_authoritative_state(_probe), "client: a subject with only local predictions has no authoritative state")

	# Host full state at T-1: a=1, b=1. The client's guess at T: a=99, b=99. The host's
	# diff at T carries a=2 only; the host's b is still 1.
	_full(9, 1)
	_check(NetworkHistoryServer.has_authoritative_state(_probe), "client: true after the first state received from the authority")
	_guess(10, GUESS, GUESS)
	_diff_a(10, 2)
	_expect(_history_of(10), 2, 1, "diff over a guess, per-object history")
	_expect(_tick_snapshot_of(10), 2, 1, "diff over a guess, per-tick snapshot")

	# No snapshot at T at all: the per-object history carries forward the latest one
	# at or before T, which is the client's guess at T-1, not the host's state at T-2.
	_full(19, 1)
	_guess(20, GUESS, GUESS)
	_diff_a(21, 2)
	_expect(_history_of(21), 2, 1, "diff with no snapshot at the tick, per-object history")
	_expect(_tick_snapshot_of(21), 2, 1, "diff with no snapshot at the tick, per-tick snapshot")

	# A second diff for the same tick lays over the first one, not over the base.
	_sync._handle_diff_state(SERVER_PEER, _probe.diff_packet_of(21, {Probe.PROP_B: 5}, false))
	_expect(_history_of(21), 2, 5, "second diff for the same tick")

	# The same for synchronized state, which has no prediction to fall back on.
	_sync._handle_full_sync(SERVER_PEER, _probe.full_sync_packet(30, 1))
	_sync._handle_diff_sync(SERVER_PEER, _probe.diff_packet_of(31, {Probe.PROP_A: 2}, true))
	var sync_snapshot: Dictionary = _tick_snapshot_of(31, true)
	_expect(sync_snapshot, 2, 1, "sync diff after a sync full state, per-tick snapshot")

	# Completion is for diffs only. A full state is whole already, so the merge of a
	# state that is not marked as a diff does not walk back for a base: a partial
	# snapshot handed to it stays partial, and the same snapshot marked as a diff is
	# completed.
	_full(40, 1)
	NetworkHistoryServer._merge_rollback_state(_probe.snapshot_of(41, {Probe.PROP_A: 2}))
	_check(_tick_snapshot_of(41).get("a") == 2 and _tick_snapshot_of(41).get("b") == null, "a merge not marked as a diff is not completed, per-tick snapshot (b is %s)" % str(_tick_snapshot_of(41).get("b")))
	NetworkHistoryServer._merge_rollback_state(_probe.snapshot_of(42, {Probe.PROP_A: 2}), true)
	_expect(_tick_snapshot_of(42), 2, 1, "the same merge marked as a diff is completed, per-tick snapshot")

	NetworkHistoryServer._merge_synchronizer_state(_probe.snapshot_of(32, {Probe.PROP_A: 2}))
	_check(_tick_snapshot_of(32, true).get("a") == 2 and _tick_snapshot_of(32, true).get("b") == null, "a sync merge not marked as a diff is not completed (b is %s)" % str(_tick_snapshot_of(32, true).get("b")))

	# A lost diff. The host: full at 100 (a=1, b=1); diff at 101 (a=2, b=2) lost; then
	# a diff per tick that changes only a; a full state one interval after the first.
	# Until that full state the client's b stays wrong: a diff cannot repair what an
	# earlier lost diff carried. After it everything is right again.
	var interval: int = _sync._rb_full_interval
	_full(100, 1)
	for tick: int in range(102, 100 + interval):
		_diff_a(tick, tick - 99)
	var last: int = 100 + interval - 1
	_check(_history_of(last).get("b") == 1, "after a lost diff the client's b is still the stale 1 at tick %d (host has 2)" % last)
	_sync._handle_full_state(SERVER_PEER, _probe.full_state_packet(100 + interval, 2))
	_expect(_history_of(100 + interval), 2, 2, "full state one interval after the first")
	_diff_a(100 + interval + 1, 7)
	_expect(_history_of(100 + interval + 1), 7, 2, "diff after the repairing full state")

	# Negative cases of the public query, each on a subject of its own.
	var refused: Node = Probe.new()
	add_child(refused)
	refused.register("RefusedSubject")
	refused.set_multiplayer_authority(SERVER_PEER)
	NetworkRollback._history_floor = 500
	_sync._handle_full_state(SERVER_PEER, refused.full_state_packet(450, 1))
	NetworkRollback._history_floor = 0
	_check(not NetworkHistoryServer.has_authoritative_state(refused), "client: a snapshot whose tick is refused does not set it")
	_sync._handle_full_sync(SERVER_PEER, refused.full_sync_packet(460, 1))
	_check(NetworkHistoryServer.has_authoritative_state(refused), "client: a received synchronized state sets it")
	NetworkHistoryServer.deregister(refused)
	_check(not NetworkHistoryServer.has_authoritative_state(refused), "client: deregistering the node clears it")
	var freed: Object = Node.new()
	freed.free()
	_check(not NetworkHistoryServer.has_authoritative_state(freed), "client: a freed subject is not authoritative and raises no error")

	# A stop forgets it, and the next state received sets it again.
	NetworkTime.stop()
	_check(not NetworkHistoryServer.has_authoritative_state(_probe), "client: false again after NetworkTime stops")
	_full(200, 1)
	_check(NetworkHistoryServer.has_authoritative_state(_probe), "client: true again after the first state of the next session")

	print("%d failures" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)
