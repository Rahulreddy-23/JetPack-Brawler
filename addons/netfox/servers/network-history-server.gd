extends Node
class_name _NetworkHistoryServer

# @public class

## Tracks the history of objects' properties
##
## Specifically, history is stored for rollback state properties, rollback input
## properties, and synchronized state properties.
## [br][br]
## Keeping history lets rollback restore earlier game states for resimulation,
## and enables [_NetworkSynchronizationServer] to send diff states by comparing
## against historical data.

var _rb_input_properties := _PropertyPool.new()
var _rb_state_properties := _PropertyPool.new()
var _sync_state_properties := _PropertyPool.new()

var _rb_history_size := NetworkRollback.history_limit
var _sync_history_size := ProjectSettings.get_setting("netfox/state_synchronizer/history_limit", 64) as int

var _ignored_subjects := _Set.new()

# PATCH (see addons/NETFOX_PATCHES.md): subjects that state from their authority
# has been merged for in this session
var _authoritative_subjects := _Set.new()

# Source of truth for history
var _rb_input_history := _PerObjectHistory.new(_rb_history_size)
var _rb_state_history := _PerObjectHistory.new(_rb_history_size)
var _sync_history := _PerObjectHistory.new(_sync_history_size)

# Cached snapshots for syncing
var _rb_input_snapshots := _HistoryBuffer.new(_rb_history_size)
var _rb_state_snapshots := _HistoryBuffer.new(_rb_history_size)
var _sync_state_snapshots := _HistoryBuffer.new(_sync_history_size)

static var _logger := NetfoxLogger._for_netfox("NetworkHistoryServer")

## Register a rollback state property
func register_rollback_state(node: Node, property: NodePath) -> void:
	_rb_state_properties.add(node, property)

## Deregister a rollback state property
func deregister_rollback_state(node: Node, property: NodePath) -> void:
	_rb_state_properties.erase(node, property)

## Register a rollback input property
func register_rollback_input(node: Node, property: NodePath) -> void:
	_rb_input_properties.add(node, property)

## Deregister a rollback input property
func deregister_rollback_input(node: Node, property: NodePath) -> void:
	_rb_input_properties.erase(node, property)

## Register a synchronized state property
func register_sync_state(node: Node, property: NodePath) -> void:
	_sync_state_properties.add(node, property)

## Deregister a synchronized state property
func deregister_sync_state(node: Node, property: NodePath) -> void:
	_sync_state_properties.erase(node, property)

## Deregister a node, no longer tracking any property it had registered using
## any of the [code]register_*()[/code] methods
func deregister(node: Node) -> void:
	# Deregister properties
	_rb_state_properties.erase_subject(node)
	_rb_input_properties.erase_subject(node)
	_sync_state_properties.erase_subject(node)

	_authoritative_subjects.erase(node)

	# Erase from per-object history
	_rb_state_history.erase_subject(node)
	_rb_input_history.erase_subject(node)
	_sync_history.erase_subject(node)

	# Erase from per-tick history
	for history in [_rb_state_snapshots, _rb_input_snapshots, _sync_state_snapshots]:
		for value in history.values():
			var snapshot := value as _Snapshot
			snapshot.erase_subject(node)

## Forget all recorded history, while keeping the registered properties
## [br][br]
## History is indexed by tick, so data from a previous session must not carry
## over to the next one. Called by [method _NetworkTime.stop].
func reset() -> void:
	_rb_input_history = _PerObjectHistory.new(_rb_history_size)
	_rb_state_history = _PerObjectHistory.new(_rb_history_size)
	_sync_history = _PerObjectHistory.new(_sync_history_size)

	_rb_input_snapshots = _HistoryBuffer.new(_rb_history_size)
	_rb_state_snapshots = _HistoryBuffer.new(_rb_history_size)
	_sync_state_snapshots = _HistoryBuffer.new(_sync_history_size)

	_ignored_subjects.clear()
	_authoritative_subjects.clear()

## Do not record [param subject]
## [br][br]
## Can be used in [code]_rollback_tick()[/code] in case node prediction is
## enabled, but state can't be reasonably predicted.
## [br][br]
## Subjects stay ignored until [method flush_ignores] is called. This is done
## by default after every rollback tick.
func ignore(subject: Node) -> void:
	_ignored_subjects.add(subject)

