extends Node
class_name _RollbackSimulationServer

# @public class

## Runs gameplay simulation during rollback
##
## Rollback involves restoring the game state to an earlier point in time and
## re-running game logic from there. This class tracks which nodes participate
## in rollback, which of them need to be actually simulated, and runs the
## simulation itself.
## [br][br]
## Node simulation honors scene tree order. Processing order and physics
## processing order are [b]not[/b] considered.
## [br][br]
## To participate in rollback, call [method register] using the method to call
## to simulate the node. Only one [Callable] can be actively registered per
## node.

var _history_server: _NetworkHistoryServer
var _liveness_server: _RollbackLivenessServer

var _callbacks := {}		# node to callback
var _simulated_ticks := {}	# node to array of ticks
var _prediction_enabled_nodes := _Set.new()

var _input_graph := _Graph.new() # Links inputs to objects controlled by them

# Currently simulated object
var _current_object: Object = null
# Predicted nodes for next simulation
var _predicted_nodes := _Set.new()

var _group := StringName("__nf_rollback_sim" + str(get_instance_id()))

static var _logger := NetfoxLogger._for_netfox("RollbackSimulationServer")

## Register a [param callback] to run as part of the rollback loop
func register(callback: Callable) -> void:
	if not is_instance_valid(callback.get_object()):
		_logger.error("Trying to register callback that belongs to an invalid object!")
		return

	var subject := callback.get_object()
	assert(subject, "Only nodes supported for now!")
	assert(not _callbacks.has(subject), "Double register() of node %s!" % [subject])
	assert((subject as Node).is_inside_tree(), "Node %s is not inside the tree!" % [subject])

	_callbacks[subject] = callback
	(subject as Node).add_to_group(_group)

## Deregister a [param callback] from the rollback loop
func deregister(callback: Callable) -> void:
	if not callback or not callback.is_valid(): return

	var subject := callback.get_object()

	if not is_instance_valid(subject): return
	if _callbacks[subject] != callback: return

	_callbacks.erase(subject)
	_input_graph.erase(subject)
	_simulated_ticks.erase(subject)
	(subject as Node).remove_from_group(_group)

## Forget which ticks were simulated, while keeping the registered callbacks
## [br][br]
## Called by [method _NetworkTime.stop], so ticks of the next session are not
## mistaken for already simulated ones.
func reset() -> void:
	_simulated_ticks.clear()

## Deregister a [param node] from the rollback loop
func deregister_node(node: Node) -> void:
	if _callbacks.has(node):
		deregister(_callbacks[node])
	_input_graph.erase(node)
	_prediction_enabled_nodes.erase(node)

## Register [param input] as providing input for [param node]
func register_rollback_input_for(node: Node, input: Node) -> void:
	_input_graph.link(input, node)

## Deregister [param input] from providing input for [param node]
func deregister_rollback_input(node: Node, input: Node) -> void:
	_input_graph.unlink(input, node)

## Toggle the prediction enabled flag for [param node]
## [br][br]
## Prediction in this sense means that the node will be simulated even if there
## is no up to date input available.
func set_prediction_enabled_for(node: Node, enabled: bool) -> void:
	if enabled:
		_prediction_enabled_nodes.add(node)
	else:
		_prediction_enabled_nodes.erase(node)

## Return true if prediction is enabled for [param node]
## [br][br]
## Prediction in this sense means that the node will be simulated even if there
## is no up to date input available.
func is_prediction_enabled_for(node: Node) -> bool:
	return _prediction_enabled_nodes.has(node)

## Return true if the currently simulated node is being predicted
func is_predicting_current() -> bool:
	if not _current_object or not is_instance_valid(_current_object):
		return false
	return _predicted_nodes.has(_current_object)

## Get the currently simulated object
func get_simulated_object() -> Object:
	return _current_object

## Simulate a tick
func simulate(delta: float, tick: int) -> void:
	_current_object = null

	var input_snapshot := NetworkHistoryServer._get_rollback_input_snapshot(tick)
	var state_snapshot := NetworkHistoryServer._get_rollback_state_snapshot(tick)
	var nodes := _get_nodes_to_simulate(input_snapshot) # Result is sorted by tree order
	_predicted_nodes.clear()

	# Determine predicted nodes
	for node in _callbacks.keys():
		if _is_predicting(input_snapshot, node, tick):
			_predicted_nodes.add(node)

	# Run callbacks and clear group
	for node in nodes:
		_current_object = node

		var callback := _callbacks[node] as Callable
		var is_fresh := _is_tick_fresh_for(node, tick)
		callback.call(delta, tick, is_fresh)

		_current_object = null
		_set_tick_simulated_for(node, tick)

	# Metrics
	NetworkPerformance.push_rollback_nodes_simulated(nodes.size())

