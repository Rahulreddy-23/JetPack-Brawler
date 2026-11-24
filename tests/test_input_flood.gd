extends Node
## A client can send an input packet stamped with a tick far in the future. It
## must not stop the host from simulating. This runs a host in this process,
## holds a key, injects the packet the way netfox's input handler does, and
## checks the bot still moves afterwards. Run:
##   godot --headless --path . res://tests/test_input_flood.tscn
## Exits 0 when the bot keeps moving, 1 otherwise (also on timeout).

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_SECONDS: float = 30.0
const FAR_FUTURE_TICKS: int = 100000
const MIN_TRAVEL_PX: float = 100.0
const PORT: int = 25100

var _failures: int = 0

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

func _run() -> void:
	InputActions.ensure_registered()
	var main: Main = MAIN_SCENE.instantiate() as Main
	add_child(main)
	main._args.port = PORT
	main._on_host()
	var bots: Node = main.get_node("Bots")
	while bots.get_child_count() == 0:
		await get_tree().process_frame
	var bot: Bot = bots.get_child(0) as Bot
	await get_tree().create_timer(1.0).timeout

	var x0: float = bot.global_position.x
	Input.action_press(InputActions.MOVE_RIGHT)
	await get_tree().create_timer(1.0).timeout
	var x1: float = bot.global_position.x
	_check(x1 - x0 > MIN_TRAVEL_PX, "bot moves right before the packet (%.1f px)" % (x1 - x0))

	var tick_before: int = NetworkTime.tick
	var snapshot: _Snapshot = _Snapshot.new(NetworkTime.tick + FAR_FUTURE_TICKS)
	NetworkHistoryServer._merge_rollback_input(snapshot)

	Input.action_release(InputActions.MOVE_RIGHT)
	Input.action_press(InputActions.MOVE_LEFT)
	await get_tree().create_timer(1.0).timeout
	Input.action_release(InputActions.MOVE_LEFT)
	var x2: float = bot.global_position.x
	_check(NetworkTime.tick > tick_before, "network ticks keep running")
	_check(x1 - x2 > MIN_TRAVEL_PX, "bot still moves after a far-future input packet (%.1f px)" % (x1 - x2))

	print("%d failures" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)
