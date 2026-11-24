extends Node
## World-object slots and pickup spots must still send their state after a session as a
## client. Used by tests/net_ownership.sh.
##   -- --mode=relay --address=127.0.0.1 --port=P1 --host-port=P2 :
##        join the host at P1, leave, then host at P2 and write a value into slot Obj0 and
##        spot Spot0 on every tick (the way a rule would), until killed
##   -- --mode=check --address=127.0.0.1 --port=P2 :
##        join the relay's host and wait for those values to arrive
## Exits 0 on success, 1 otherwise (also on timeout).

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_SECONDS: float = 45.0
const WAIT_SECONDS: float = 15.0
const PAUSE_SECONDS: float = 1.0
const SLOT_VALUE: int = 7
const SPOT_VALUE: int = 4242
const BOT_VALUE: int = 9

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

func _wait_for_bot(label: String) -> bool:
	var waited: float = 0.0
	while not _local_bot_exists():
		await get_tree().process_frame
		waited += get_process_delta_time()
		if waited > WAIT_SECONDS:
			_fail("no bot after " + label)
			return false
	print("PASS bot spawned: ", label)
	return true

# The host's own bot, to show that bots (created fresh each session) do not have the problem.
func _host_bot() -> Bot:
	for child: Node in _bots.get_children():
		var bot: Bot = child as Bot
		if bot != null and bot.peer_id == 1:
			return bot
	return null

func _slot() -> WorldObject:
	return _main.get_node("Objects/Obj0") as WorldObject

func _spot() -> PickupSpot:
	return _main.get_node("Pickups/Spot0") as PickupSpot

# Written after the tick is simulated, so it is recorded as part of the state of the next tick.
func _write_values(_tick: int) -> void:
	if multiplayer.is_server():
		_slot().launches = SLOT_VALUE
		_spot().ready_tick = SPOT_VALUE
		var bot: Bot = _host_bot()
		if bot != null:
			bot.vitals.hits_taken = BOT_VALUE

func _run() -> void:
	var mode: String = "check"
	var address: String = "127.0.0.1"
	var port: int = 0
	var host_port: int = 0
	for arg: String in OS.get_cmdline_user_args():
		var value: String = arg.get_slice("=", 1)
		match arg.get_slice("=", 0):
			"--mode":
				mode = value
			"--address":
				address = value
			"--port":
				port = value.to_int()
			"--host-port":
				host_port = value.to_int()
	_main = MAIN_SCENE.instantiate() as Main
	# The spawner's node path must match the host's, so Main goes directly under root.
	get_tree().root.add_child.call_deferred(_main)
	await get_tree().process_frame
	_main._args.port = port
	_bots = _main.get_node("Bots")
	if mode == "relay":
		_main._on_join(address)
		if not await _wait_for_bot("as a client"):
			return
		await get_tree().create_timer(PAUSE_SECONDS).timeout
		_main._on_leave()
		await get_tree().create_timer(PAUSE_SECONDS).timeout
		_main._args.port = host_port
		_main._on_host()
		NetworkRollback.after_process_tick.connect(_write_values)
		if not await _wait_for_bot("as the new host"):
			return
		print("RELAY_HOSTING owned=%s" % _slot().get_multiplayer_authority())
		return
	_main._on_join(address)
	if not await _wait_for_bot("as a guest of the relay"):
		return
	var waited: float = 0.0
	while _host_bot() == null or _slot().launches != SLOT_VALUE or _spot().ready_tick != SPOT_VALUE or _host_bot().vitals.hits_taken != BOT_VALUE:
		await get_tree().process_frame
		waited += get_process_delta_time()
		if waited > WAIT_SECONDS:
			_fail("the slot, spot and bot values never arrived (slot %d, spot %d, bot %d)" % [_slot().launches, _spot().ready_tick, _host_bot().vitals.hits_taken if _host_bot() != null else -1])
			return
	print("PASS slot, spot and host bot state arrived after %.1f s" % waited)
	get_tree().quit(0)
