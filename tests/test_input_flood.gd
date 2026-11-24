extends Node
## A client can send input, state and sync packets stamped with ticks ahead of
## the host's. The host must refuse the ones beyond the bound and must keep
## simulating. This runs a host in this process and hands packets to netfox's real
## handlers (_handle_input, _handle_full_state, _handle_full_sync, which end in the
## merge functions of NetworkHistoryServer) as a client that owns a probe subject
## would send them, from _process with a priority ahead of NetworkTime's, so the
## call comes before the tick loop as real packets do (they arrive during the
## multiplayer poll, before the loop).
## After each case the host is restarted, so one frozen case cannot hide or fake
## the next. Cases:
##   - the bound itself, on all three merge paths: a snapshot stamped at the
##     bound is merged and one tick past it is not, read directly from the
##     history buffers. The bound is the reference tick (the tick the host's
##     reference clock has reached, which keeps running through a main-thread
##     hitch, but never less than NetworkTime.tick) plus max_ticks_per_frame
##     plus input_delay;
##   - the bound never exceeds the buffers' history size - 1 ticks past
##     NetworkTime.tick (history_limit, or the state synchronizer's own for sync
##     state), even when the reference clock runs far ahead of NetworkTime.tick;
##   - one snapshot 100000 ticks ahead;
##   - a sweep: one input packet per frame for 1.2 s at lead K = 1, the bound,
##     bound + 1, history_limit - 1, history_limit, history_limit + 1; the bot
##     must keep moving at normal speed in every case.
## Run:
##   godot --headless --path . res://tests/test_input_flood.tscn
## Exits 0 when all cases pass, 1 otherwise (also on timeout).

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const Probe: GDScript = preload("res://tests/netfox_probe.gd")
const TIMEOUT_SECONDS: float = 120.0
const FAR_FUTURE_TICKS: int = 100000
const FLOOD_SECONDS: float = 1.2
const SETTLE_SECONDS: float = 1.0
## The bot must cover at least this share of the distance it covers unattacked.
const MIN_SPEED_SHARE: float = 0.8
## How far the reference clock is pushed ahead for the history_limit check.
const CLOCK_JUMP_SECONDS: float = 2.0
const MAX_PROBE_ATTEMPTS: int = 20
## The peer id the probe packets come from; it owns the probe subject.
const SENDER: int = 2
## The state synchronizer's own history size for the check of its bound.
const SMALL_SYNC_HISTORY: int = 16
## Taken from TEST_PORT so that suites can run side by side (tests/run_all.sh sets it).
const DEFAULT_PORT: int = 25100

enum Path { INPUT, STATE, SYNC }

var _main: Main = null
var _bots: Node = null
var _failures: int = 0
var _flood_lead: int = -1
var _flood_latest_lead: int = -1000000
var _direction: StringName = InputActions.MOVE_RIGHT
var _probe: Node = null

func _ready() -> void:
	# Run before NetworkTime's _process (priority 0): packets are handled in the
	# poll that starts the frame, before the tick loop.
	process_priority = -100
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

# One empty snapshot per frame, while a flood is active.
func _process(_delta: float) -> void:
	if _flood_lead >= 0 and NetworkTime.is_initial_sync_done():
		_deliver(Path.INPUT, NetworkTime.tick + _flood_lead)
		_flood_latest_lead = maxi(_flood_latest_lead, NetworkHistoryServer._rb_input_snapshots.get_latest_index() - NetworkTime.tick)

func _start_host() -> Bot:
	_main._on_host()
	while _bots.get_child_count() == 0:
		await get_tree().process_frame
	await get_tree().create_timer(SETTLE_SECONDS).timeout
	return _bots.get_child(0) as Bot

func _stop_host() -> void:
	_flood_lead = -1
	Input.action_release(InputActions.MOVE_LEFT)
	Input.action_release(InputActions.MOVE_RIGHT)
	_main._on_leave()
	await get_tree().create_timer(SETTLE_SECONDS).timeout

# Hold a direction for FLOOD_SECONDS and return how far the bot moved along it.
func _distance_held(bot: Bot, action: StringName, lead: int) -> float:
	var start: float = bot.global_position.x
	_flood_lead = lead
	Input.action_press(action)
	await get_tree().create_timer(FLOOD_SECONDS).timeout
	Input.action_release(action)
	_flood_lead = -1
	return absf(bot.global_position.x - start)

# The tick the host's own clock has reached. NetworkTime.tick can sit one tick
# past it (the loop runs ceil(debt) ticks), or far behind it after a hitch.
func _reference_tick() -> int:
	return maxi(NetworkTime.tick, NetworkTime.seconds_to_ticks(NetworkTimeSynchronizer.get_time()))

# Hand the host a packet stamped tick, from SENDER, for a subject SENDER owns.
func _deliver(path: Path, tick: int) -> void:
	match path:
		Path.INPUT: NetworkSynchronizationServer._handle_input(SENDER, _probe.input_packet(tick, 1))
		Path.STATE: NetworkSynchronizationServer._handle_full_state(SENDER, _probe.full_state_packet(tick, 1))
		Path.SYNC: NetworkSynchronizationServer._handle_full_sync(SENDER, _probe.full_sync_packet(tick, 1))

func _stored(path: Path, tick: int) -> bool:
	match path:
		Path.INPUT: return NetworkHistoryServer._rb_input_snapshots.has_at(tick)
		Path.STATE: return NetworkHistoryServer._rb_state_snapshots.has_at(tick)
		_: return NetworkHistoryServer._sync_state_snapshots.has_at(tick)