## Clear the list of ignored subjects
## [br][br]
## Calling this method undoes all previous [method ignore] calls.
func flush_ignores() -> void:
	_ignored_subjects.clear()

## Return the latest tick where any of the [param subjects] had rollback
## state data available
func get_latest_state_tick_for(subjects: Array, tick: int) -> int:
	return _get_latest_for(subjects, tick, _rb_state_history)

## Return how old is the latest rollback state data for any of the
## [param subjects], in ticks
func get_state_age_for(subjects: Array, tick: int) -> int:
	var latest_state := get_latest_state_tick_for(subjects, tick)
	if latest_state < 0:
		return -1
	else:
		return tick - latest_state

## Return the latest tick where any of the [param subjects] had rollback
## input data available
func get_latest_input_for(subjects: Array, tick: int) -> int:
	return _get_latest_for(subjects, tick, _rb_input_history)

## Return how old is the latest rollback input data for any of the
## [param subjects], in ticks
func get_input_age_for(subjects: Array, tick: int) -> int:
	var latest_input := get_latest_input_for(subjects, tick)
	if latest_input < 0:
		return -1
	else:
		return tick - latest_input

## Return true if [param subject] has state that came from its authority
## [br][br]
## On a peer that is not the authority, rollback and synchronized state of a
## subject is predicted locally until the authority's state arrives. This is
## true once any state received from the authority has been merged for
## [param subject] in this session, and always true on the authority itself. It
## is false again after [method _NetworkTime.stop], which calls [method reset].
## [br][br]
## [param subject] is a [Variant] so that a freed node can be passed and gives
## [code]false[/code]: GDScript refuses a freed object for an [Object] parameter
## before the function runs.
func has_authoritative_state(subject: Variant) -> bool:
	if not is_instance_valid(subject):
		return false
	if subject is Node and (subject as Node).is_multiplayer_authority():
		return true
	return _authoritative_subjects.has(subject)

## Record currently registered rollback state properties for [param subject] at
## [param tick].
func push_rollback_state(subject: Node, tick: int) -> void:
	var subject_snapshot := _rb_state_history.ensure_snapshot(tick, subject, false)
	if subject_snapshot == null:
		_logger.warning("Dropping seeded state @%d for subject %s as out-of-bounds", [tick, subject])
		return

	var snapshot := _rb_state_snapshots.get_at(tick, _Snapshot.new(tick)) as _Snapshot
	if not _rb_state_snapshots.has_at(tick):
		_rb_state_snapshots.set_at(tick, snapshot)

	var is_auth := subject.is_multiplayer_authority()
	subject_snapshot.record_properties(
		_rb_state_properties.get_properties_of_raw(subject),
		snapshot,
		is_auth
	)

func _record_rollback_input(tick: int) -> void:
	_record(tick, _rb_input_history, _rb_input_snapshots, _rb_input_properties, true, func(subject: Node):
		return subject.is_multiplayer_authority()
	)

func _record_rollback_state(tick: int) -> void:
	var input_snapshot := _get_rollback_input_snapshot(tick - 1)

	_record(tick, _rb_state_history, _rb_state_snapshots, _rb_state_properties, false, func(subject: Node):
		if not subject.is_multiplayer_authority():
			return false
		if RollbackSimulationServer._is_predicting(input_snapshot, subject):
			return false
		return true
	)

func _record_sync_state(tick: int) -> void:
	_record(tick, _sync_history, _sync_state_snapshots, _sync_state_properties, true, func(subject: Node):
		return subject.is_multiplayer_authority()
	)

func _restore_rollback_input(tick: int) -> bool:
	return _restore_latest(tick, _rb_input_history)

func _restore_rollback_state(tick: int) -> bool:
	return _restore_latest(tick, _rb_state_history)

func _restore_synchronizer_state(tick: int) -> bool:
	return _restore_latest(tick, _sync_history)

func _get_rollback_input_snapshot(tick: int) -> _Snapshot:
	return _rb_input_snapshots.get_at(tick)

func _get_rollback_state_snapshot(tick: int) -> _Snapshot:
	return _rb_state_snapshots.get_at(tick)

