class_name BotSpawner
extends MultiplayerSpawner
## Spawns one bot per connected peer, the host included. Only the server
## decides when to spawn and despawn; spawn data is built on the server and
## replayed on clients by Godot's spawner. A bot is removed when its peer
## disconnects. The Session turns away players past the maximum before they get here.
## This node defines no RPCs.

signal bot_spawned(bot: Bot)

@export var bot_scene: PackedScene
@export var layout: ArenaLayout

## Drive the local bot with the scripted test input (set from the command line).
var autopilot: bool = false

var _cfg: TuningConfig = TuningConfig.get_default()
var _bots: Dictionary[int, Bot] = {}

func _ready() -> void:
	spawn_function = _spawn_bot
	NetworkEvents.on_server_start.connect(_on_server_start)
	NetworkEvents.on_peer_leave.connect(_on_peer_leave)
	NetworkEvents.on_server_stop.connect(clear)
	NetworkEvents.on_client_stop.connect(clear)

## All bots currently in the arena, by peer id.
func get_bots() -> Dictionary[int, Bot]:
	return _bots

## Remove every bot (used when leaving a session).
func clear() -> void:
	for bot: Bot in _bots.values():
		bot.queue_free()
	_bots.clear()

func _on_server_start() -> void:
	_server_spawn(1)

## Called by Main for each peer the Session accepted (the limit is checked there).
func on_peer_accepted(id: int) -> void:
	if not multiplayer.is_server():
		return
	# A bot is only useful once the peer's clock is synced to the server.
	while not NetworkTime.is_client_synced(id):
		await NetworkTime.after_client_sync
		if not multiplayer.get_peers().has(id):
			return
	_server_spawn(id)

func _on_peer_leave(id: int) -> void:
	if not multiplayer.is_server():
		return
	if _bots.has(id):
		_bots[id].queue_free()

func _server_spawn(id: int) -> void:
	if _bots.has(id):
		return
	spawn({"peer_id": id, "slot": _free_slot()})

func _free_slot() -> int:
	var used: Array[int] = []
	for bot: Bot in _bots.values():
		used.append(bot.slot)
	for slot: int in _cfg.max_players:
		if not used.has(slot):
			return slot
	return 0

# Runs on every peer with the server's spawn data.
func _spawn_bot(data: Variant) -> Node:
	var info: Dictionary = data as Dictionary
	var peer_id: int = info.get("peer_id", 0) as int
	var slot: int = clampi(info.get("slot", 0) as int, 0, _cfg.max_players - 1)
	var bot: Bot = bot_scene.instantiate() as Bot
	bot.peer_id = peer_id
	bot.slot = slot
	bot.name = "Bot%d" % peer_id
	bot.position = layout.spawns[slot % layout.spawns.size()] * _cfg.bot_height_px
	# The server owns the bot. The player owns only the input node.
	bot.set_multiplayer_authority(1)
	var input: BotInput = bot.get_node("Input") as BotInput
	input.set_multiplayer_authority(peer_id)
	input.autopilot = autopilot and peer_id == multiplayer.get_unique_id()
	input.autopilot_delay_ticks = _cfg.tick_rate
	_bots[peer_id] = bot
	bot.tree_exited.connect(_on_bot_exited.bind(peer_id))
	bot_spawned.emit(bot)
	return bot

func _on_bot_exited(peer_id: int) -> void:
	_bots.erase(peer_id)