# Deliver a packet stamped base() + offset and say whether it was stored.
# The reference tick moves with the clock, so a probe whose reference tick
# changed between reading it and merging is repeated.
func _accepted(path: Path, base: Callable, offset: int) -> bool:
	for attempt: int in MAX_PROBE_ATTEMPTS:
		var before: int = base.call()
		_deliver(path, before + offset)
		if base.call() == before:
			return _stored(path, before + offset)
	_check(false, "probe at offset %d kept crossing a tick boundary" % offset)
	return false

func _check_bound(base: Callable, bound: int, label: String) -> void:
	for path: Path in [Path.INPUT, Path.STATE, Path.SYNC]:
		var name: String = Path.keys()[path]
		_check(not _accepted(path, base, bound + 1), "%s: %s snapshot one tick past the bound (%d) is refused" % [label, name, bound])
		_check(not _accepted(path, base, bound + 2 * NetworkRollback.history_limit), "%s: %s snapshot far past the bound is refused" % [label, name])
	for path: Path in [Path.INPUT, Path.STATE, Path.SYNC]:
		var name: String = Path.keys()[path]
		_check(_accepted(path, base, bound), "%s: %s snapshot at the bound (%d) is accepted" % [label, name, bound])

func _run() -> void:
	InputActions.ensure_registered()
	_main = MAIN_SCENE.instantiate() as Main
	add_child(_main)
	_main._args.port = _port()
	_bots = _main.get_node("Bots")
	_probe = Probe.new()
	add_child(_probe)
	_probe.register()
	_probe.set_multiplayer_authority(SENDER)

	# Baseline: no flood.
	var bot: Bot = await _start_host()
	var baseline: float = await _distance_held(bot, InputActions.MOVE_RIGHT, -1)
	_check(baseline > 0.0, "baseline distance without flooding: %.1f px" % baseline)
	await _stop_host()

	var limit: int = NetworkRollback.history_limit
	var bound: int = NetworkTime.max_ticks_per_frame + NetworkRollback.input_delay
	print("history_limit %d, max_ticks_per_frame %d, input_delay %d" % [limit, NetworkTime.max_ticks_per_frame, NetworkRollback.input_delay])

	# The bound, read directly: relative to the reference tick.
	await _start_host()
	_check_bound(_reference_tick, bound, "bound")
	await _stop_host()

	# The reference clock far ahead of NetworkTime.tick, as after a long hitch.
	# The bound must not pass history_limit - 1 ticks past NetworkTime.tick.
	await _start_host()
	NetworkTimeSynchronizer._clock.adjust(CLOCK_JUMP_SECONDS)
	var lag: int = _reference_tick() - NetworkTime.tick
	_check(lag + bound >= limit, "the reference clock is %d ticks ahead of NetworkTime.tick, so the unclamped bound would reach history_limit" % lag)
	var tick_base: Callable = func() -> int: return NetworkTime.tick
	_check(not _accepted(Path.INPUT, tick_base, limit), "clamp: input snapshot history_limit ticks past NetworkTime.tick is refused")
	_check(_accepted(Path.INPUT, tick_base, limit - 1), "clamp: input snapshot history_limit - 1 ticks past NetworkTime.tick is accepted")
	# The synchronized state has a history size of its own; the cut follows it.
	NetworkHistoryServer._sync_history_size = SMALL_SYNC_HISTORY
	NetworkHistoryServer.reset()
	_check(not _accepted(Path.SYNC, tick_base, SMALL_SYNC_HISTORY), "clamp: sync snapshot %d ticks past NetworkTime.tick (its history size) is refused" % SMALL_SYNC_HISTORY)
	_check(_accepted(Path.SYNC, tick_base, SMALL_SYNC_HISTORY - 1), "clamp: sync snapshot %d ticks past NetworkTime.tick is accepted" % (SMALL_SYNC_HISTORY - 1))
	NetworkHistoryServer._sync_history_size = limit
	NetworkHistoryServer.reset()
	NetworkTimeSynchronizer._clock.adjust(-CLOCK_JUMP_SECONDS)
	await _stop_host()

	# One packet very far ahead, then check the bot keeps moving.
	bot = await _start_host()
	var tick_before: int = NetworkTime.tick
	_deliver(Path.INPUT, NetworkTime.tick + FAR_FUTURE_TICKS)
	var far: float = await _distance_held(bot, InputActions.MOVE_RIGHT, -1)
	_check(NetworkTime.tick > tick_before, "ticks keep running after a +%d packet" % FAR_FUTURE_TICKS)
	_check(far >= baseline * MIN_SPEED_SHARE, "bot keeps moving after a +%d packet (%.1f px)" % [FAR_FUTURE_TICKS, far])
	await _stop_host()

	for lead: int in [1, bound, bound + 1, limit - 1, limit, limit + 1]:
		bot = await _start_host()
		_flood_latest_lead = -1000000
		var moved: float = await _distance_held(bot, InputActions.MOVE_RIGHT, lead)
		_check(moved >= baseline * MIN_SPEED_SHARE, "flood at lead %d: bot moved %.1f px (baseline %.1f)" % [lead, moved, baseline])
		if _flood_latest_lead > 0:
			print("INFO flood at lead %d: the input buffer's newest tick reached %d ahead of NetworkTime.tick, leaving %d of %d ticks of rollback window" % [lead, _flood_latest_lead, limit - 1 - _flood_latest_lead, limit])
		await _stop_host()

	print("%d failures" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)