func _get_synchronizer_state_snapshot(tick: int) -> _Snapshot:
	return _sync_state_snapshots.get_at(tick)

func _merge_rollback_input(snapshot: _Snapshot) -> bool:
	if not _can_merge_tick(snapshot.tick, _rb_input_history):
		return false
	_merge_snapshot(snapshot, _rb_input_snapshots, true)
	return _merge_history(snapshot, _rb_input_history, true)

func _merge_rollback_state(snapshot: _Snapshot, is_diff: bool = false) -> bool:
	if not _can_merge_tick(snapshot.tick, _rb_state_history):
		return false
	_mark_authoritative(snapshot)
	if is_diff:
		_complete_diff(snapshot, _rb_state_history)
	_merge_snapshot(snapshot, _rb_state_snapshots)
	return _merge_history(snapshot, _rb_state_history)

func _merge_synchronizer_state(snapshot: _Snapshot, is_diff: bool = false) -> bool:
	if not _can_merge_tick(snapshot.tick, _sync_history):
		return false
	_mark_authoritative(snapshot)
	if is_diff:
		_complete_diff(snapshot, _sync_history)
	_merge_snapshot(snapshot, _sync_state_snapshots, true)
	return _merge_history(snapshot, _sync_history)

# PATCH (see addons/NETFOX_PATCHES.md): remember which subjects state came in for
func _mark_authoritative(snapshot: _Snapshot) -> void:
	for subject in snapshot.get_auth_subjects():
		_authoritative_subjects.add(subject)

# PATCH (see addons/NETFOX_PATCHES.md): a diff holds only what changed since the
# last state the sender sent. Make it whole by adding the properties of the
# latest authoritative snapshot before its tick, so merging it never lets this
# peer's own prediction for the tick fill in the properties it left out. A
# subject that already has an authoritative snapshot at the tick (an earlier
# diff or a full state) is layered on as before.
func _complete_diff(snapshot: _Snapshot, history: _PerObjectHistory) -> void:
	for subject in snapshot.get_subjects():
		if not snapshot.is_auth(subject) or history.is_auth(snapshot.tick, subject):
			continue

		var base := history.get_latest_auth_snapshot_before(snapshot.tick, subject)
		if base == null:
			continue

		for property in base._data:
			if not snapshot.has_property(subject, property):
				snapshot.set_property(subject, property, base._data[property])

func _record(tick: int, history: _PerObjectHistory, snapshots: _HistoryBuffer, property_pool: _PropertyPool, only_auth: bool, auth_filter: Callable) -> void:
	var snapshot := snapshots.get_at(tick, _Snapshot.new(tick)) as _Snapshot
	if not snapshots.has_at(tick):
		snapshots.set_at(tick, snapshot)

	history.record_subjects(
		tick,
		property_pool.get_subjects_raw(),
		property_pool,
		snapshot,
		only_auth,
		auth_filter,
		history == _rb_state_history,
		_ignored_subjects
	)
	if history == _rb_input_history:
		_logger.trace("Recorded input @%d: %s", [tick, snapshot])
	elif history == _rb_state_history:
		_logger.trace("Recorded state @%d: %s", [tick, snapshot])

func _restore_latest(tick: int, history: _PerObjectHistory) -> bool:
	var any_applied := history.restore_latest(tick)

	if any_applied and _logger._check_log_level(NetfoxLogger.LOG_TRACE):
		if history == _rb_input_history:
			_logger.trace("Restored input @%d", [tick])
		elif history == _rb_state_history:
			_logger.trace("Restored state @%d", [tick])

	return any_applied

func _merge_snapshot(snapshot: _Snapshot, snapshots: _HistoryBuffer, reverse: bool = false) -> bool:
	var tick := snapshot.tick

	if not snapshots.has_at(snapshot.tick):
		snapshots.set_at(tick, snapshot)
		return true

	var original_snapshot := snapshots.get_at(tick) as _Snapshot
	if reverse:
		var original_subjects := original_snapshot.get_auth_subjects()
		var incoming_subjects := snapshot.get_auth_subjects()

		# Merge the original snapshot on top of the incoming
		# This prevents players from changing history, e.g. rewrite their past
		# inputs
		snapshots.set_at(tick, snapshot)
		snapshot.merge(original_snapshot)

		# Only return true if we've received inputs for a new node
		return incoming_subjects.any(func(it): return not original_subjects.has(it))
	else:
		return original_snapshot.merge(snapshot)

