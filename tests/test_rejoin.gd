extends Node
## Leave and start again. Used by tests/net_rejoin.sh.
##   -- --mode=client --address=127.0.0.1 --port=N : join, leave, join the same host again
##   -- --mode=host --port=N                       : host, leave, host again
## After each start the local bot must spawn. Exits 0 on success, 1 otherwise
## (also on timeout).

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_SECONDS: float = 40.0
const SPAWN_WAIT_SECONDS: float = 12.0
const PAUSE_SECONDS: float = 1.0

var _main: Main = null
var _bots: Node = null

func _ready() -> void:
	get_tree().create_timer(TIMEOUT_SECONDS).timeout.connect(_fail.bind("timeout"))
	_run()

func _fail(reason: String) -> void:
	print("FAIL ", reason)
	get_tree().quit(1)

func _local_bot_exists() -> bool:
	for child: Node in _bots.get_children():
		var bot: Bot = child as Bot
		if bot != null and bot.peer_id == multiplayer.get_unique_id():
			return true
	return false

func _wait_for_bot(label: String) -> void:
	var waited: float = 0.0
	while not _local_bot_exists():
		await get_tree().process_frame
		waited += get_process_delta_time()
		if waited > SPAWN_WAIT_SECONDS:
			_fail("no bot after " + label)
			return
	print("PASS bot spawned: ", label)

func _run() -> void:
	var mode: String = "client"
	var address: String = "127.0.0.1"
	var port: int = 0
	for arg: String in OS.get_cmdline_user_args():
		var value: String = arg.get_slice("=", 1)
		match arg.get_slice("=", 0):
			"--mode":
				mode = value
			"--address":
				address = value
			"--port":
				port = value.to_int()
	_main = MAIN_SCENE.instantiate() as Main
	# The spawner's node path must match the host's, so Main goes directly under root.
	get_tree().root.add_child.call_deferred(_main)
	await get_tree().process_frame
	_main._args.port = port
	_bots = _main.get_node("Bots")
	for round_number: int in 2:
		if mode == "host":
			_main._on_host()
		else:
			_main._on_join(address)
		await _wait_for_bot("%s round %d" % [mode, round_number + 1])
		await get_tree().create_timer(PAUSE_SECONDS).timeout
		_main._on_leave()
		await get_tree().create_timer(PAUSE_SECONDS).timeout
	print("PASS")
	get_tree().quit(0)
