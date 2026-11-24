extends Node
## When a frame covers more than one network tick, every tick must still be
## simulated. This runs a host in this process, holds a direction, and makes
## every frame slow (a delay in _process, after NetworkTime's loop), so each loop
## runs about three ticks. It checks that the bot was simulated on every tick of
## the window, and that it covered about the distance it covers with normal
## frames. Run:
##   godot --headless --path . res://tests/test_slow_frames.tscn
## Exits 0 when all checks pass, 1 otherwise (also on timeout).

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_SECONDS: float = 90.0
const DEFAULT_PORT: int = 25115
const SETTLE_SECONDS: float = 1.0
const RUN_SECONDS: float = 2.0
## Length of a slow frame; about three ticks at 30 ticks per second.
const SLOW_FRAME_MSEC: int = 100
## The bot must cover at least this share of the distance it covers with normal frames.
const MIN_DISTANCE_SHARE: float = 0.9

var _main: Main = null
var _bots: Node = null
var _failures: int = 0
var _slow: bool = false
var _simulated: Dictionary = {}
var _bot: Bot = null

func _ready() -> void:
	get_tree().create_timer(TIMEOUT_SECONDS).timeout.connect(_on_timeout)
	NetworkRollback.after_process_tick.connect(_on_after_process_tick)
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

func _on_after_process_tick(tick: int) -> void:
	if _bot != null and _bot.last_sim_tick == tick:
		_simulated[tick] = true

func _process(_delta: float) -> void:
	if _slow:
		OS.delay_msec(SLOW_FRAME_MSEC)

func _start_host() -> void:
	_main._on_host()
	while _bots.get_child_count() == 0:
		await get_tree().process_frame
	_bot = _bots.get_child(0) as Bot
	await get_tree().create_timer(SETTLE_SECONDS).timeout

func _stop_host() -> void:
	_slow = false
	Input.action_release(InputActions.MOVE_RIGHT)
	_main._on_leave()
	_bot = null
	await get_tree().create_timer(SETTLE_SECONDS).timeout

# Hold right for RUN_SECONDS. Returns the distance moved and the ticks of the
# window that were never simulated.
func _hold(slow: bool) -> Dictionary:
	var start_x: float = _bot.global_position.x
	var start_tick: int = NetworkTime.tick
	_simulated.clear()
	_slow = slow
	Input.action_press(InputActions.MOVE_RIGHT)
	await get_tree().create_timer(RUN_SECONDS).timeout
	_slow = false
	Input.action_release(InputActions.MOVE_RIGHT)
	var end_tick: int = NetworkTime.tick
	var missed: int = 0
	for tick: int in range(start_tick, end_tick):
		if not _simulated.has(tick):
			missed += 1
	return {"distance": absf(_bot.global_position.x - start_x), "missed": missed, "ticks": end_tick - start_tick}

func _run() -> void:
	InputActions.ensure_registered()
	_main = MAIN_SCENE.instantiate() as Main
	add_child(_main)
	_main._args.port = _port()
	_bots = _main.get_node("Bots")

	await _start_host()
	var normal: Dictionary = await _hold(false)
	await _stop_host()
	_check(normal["missed"] == 0, "normal frames: %d of %d ticks never simulated" % [normal["missed"], normal["ticks"]])
	_check((normal["distance"] as float) > 0.0, "normal frames: bot moved %.1f px" % normal["distance"])

	await _start_host()
	var slow: Dictionary = await _hold(true)
	await _stop_host()
	_check(slow["missed"] == 0, "%d ms frames: %d of %d ticks never simulated" % [SLOW_FRAME_MSEC, slow["missed"], slow["ticks"]])
	_check((slow["distance"] as float) >= (normal["distance"] as float) * MIN_DISTANCE_SHARE, "%d ms frames: bot moved %.1f px (normal frames %.1f px)" % [SLOW_FRAME_MSEC, slow["distance"], normal["distance"]])

	print("%d failures" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)