# Returns nodes in scene tree order
func _get_nodes_to_simulate(input_snapshot: _Snapshot) -> Array[Node]:
	var result: Array[Node] = []
	if not input_snapshot:
		return []

	var tick := input_snapshot.tick
	for node in get_tree().get_nodes_in_group(_group):
		if not _liveness_server.is_alive(node, tick):
			# Node is not alive in this tick
			continue

		var inputs := [] as Array[Node]
		inputs.assign(_input_graph.get_linked_to(node))

		if inputs.is_empty():
			# Node has no input, simulate it
			result.append(node)
			continue

		if NetworkRollback.is_mutated(node, tick):
			# Node is mutated, must simulate
			result.append(node)
			continue

		if not input_snapshot.has_subjects(inputs, true) and \
			not is_prediction_enabled_for(node):
			# We don't have input for node, and input prediction is disabled
			# Don't simulate
			continue

		# PATCH (see addons/NETFOX_PATCHES.md): an owned node does not build on
		# a state that is only a carry-over, see _starts_from_carry_over()
		if input_snapshot.has_subjects(inputs, true) and _starts_from_carry_over(node, tick):
			continue

		result.append(node)

	return result

# PATCH (see addons/NETFOX_PATCHES.md): `tick` is the tick of the input snapshot, for when there
# is no input snapshot at all for that tick
func _is_predicting(input_snapshot: _Snapshot, node: Node, tick: int = -1) -> bool:
	if input_snapshot:
		tick = input_snapshot.tick
	var input_nodes := [] as Array[Node]
	input_nodes.assign(_input_graph.get_linked_to(node))

	var is_owned := node.is_multiplayer_authority()
	var is_inputless := input_nodes.is_empty()
	var has_input := false

	if not is_inputless and input_snapshot:
		has_input = input_snapshot.has_subjects(input_nodes, true)

	if not is_owned and has_input:
		# We don't own the node, but we own input for it - not (input) predicting
		return false
	if not is_owned:
		# We don't own the node, so we can only guess - i.e. predict
		return true
	if is_owned and is_inputless:
		# We own the node, node doesn't depend on input, we're sure
		return false
	if is_owned and not has_input:
		# We own the node, node depends on input, we don't have data for input - predict
		# PATCH (see addons/NETFOX_PATCHES.md): unless this is no hole, or the hole has
		# expired; the node was not simulated, and its state carried over is then the state
		# of record
		if tick >= 0 and not is_prediction_enabled_for(node) and _is_hole_accepted(node, input_nodes, tick):
			return false
		return true
	# We own the node and we have data for node's input - we're sure
	# PATCH (see addons/NETFOX_PATCHES.md): but not if it starts from a carry-over
	if tick >= 0 and _starts_from_carry_over(node, tick):
		return true
	return false

# PATCH (see addons/NETFOX_PATCHES.md): true if `node`, which this peer owns, has a state
# at `tick` that is only a carry-over: it was skipped on an earlier tick because its input
# for that tick had not arrived, so its state at `tick` is the state before it, recorded as
# not authoritative. Simulating from it, with the input of `tick`, would build a state
# that is one or more steps behind and record it as authoritative.
func _starts_from_carry_over(node: Node, tick: int) -> bool:
	if not node.is_multiplayer_authority():
		return false
	var state_snapshot := NetworkHistoryServer._get_rollback_state_snapshot(tick)
	return state_snapshot != null and state_snapshot.has_subject(node) and not state_snapshot.is_auth(node)

# PATCH (see addons/NETFOX_PATCHES.md): the latest an honest input may arrive, as a multiple of
# input_redundancy ticks counted on the host's own clock from the tick the input belongs to.
# Later than that is the same as lost: the host stops waiting, the tick stands as one where
# the subject did not act, and input for it that arrives afterwards is refused. It also
# covers honest input that is merely late and in order (a stall delivers a run of packets at
# once; what is older than the allowance in it is refused). 3 times 4 ticks is 12 ticks, 400 ms
# at 30 ticks per second. A first guess, to be judged after the phone test.
const _INPUT_ALLOWANCE_FACTOR := 3

# PATCH (see addons/NETFOX_PATCHES.md): the input allowance in ticks (see above). After it
# the tick is final: its hole is accepted (see _is_hole_accepted) and the host refuses input
# stamped with it (see NetworkHistoryServer._merge_rollback_input).
func _get_hole_allowance() -> int:
	return _INPUT_ALLOWANCE_FACTOR * NetworkRollback.input_redundancy

