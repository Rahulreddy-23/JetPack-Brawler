extends Node
## A client can send input packets stamped with ticks ahead of the host's. They
## must not stop the host from simulating. This runs a host in this process and
## injects empty input snapshots the way netfox's input handler merges them
## (NetworkHistoryServer._merge_rollback_input), while a key is held. After each
## case the host is restarted, so one frozen case cannot hide or fake the next.
## Cases:
##   - one snapshot 100000 ticks ahead;
##   - a sweep: one snapshot per tick for 1.2 s at lead K = 1, the accepted
##     bound, bound + 1, history_limit - 1, history_limit, history_limit + 1.
## In every case the bot must keep moving at normal speed. Run:
##   godot --headless --path . res://tests/test_input_flood.tscn
## Exits 0 when all cases pass, 1 otherwise (also on timeout).

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_SECONDS: float = 90.0
const FAR_FUTURE_TICKS: int = 100000
const FLOOD_SECONDS: float = 1.2
const SETTLE_SECONDS: float = 1.0
## The bot must cover at least this share of the distance it covers unattacked.
const MIN_SPEED_SHARE: float = 0.8
const PORT: int = 25100

var _main: Main = null
var _bots: Node = null
var _failures: int = 0
var _flood_lead: int = -1
var _direction: StringName = InputActions.MOVE_RIGHT

func _ready() -> void:
	get_tree().create_timer(TIMEOUT_SECONDS).timeout.connect(_on_timeout)
	NetworkTime.after_tick.connect(_on_after_tick)
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

# One empty snapshot per network tick, while a flood is active.
func _on_after_tick(_delta: float, tick: int) -> void:
	if _flood_lead >= 0:
		NetworkHistoryServer._merge_rollback_input(_Snapshot.new(tick + _flood_lead))

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

func _run() -> void:
	InputActions.ensure_registered()
	_main = MAIN_SCENE.instantiate() as Main
	add_child(_main)
	_main._args.port = PORT
	_bots = _main.get_node("Bots")

	# Baseline: no flood.
	var bot: Bot = await _start_host()
	var baseline: float = await _distance_held(bot, InputActions.MOVE_RIGHT, -1)
	_check(baseline > 0.0, "baseline distance without flooding: %.1f px" % baseline)
	await _stop_host()

	# One packet very far ahead, then check the bot keeps moving.
	bot = await _start_host()
	var tick_before: int = NetworkTime.tick
	NetworkHistoryServer._merge_rollback_input(_Snapshot.new(NetworkTime.tick + FAR_FUTURE_TICKS))
	var far: float = await _distance_held(bot, InputActions.MOVE_RIGHT, -1)
	_check(NetworkTime.tick > tick_before, "ticks keep running after a +%d packet" % FAR_FUTURE_TICKS)
	_check(far >= baseline * MIN_SPEED_SHARE, "bot keeps moving after a +%d packet (%.1f px)" % [FAR_FUTURE_TICKS, far])
	await _stop_host()

	var limit: int = NetworkRollback.history_limit
	var bound: int = NetworkTime.max_ticks_per_frame
	print("history_limit %d, max_ticks_per_frame %d" % [limit, bound])
	for lead: int in [1, bound, bound + 1, limit - 1, limit, limit + 1]:
		bot = await _start_host()
		var moved: float = await _distance_held(bot, InputActions.MOVE_RIGHT, lead)
		_check(moved >= baseline * MIN_SPEED_SHARE, "flood at lead %d: bot moved %.1f px (baseline %.1f)" % [lead, moved, baseline])
		await _stop_host()

	print("%d failures" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)
