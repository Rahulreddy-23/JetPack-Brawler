extends Node
## The host's rule for a rollback subject whose input has a hole: the input of one tick is
## missing while the inputs of ticks after it are there (they overtook it on the wire).
##   - While the hole is open the subject is not simulated on the ticks after it, and no state
##     built on its stale start state is recorded as authoritative (so none is sent).
##   - When the missing input arrives in time, the subject is simulated from the hole on and
##     the states from there are authoritative.
##   - The hole expires on the host's clock: a later input exists and the host's tick is more
##     than the input allowance (3 times input_redundancy) past the hole. Then the hole tick
##     stays unsimulated (no input is made up, a one-tick press before it is not repeated), its
##     carried-over state becomes the state of record, and the subject goes on from the real
##     inputs after it. An expired hole stays expired when the ticks are simulated again.
##   - Later than the allowance is the same as lost: the host refuses input for a tick older
##     than that. A straggler after the expiry changes nothing; input exactly at the allowance
##     is accepted, one tick older is refused; a stream of old input is refused, causes no
##     simulation of ticks older than the allowance, and one warning per peer (not one per
##     snapshot) in the log; the count of refused input per peer is readable, forgotten after a
##     second, when the peer leaves and on reset.
##   - Input for a tick before a subject's first input that the host has already passed (inputs
##     10 and 11 arrive before 8 and 9 and the host sends the carried-over states of 8 and 9)
##     is refused, so no state sent is replaced; an ordinary join still starts on its first tick.
##   - The scan for expired holes, which runs once per rollback loop, takes little time with
##     six remote inputs (reported as SCAN_COST).
##   - A tick with no input at all before it (the subject has not started to send) is no hole:
##     the subject is simulated from its first input tick, without delay.
## This hosts in this process with probe subjects registered with netfox's real history and
## simulation servers, and hands them input as the packet handler would (merge, then the
## signal netfox's rollback listens to). A subject without inputs is simulated on every tick.
## Run:
##   godot --headless --path . res://tests/test_hole_rule.tscn
## Port: TEST_PORT, default below. Exits 0 when all checks pass, 1 otherwise.

const TIMEOUT_SECONDS: float = 60.0
const DEFAULT_PORT: int = 25339
const INPUT_OWNER: int = 2
## A one-tick press: the input value of the tick before the lost one.
const PRESS: int = 77
## The most one call of the expired-hole scan may take on average, in microseconds, with six
## remote inputs (a frame is 16 000 us at 60 fps; the scan runs once per rollback loop).
const SCAN_MAX_MICROSECONDS: float = 500.0
const SCAN_CALLS: int = 2000

## The subject: counts how often it was simulated and notes what it used.
class SimProbe extends Node:
	var a: int = 0
	var log: Array[Dictionary] = []
	var input_node: Node = null

	func _rollback_tick(_delta: float, tick: int, is_fresh: bool) -> void:
		a += 1
		log.append({"tick": tick, "v": input_node.get("v"), "fresh": is_fresh})

	func simulated(tick: int) -> bool:
		for entry: Dictionary in log:
			if entry["tick"] == tick:
				return true
		return false

	func times_simulated_with(value: int) -> int:
		var count: int = 0
		for entry: Dictionary in log:
			if entry["v"] == value and entry["fresh"] == true:
				count += 1
		return count

	func last_used(tick: int) -> Dictionary:
		var found: Dictionary = {}
		for entry: Dictionary in log:
			if entry["tick"] == tick:
				found = entry
		return found

class InputProbe extends Node:
	var v: int = 0

