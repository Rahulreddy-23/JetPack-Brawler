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
var _pending_peers: Dictionary[int, bool] = {}

func _ready() -> void:
	spawn_function = _spawn_bot
	NetworkEvents.on_server_start.connect(_on_server_start)
	NetworkEvents.on_peer_leave.connect(_on_peer_leave)
	NetworkEvents.on_server_stop.connect(clear)
	NetworkEvents.on_client_stop.connect(clear)
	NetworkTime.after_client_sync.connect(_on_client_synced)

## All bots currently in the arena, by peer id.
func get_bots() -> Dictionary[int, Bot]:
	return _bots

## Remove every bot (used when leaving a session).
func clear() -> void:
	_pending_peers.clear()
	var to_remove: Array[Bot] = []
	for bot: Bot in _bots.values():
		to_remove.append(bot)
	_bots.clear()
	for bot: Bot in to_remove:
		if is_instance_valid(bot):
			if bot.get_parent() != null:
				bot.get_parent().remove_child(bot)
			bot.queue_free()

func _on_server_start() -> void:
	_server_spawn(1)

## Called by Main for each peer the Session accepted (the limit is checked there).
func on_peer_accepted(id: int) -> void:
	if not NetworkEvents.is_server():
		return
	if NetworkTime.is_client_synced(id):
		_server_spawn(id)
	else:
		_pending_peers[id] = true

func _on_client_synced(id: int) -> void:
	if not _pending_peers.has(id):
		return
	_pending_peers.erase(id)
	if not NetworkEvents.is_server():
		return
	if not multiplayer.get_peers().has(id):
		return
	_server_spawn(id)

func _on_peer_leave(id: int) -> void:
	_pending_peers.erase(id)
	if not multiplayer.is_server():
		return
	if _bots.has(id):
		var bot: Bot = _bots[id]
		_bots.erase(id)
		if is_instance_valid(bot):
			if bot.get_parent() != null:
				bot.get_parent().remove_child(bot)
			bot.queue_free()

func _server_spawn(id: int) -> void:
	if _bots.has(id) and is_instance_valid(_bots[id]):
		return
	spawn({"peer_id": id, "slot": _free_slot()})

func _free_slot() -> int:
	var used: Array[int] = []
	for bot: Bot in _bots.values():
		if is_instance_valid(bot):
			used.append(bot.slot)
	for slot: int in _cfg.max_players:
		if not used.has(slot):
			return slot
	return 0

# Runs on every peer with the server's spawn data.
func _spawn_bot(data: Variant) -> Node:
	var info: Dictionary = data as Dictionary if typeof(data) == TYPE_DICTIONARY else {}
	var peer_id: int = info.get("peer_id", 0) as int
	var max_slot: int = maxi(_cfg.max_players - 1, 0)
	var slot: int = clampi(info.get("slot", 0) as int, 0, max_slot)
	var bot: Bot = bot_scene.instantiate() as Bot
	bot.peer_id = peer_id
	bot.slot = slot
	bot.name = "Bot%d" % peer_id
	if layout != null and not layout.spawns.is_empty():
		bot.position = layout.spawns[slot % layout.spawns.size()] * _cfg.bot_height_px
	# The server owns the bot. The player owns only the input node.
	bot.set_multiplayer_authority(1)
	var input: BotInput = bot.get_node("Input") as BotInput
	input.set_multiplayer_authority(peer_id)
	input.autopilot = autopilot and peer_id == multiplayer.get_unique_id()
	input.autopilot_delay_ticks = _cfg.tick_rate
	_bots[peer_id] = bot
	bot.tree_exited.connect(_on_bot_exited.bind(peer_id, bot))
	bot_spawned.emit(bot)
	return bot

func _on_bot_exited(peer_id: int, bot: Bot) -> void:
	if _bots.get(peer_id) == bot:
		_bots.erase(peer_id)
