extends Node
## Regression test for active unmerged geminiceo fix (G-32) against origin/main (c05420e).
## Fails on origin/main without the fix: _get_earliest_expired_hole() returns PeerA's tick
## instead of PeerB's earlier expired hole.
## Run:
##   godot --headless --path . res://tests/test_security_audit.tscn
## Exits 0 when every check passes, 1 otherwise.

const TIMEOUT_SECONDS: float = 30.0
const PORT: int = 25341

class SimStub extends Node:
	var a: int = 0
	func _rollback_tick(_delta: float, _tick: int, _is_fresh: bool) -> void:
		a += 1

class InputStub extends Node:
	var v: int = 0

var _failures: int = 0
var _checks: int = 0

func _ready() -> void:
	get_tree().create_timer(TIMEOUT_SECONDS).timeout.connect(_on_timeout)
	_run()

func _on_timeout() -> void:
	print("FAIL timeout, security audit test did not finish")
	get_tree().quit(1)

func _check(ok: bool, label: String) -> void:
	_checks += 1
	if ok:
		print("PASS ", label)
	else:
		_failures += 1
		print("FAIL ", label)

func _make_pair(label: String, owner_peer: int) -> Array[Node]:
	var sim := SimStub.new()
	sim.name = label
	add_child(sim)
	var inp := InputStub.new()
	inp.name = label + "Input"
	sim.add_child(inp)
	inp.set_multiplayer_authority(owner_peer)
	NetworkHistoryServer.register_rollback_state(sim, ^"a")
	NetworkHistoryServer.register_rollback_input(inp, ^"v")
	RollbackSimulationServer.register(Callable(sim, "_rollback_tick"))
	RollbackSimulationServer.register_rollback_input_for(sim, inp)
	return [sim, inp]

func _put_input(inp: Node, tick: int, val: int) -> void:
	var snap := _Snapshot.new(tick)
	snap.set_property(inp, ^"v", val)
	snap.set_auth(inp, true)
	if NetworkHistoryServer._merge_rollback_input(snap):
		NetworkSynchronizationServer._on_input.emit(snap)

func _run() -> void:
	var peer := ENetMultiplayerPeer.new()
	var err: Error = peer.create_server(PORT, 4)
	if err != OK:
		print("FAIL create_server: ", err)
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	await get_tree().process_frame
	var pair_a: Array[Node] = _make_pair("PeerA", 2)
	var pair_b: Array[Node] = _make_pair("PeerB", 3)
	var sim_a: Node = pair_a[0]
	var inp_a: Node = pair_a[1]
	var inp_b: Node = pair_b[1]

	# Deliver PeerB's inputs for ticks 10 and 12 (creating a real open hole at tick 11).
	while NetworkTime.tick < 12:
		await get_tree().process_frame
	_put_input(inp_b, 10, 1)
	_put_input(inp_b, 12, 2)
	# Wait until tick 23 (age = 12, hole 11 is still open so the rollback loop has not resolved it),
	# then pause NetworkTime and step _tick to 24 (age = 13 > 12, hole 11 just expired).
	while NetworkTime.tick < 23:
		await get_tree().process_frame
	NetworkTime.set_process(false)
	NetworkTime._tick = 24
	var now: int = NetworkTime.tick
	# PeerA (registered first) has an accepted pre-start tick at now - 2 (22) with first input at 23,
	# while PeerB (registered second) has its expired hole at tick 11.
	var tick_a_later: int = now - 2
	_put_input(inp_a, tick_a_later + 1, 1)
	for t: int in range(tick_a_later, now):
		var st := _Snapshot.new(t)
		st.set_property(sim_a, ^"a", 0)
		st.set_auth(sim_a, t <= tick_a_later)
		NetworkHistoryServer._merge_rollback_state(st)

	var got: int = RollbackSimulationServer._get_earliest_expired_hole()
	_check(got == 11,
		"G-32: _get_earliest_expired_hole() returns minimum across all peers (got %d, want 11; PeerA had %d)" % [got, tick_a_later])

	NetworkTime.set_process(true)
	NetworkTime.stop()
	peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	print("%d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)