func _merge_history(snapshot: _Snapshot, history: _PerObjectHistory, reverse: bool = false) -> bool:
	var tick := snapshot.tick
	var has_updated := false

	for subject in snapshot.get_subjects():
		var object_snapshot := history.ensure_snapshot(tick, subject, not reverse)
		if object_snapshot == null:
			_logger.warning("Snapshot being merged is out of bounds! (@%d)", [tick])
			continue

		# Never overwrite auth data
		if object_snapshot.is_auth() and not snapshot.is_auth(subject):
			continue

		for property in snapshot.get_subject_properties(subject):
			# If merging in reverse, don't update anything that we already have
			# a value for - only accept previously unknown property values
			if reverse and object_snapshot.has_value(property):
				continue

			var original_value := object_snapshot.get_value(property)
			var new_value := snapshot.get_property(subject, property)

			object_snapshot.set_value(property, new_value)
			if not has_updated and original_value != new_value:
				has_updated = true
		object_snapshot.set_auth(snapshot.is_auth(subject))

	return has_updated

func _can_merge_tick(tick: int, history: _PerObjectHistory) -> bool:
	# PATCH (see addons/NETFOX_PATCHES.md): a server refuses ticks that are too
	# far ahead of its own clock. The history buffers hold only history_limit
	# ticks, so a snapshot stamped further ahead pushes the buffer's old edge
	# past the current tick and discards what this peer just recorded. Commands
	# arrive before NetworkTime runs its loop, and after a short main-thread
	# hitch NetworkTime.tick lags the clock; honest inputs are stamped with the
	# real time. So the bound is measured from the clock (never from less than
	# NetworkTime.tick) and never reaches the history size of the buffers it
	# guards (history_limit, or the state synchronizer's own) ticks past
	# NetworkTime.tick. Clients only take the server's snapshots, which they
	# trust (see the synchronization server).
	if multiplayer.is_server():
		var reference_tick := maxi(NetworkTime.tick, NetworkTime.seconds_to_ticks(NetworkTimeSynchronizer.get_time()))
		var latest_tick := reference_tick + NetworkTime.max_ticks_per_frame + NetworkRollback.input_delay
		var history_size := _sync_history_size if history == _sync_history else _rb_history_size
		latest_tick = mini(latest_tick, NetworkTime.tick + history_size - 1)
		if tick > latest_tick:
			_logger.trace("Dropping snapshot @%d from too far in the future", [tick])
			return false

	if tick >= NetworkRollback.history_start:
		return true

	# Packets queued while the main thread was stalled are expected to arrive
	# after NetworkTime has skipped past them. They cannot be merged into the
	# new contiguous history and are not an exceptional condition.
	if tick < NetworkRollback._history_floor:
		_logger.trace("Dropping snapshot @%d from before the current history floor", [tick])
		return false

	match history:
		_rb_input_history: _logger.warning("Input being merged is too old! (@%d)", [tick])
		_rb_state_history: _logger.warning("State being merged is too old! (@%d)", [tick])
		_sync_history: _logger.warning("Sync state being merged is too old! (@%d)", [tick])
		_: _logger.warning("Snapshot being merged is too old! (@%d)", [tick])
	return false

func _get_latest_for(subjects: Array, tick: int, history: _PerObjectHistory) -> int:
	var latest := -1

	for subject in subjects:
		var subject_latest := history.get_latest_tick(tick, subject)
		if subject_latest < 0:
			continue

		# Should we track `mini()` instead?
		latest = maxi(latest, subject_latest)

	return latest

func _get_earliest_for(subjects: Array, tick: int, history: _PerObjectHistory) -> int:
	var earliest := -1

	for subject in subjects:
		var subject_latest := history.get_latest_tick(tick, subject)
		if subject_latest < 0:
			return -1

		if earliest < 0:
			earliest = earliest
		else:
			earliest = mini(earliest, subject_latest)

	return earliest