## Counts what is logged above trace level (netfox warnings go to print and push_warning).
class LogCounter extends Logger:
	var count: int = 0
	var lines: Array[String] = []

	func _log_message(message: String, _error: bool) -> void:
		# The test's own PASS and FAIL lines are not what is counted.
		if not message.begins_with("PASS") and not message.begins_with("FAIL"):
			count += 1
			lines.append(message.strip_edges())

	func _log_error(_function: String, _file: String, _line: int, code: String, rationale: String, _editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		count += 1
		lines.append(rationale if not rationale.is_empty() else code)

## A subject without inputs, simulated on every tick.
class FreeProbe extends Node:
	var a: int = 0
	var ticks: Array[int] = []

	func _rollback_tick(_delta: float, tick: int, _is_fresh: bool) -> void:
		a += 1
		ticks.append(tick)

var _failures: int = 0
var _free: FreeProbe = null

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

func _wait_until_tick(tick: int) -> void:
	while NetworkTime.tick < tick:
		await get_tree().process_frame
	# Two more frames, so the rollback loop that follows has run.
	await get_tree().process_frame
	await get_tree().process_frame

# A subject with an input node owned by peer 2, registered with the real servers.
func _make_subject(subject_name: String, owner_peer: int = INPUT_OWNER) -> SimProbe:
	var sim: SimProbe = SimProbe.new()
	sim.name = subject_name
	add_child(sim)
	var input: InputProbe = InputProbe.new()
	input.name = subject_name + "Input"
	sim.add_child(input)
	sim.input_node = input
	input.set_multiplayer_authority(owner_peer)
	NetworkHistoryServer.register_rollback_state(sim, ^"a")
	NetworkHistoryServer.register_rollback_input(input, ^"v")
	RollbackSimulationServer.register(Callable(sim, "_rollback_tick"))
	RollbackSimulationServer.register_rollback_input_for(sim, input)
	return sim

# What the packet handler does with an input snapshot from the client that owns the input.
func _deliver(sim: SimProbe, tick: int, value: int) -> bool:
	var snapshot: _Snapshot = _Snapshot.new(tick)
	snapshot.set_property(sim.input_node, ^"v", value)
	snapshot.set_auth(sim.input_node, true)
	var merged: bool = NetworkHistoryServer._merge_rollback_input(snapshot)
	if merged:
		NetworkSynchronizationServer._on_input.emit(snapshot)
	return merged

func _authoritative(sim: SimProbe, tick: int) -> bool:
	var snapshot: _Snapshot = NetworkHistoryServer._get_rollback_state_snapshot(tick)
	return snapshot != null and snapshot.is_auth(sim)

func _count_authoritative(sim: SimProbe, first: int, last: int) -> int:
	var count: int = 0
	for tick: int in range(first, last + 1):
		count += 1 if _authoritative(sim, tick) else 0
	return count

func _count_simulated(sim: SimProbe, first: int, last: int) -> int:
	var count: int = 0
	for tick: int in range(first, last + 1):
		count += 1 if sim.simulated(tick) else 0
	return count

func _run() -> void:
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	peer.create_server(_port(), 4)
	multiplayer.multiplayer_peer = peer
	while NetworkTime.tick < 5:
		await get_tree().process_frame

	var redundancy: int = NetworkRollback.input_redundancy
	var allowance: int = RollbackSimulationServer._get_hole_allowance()
	_check(allowance == 3 * redundancy, "the input allowance is 3 times input_redundancy (%d ticks)" % allowance)

	_free = FreeProbe.new()
	_free.name = "FreeSubject"
	add_child(_free)
	NetworkHistoryServer.register_rollback_state(_free, ^"a")
	RollbackSimulationServer.register(Callable(_free, "_rollback_tick"))

	var sim: SimProbe = _make_subject("HoleSubject")
	_check(sim.is_multiplayer_authority() and not sim.input_node.is_multiplayer_authority(), "the subject is owned here, its input by peer %d" % INPUT_OWNER)

	# The first input of a subject that has not sent anything yet: no hole before it, no delay.
	var start: int = NetworkTime.tick + 4
	NetworkHistoryServer.push_rollback_state(sim, start - 3)
	NetworkHistoryServer.push_rollback_state(_free, start - 3)
	_deliver(sim, start, 10)
	await _wait_until_tick(start + 3)
	_check(sim.simulated(start), "a subject is simulated on its first input tick, with no start delay")
	_check(_count_authoritative(sim, start - 2, start + 1) == 4, "the ticks before the first input carry their state over as authoritative")

	# A hole that is filled in time: input of ticks around it arrives, then the hole's input.
	var hole: int = NetworkTime.tick + 2
	for tick: int in range(start + 1, hole):
		_deliver(sim, tick, 10 + tick - start)
	for tick: int in range(hole + 1, hole + redundancy + 1):
		_deliver(sim, tick, 10 + tick - start)
	await _wait_until_tick(hole + redundancy + 3)
	_check(not sim.simulated(hole), "the hole tick is not simulated")
	_check(_count_simulated(sim, hole + 1, hole + redundancy) == 0, "no tick after the open hole is simulated from the stale start state (%d were)" % _count_simulated(sim, hole + 1, hole + redundancy))
	_check(_count_authoritative(sim, hole + 1, hole + redundancy + 1) == 0, "no state after the open hole is recorded as authoritative (so none is sent)")
	var gaps: int = 0
	for tick: int in range(start, hole + redundancy):
		gaps += 0 if _free.ticks.has(tick) else 1
	_check(gaps == 0, "a subject without inputs was simulated on every tick meanwhile")
	_deliver(sim, hole, 10 + hole - start)
	await _wait_until_tick(hole + redundancy + 6)
	_check(_count_simulated(sim, hole, hole + redundancy) == redundancy + 1, "once the hole is filled every tick from the hole on is simulated")
	_check((sim.last_used(hole).get("v", -1) as int) == 10 + hole - start, "the hole tick used the input that arrived for it")
	_check(_count_authoritative(sim, hole + 1, hole + redundancy + 1) == redundancy + 1, "the states from the hole on are authoritative")

	# A hole whose input never arrives, with a one-tick press on the tick before it. Inputs far
	# ahead of it do not expire it: that is the host's clock.
	var second: int = NetworkTime.tick + 2
	var lost: int = second + 1
	for tick: int in range(hole + redundancy + 1, second):
		_deliver(sim, tick, 5)
	_deliver(sim, second, PRESS)
	for tick: int in range(lost + 1, lost + redundancy + 2):
		_deliver(sim, tick, 60 + tick - lost)
	await _wait_until_tick(lost + allowance - 2)
	_check(not sim.simulated(lost) and _count_simulated(sim, lost + 1, lost + redundancy + 1) == 0, "a hole stays open while the host's tick is at most %d past it, whatever input follows" % allowance)
	_check(_count_authoritative(sim, lost + 1, lost + 2) == 0, "no authoritative state while it is open (second hole)")
	await _wait_until_tick(lost + allowance + 3)
	_check(not sim.simulated(lost), "an expired hole is not simulated: no input is made up")
	_check(_authoritative(sim, lost + 1), "its carried-over state is the state of record")
	_check(_count_simulated(sim, lost + 1, lost + redundancy + 1) == redundancy + 1, "the subject goes on from the real inputs after the hole")
	_check(sim.times_simulated_with(PRESS) == 1, "the one-tick press before the lost input was applied once (%d)" % sim.times_simulated_with(PRESS))

	# Simulating the ticks again changes nothing: the expired hole stays expired.
	var before: int = sim.log.size()
	NetworkRollback.before_loop.connect(func() -> void: NetworkRollback.notify_resimulation_start(lost - 2), CONNECT_ONE_SHOT)
	await _wait_until_tick(NetworkTime.tick + 2)
	_check(sim.log.size() > before, "the ticks around the hole were simulated again")
	_check(not sim.simulated(lost) and _authoritative(sim, lost + 1) and _count_simulated(sim, lost + 1, lost + redundancy + 1) == redundancy + 1, "after simulating again the hole is still expired, still not simulated")

	# The straggler arrives after the expiry: refused, nothing changes. Later than the allowance is lost.
	var simulated_before: int = sim.log.size()
	var auth_before: int = _count_authoritative(sim, lost - 2, lost + redundancy + 1)
	_check(not _deliver(sim, lost, 99), "a straggler after the expiry is refused")
	await _wait_until_tick(NetworkTime.tick + 3)
	_check(not sim.simulated(lost) and sim.times_simulated_with(99) == 0, "the refused straggler was not simulated")
	_check(_count_authoritative(sim, lost - 2, lost + redundancy + 1) == auth_before, "the refused straggler changed no state of record")

	# Join, reordered: the inputs of two later ticks arrive before the first ones. The host passes
	# the first ticks (no input before them: carried over, authoritative, sent); then the first
	# ones arrive inside the allowance and are refused, so nothing sent is replaced.
	var joined: SimProbe = _make_subject("JoinSubject", 7)
	var first: int = NetworkTime.tick + 6
	NetworkHistoryServer.push_rollback_state(joined, first - 3)
	_deliver(joined, first + 2, 20)
	_deliver(joined, first + 3, 21)
	await _wait_until_tick(first + 5)
	var joined_auth: int = _count_authoritative(joined, first - 2, first + 2)
	_check(joined_auth == 5 and not joined.simulated(first) and not joined.simulated(first + 1), "ticks before the first accepted input are carried over as authoritative and not simulated (%d states)" % joined_auth)
	_check(not _deliver(joined, first, 8) and not _deliver(joined, first + 1, 9), "input for a tick before the first accepted input, which the host passed, is refused")
	await _wait_until_tick(NetworkTime.tick + 3)
	_check(not joined.simulated(first) and not joined.simulated(first + 1) and joined.simulated(first + 2), "the refused first inputs were not simulated, the subject runs from its first accepted input")
	_check(_count_authoritative(joined, first - 2, first + 2) == joined_auth, "no state of record was replaced")

	# An ordinary join after the host passed some ticks with no input at all: the carried-over
	# states of those ticks are not authoritative yet, so the first input is accepted.
	var starter: SimProbe = _make_subject("StarterSubject", 9)
	NetworkHistoryServer.push_rollback_state(starter, NetworkTime.tick - 3)
	await _wait_until_tick(NetworkTime.tick + 4)
	var starter_first: int = NetworkTime.tick - 2
	_check(_deliver(starter, starter_first, 30), "the first input of a subject is accepted after the host passed its tick, while nothing later is held")
	await _wait_until_tick(NetworkTime.tick + 2)
	_check(starter.simulated(starter_first), "and the subject is simulated from it")

	# Input exactly at the allowance is accepted, one tick older is refused.
	var counter: LogCounter = LogCounter.new()
	OS.add_logger(counter)
	var aged: SimProbe = _make_subject("AgeSubject", 5)
	var other: SimProbe = _make_subject("OtherSubject", 6)
	var now: int = NetworkTime.tick
	_check(_deliver(aged, now - allowance, 1), "input exactly %d ticks old is accepted" % allowance)
	_check(not _deliver(aged, now - allowance - 1, 2), "input %d ticks old is refused" % (allowance + 1))

	# A stream of old input, as a stall or a hostile peer delivers it: all refused, no tick older
	# than the allowance is simulated, one warning for the peer in the log (not one per snapshot),
	# and the refusals are counted for the peer.
	var stream_floor: int = NetworkTime.tick - allowance
	var stream_log_start: int = aged.log.size()
	var accepted: int = 0
	for tick: int in range(NetworkTime.tick - 60, NetworkTime.tick - allowance):
		accepted += 1 if _deliver(aged, tick, 3) else 0
	var refused_count: int = NetworkHistoryServer.get_recent_refused_input_count(5)
	await _wait_until_tick(NetworkTime.tick + 3)
	_check(refused_count == 1 + (60 - allowance), "the refusals of the peer are counted (%d)" % refused_count)
	_check(NetworkHistoryServer.get_recent_refused_input_count(8) == 0, "a peer that was not refused has a count of 0")
	_check(not _deliver(other, NetworkTime.tick - 40, 1), "another peer's old input is refused too")
	OS.remove_logger(counter)
	_check(counter.count == 4, "two peers refused give two warnings, 2 log lines each, not one per snapshot (%d lines: %s)" % [counter.count, str(counter.lines)])
	_check(accepted == 0, "a stream of 60-tick-old input is refused (%d accepted)" % accepted)
	var too_old: int = 0
	for index: int in range(stream_log_start, aged.log.size()):
		too_old += 1 if (aged.log[index]["tick"] as int) < stream_floor else 0
	_check(too_old == 0, "no tick older than the allowance is simulated because of it (%d were)" % too_old)

	# Cost of the scan for expired holes with six remote inputs (the subjects above and two more),
	# each with a current input: the state of a normal session.
	var extra_a: SimProbe = _make_subject("ScanA", 3)
	var extra_b: SimProbe = _make_subject("ScanB", 4)
	NetworkHistoryServer.push_rollback_state(extra_a, NetworkTime.tick - 1)
	NetworkHistoryServer.push_rollback_state(extra_b, NetworkTime.tick - 1)
	for tick: int in range(NetworkTime.tick - 3, NetworkTime.tick + 1):
		_deliver(extra_a, tick, 1)
		_deliver(extra_b, tick, 1)
	await _wait_until_tick(NetworkTime.tick + 2)
	var started: int = Time.get_ticks_usec()
	var earliest: int = -1
	for _call: int in SCAN_CALLS:
		earliest = RollbackSimulationServer._get_earliest_expired_hole()
	var per_call: float = float(Time.get_ticks_usec() - started) / SCAN_CALLS
	var remote_inputs: int = 0
	for input: Node in RollbackSimulationServer._input_graph._links_from:
		remote_inputs += 0 if input.is_multiplayer_authority() else 1
	print("SCAN_COST per_call_us=%.1f calls=%d remote_inputs=%d earliest=%d" % [per_call, SCAN_CALLS, remote_inputs, earliest])
	_check(per_call < SCAN_MAX_MICROSECONDS, "the scan for expired holes takes %.1f us per call (under %.0f)" % [per_call, SCAN_MAX_MICROSECONDS])

	# The count is forgotten after a second, when the peer leaves, and on reset.
	_check(NetworkHistoryServer.get_recent_refused_input_count(5) > 0, "the count is still there within the second")
	await _wait_until_tick(NetworkTime.tick + NetworkTime.tickrate + 2)
	_check(NetworkHistoryServer.get_recent_refused_input_count(5) == 0, "the count is 0 a second later")
	_deliver(aged, NetworkTime.tick - 30, 4)
	_check(NetworkHistoryServer.get_recent_refused_input_count(5) == 1, "a new refusal is counted")
	NetworkSynchronizationServer.erase_peer(5)
	_check(NetworkHistoryServer.get_recent_refused_input_count(5) == 0, "the count is erased when the peer leaves")
	_deliver(other, NetworkTime.tick - 30, 4)
	_check(NetworkHistoryServer.get_recent_refused_input_count(6) == 1, "another refusal is counted")
	NetworkHistoryServer.reset()
	_check(NetworkHistoryServer.get_recent_refused_input_count(6) == 0, "the count is cleared by reset")

	print("%d failures" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)