# PATCH (see addons/NETFOX_PATCHES.md): true if `node`, which this peer owns, was not
# simulated on `tick` for lack of input and that is final, so that the state carried over
# from `tick` is the state of record (the node did not act on that tick; no input is made up):
#   - there is no input before `tick` and one after it: the subject started to send later,
#     which is no hole; or
#   - there is an input after `tick` and the host's own tick is more than
#     _INPUT_ALLOWANCE_FACTOR times input_redundancy ticks past it: the hole expired.
# It depends only on the input history and NetworkTime.tick, which does not change within a
# rollback loop, so every pass over the tick gives the same answer.
func _is_hole_accepted(node: Node, inputs: Array, tick: int) -> bool:
	if not node.is_multiplayer_authority():
		return false
	if NetworkHistoryServer.get_latest_input_for(inputs, NetworkTime.tick + NetworkRollback.history_limit) <= tick:
		return false
	if NetworkHistoryServer.get_latest_input_for(inputs, tick) < 0:
		return true
	return NetworkTime.tick - tick > _get_hole_allowance()

# PATCH (see addons/NETFOX_PATCHES.md): true if `snapshot` holds input for a tick that the host
# has already decided had no input and no hole: nothing is held for the tick or before it, and
# the state after the tick is a carry-over recorded as authoritative (see _is_hole_accepted, the
# first case: a tick before a subject's first input). The host may have sent that state, so the
# input is refused and the decision is final, like an expiry. It reads only the histories.
func _is_start_decided(snapshot: _Snapshot) -> bool:
	for input in snapshot.get_subjects():
		for node in _input_graph.get_linked_from(input):
			if not node.is_multiplayer_authority():
				continue
			if NetworkHistoryServer.get_latest_input_for(_input_graph.get_linked_to(node), snapshot.tick) >= 0:
				continue
			var state_snapshot := NetworkHistoryServer._get_rollback_state_snapshot(snapshot.tick + 1)
			if state_snapshot != null and state_snapshot.has_subject(node) and state_snapshot.is_auth(node):
				return true
	return false

# PATCH (see addons/NETFOX_PATCHES.md): the earliest tick whose input is missing, whose hole
# is accepted (see above) and whose carried-over state is not yet the state of record, or -1.
# Nothing arrives when a hole expires, and the first input of a subject arrives after the
# ticks before it were passed, so NetworkRollback asks for this at the start of each loop
# and re-simulates from there. Looked at once per input node of another peer, and only at the
# ticks after the last authoritative state of the first node that input drives (the others
# have the same chain), which is where such a hole can be.
func _get_earliest_expired_hole() -> int:
	var now := NetworkTime.tick
	var oldest := maxi(NetworkRollback.history_start, 0)
	for input: Node in _input_graph._links_from:
		if input.is_multiplayer_authority():
			continue
		var nodes := _input_graph.get_linked_from(input)
		var node := nodes[0] as Node
		if not node.is_multiplayer_authority():
			continue

		# The states of the ticks of this loop are not recorded yet: start at the newest that is.
		var first := now
		while first > oldest:
			var state_snapshot := NetworkHistoryServer._get_rollback_state_snapshot(first)
			if state_snapshot != null and (not state_snapshot.has_subject(node) or state_snapshot.is_auth(node)):
				break
			first -= 1

		var inputs := _input_graph.get_linked_to(node)
		for tick in range(first, now):
			var input_snapshot := NetworkHistoryServer._get_rollback_input_snapshot(tick)
			if (input_snapshot == null or not input_snapshot.has_subject(input, true)) and _is_hole_accepted(node, inputs, tick) and _liveness_server.is_alive(node, tick):
				return tick
	return -1

func _is_tick_fresh_for(node: Node, tick: int) -> bool:
	if not _simulated_ticks.has(node):
		return true
	var ticks := _simulated_ticks.get(node) as Array[int]
	return not ticks.has(tick)

func _set_tick_simulated_for(node: Node, tick: int) -> void:
	if not _simulated_ticks.has(node):
		_simulated_ticks[node] = [tick] as Array[int]
	else:
		_simulated_ticks[node].append(tick)

func _trim_ticks_simulated(beginning: int) -> void:
	for object in _simulated_ticks:
		_simulated_ticks[object] = _simulated_ticks[object]\
			.filter(func(tick): return tick >= beginning)

func _get_controlled_by(input: Node) -> Array[Node]:
	var result := [] as Array[Node]
	result.assign(_input_graph.get_linked_from(input))
	return result

func _get_inputs_of(node: Node) -> Array[Node]:
	var result := [] as Array[Node]
	result.assign(_input_graph.get_linked_to(node))
	return result

func _init(p_history_server: _NetworkHistoryServer = null, p_liveness_server: _RollbackLivenessServer = null) -> void:
	_history_server = p_history_server
	_liveness_server = p_liveness_server

func _ready() -> void:
	# Ensure dependencies
	if not _history_server: _history_server = NetworkHistoryServer
	if not _liveness_server: _liveness_server = RollbackLivenessServer
