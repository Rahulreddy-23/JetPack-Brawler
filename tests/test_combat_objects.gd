extends Node
## One process of the end-to-end blast test (tests/net_combat_objects.sh): the real main scene
## with the real combat rules. The host pins the client's bot next to the dummy (test scaffolding
## written in after_process_tick, like a rule would), the client throws its Cooker Bomb straight
## down, or fires the rocket tube at the dummy, and both sides record, from netfox's own history,
## the state of the blast slot, the dummy and the client's bot for every tick. Each prints one
##   COMBAT_RESULT role=... weapon=... spawn=... explode=... (see _dump)
## line, and the script compares the two sides and the numbers the config gives.
##   -- --host --port=P --weapon=bomb|rocket [--sim-latency-ms=N] [--sim-loss=P]
##   -- --join=127.0.0.1 --port=P --weapon=bomb|rocket [--sim-latency-ms=N] [--sim-loss=P]
## For the rocket the host also gives the client the tube (written on the host until the client's
## first shot), which stands in for walking to the pickup spot.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_SECONDS: float = 90.0
## Where the client's bot is pinned, bot centre in bot heights: a bot height and a half to the
## right of the dummy (the Smelter's dummy stands at x 20), on the floor (top at 16).
const TARGET_BH: Vector2 = Vector2(21.5, 15.5)
const STILL_TICKS: int = 10
const LEAD_TICKS: int = 20
## The client reports first and leaves; the host stays on a while longer.
const CLIENT_LINGER_TICKS: int = 100
const HOST_LINGER_TICKS: int = 160
## A tick is read from the history this many ticks after it happened (more than a round trip at
## 75 ms, with loss), and for this many ticks in a row so none is missed between frames.
const SETTLE_TICKS: int = 20
const READ_WIDTH: int = 10
const DUMMY_PEER_ID: int = 0

var _main: Main = null
var _is_host: bool = false
var _rocket: bool = false
var _cfg: TuningConfig = TuningConfig.get_default()
var _target: Vector2 = Vector2.ZERO
var _pool: WorldObjects = null
var _watch: WorldObject = null
var _hooked: bool = false
var _pin_from: int = -1
var _still: int = 0
var _fire_tick: int = -1
var _blast_seen_tick: int = -1
var _client_peer: int = -1
## tick -> Dictionary of what the history holds for that tick.
var _rows: Dictionary = {}

func _ready() -> void:
	get_tree().create_timer(TIMEOUT_SECONDS).timeout.connect(_fail.bind("timeout"))
	for arg: String in OS.get_cmdline_user_args():
		_is_host = _is_host or arg == "--host"
		_rocket = _rocket or arg == "--weapon=rocket"
	_target = TARGET_BH * _cfg.bot_height_px
	# The spawner's node path must match the host's, so Main goes directly under the root.
	_main = MAIN_SCENE.instantiate() as Main
	get_tree().root.add_child.call_deferred(_main)

func _fail(reason: String) -> void:
	print("FAIL ", reason)
	get_tree().quit(1)

func _bot_of(peer: int) -> Bot:
	for node: Node in get_tree().get_nodes_in_group(&"bots"):
		var bot: Bot = node as Bot
		if bot != null and bot.peer_id == peer:
			return bot
	return null

# The player bot that is not the host's: the one that throws or fires.
func _client_bot() -> Bot:
	for node: Node in get_tree().get_nodes_in_group(&"bots"):
		var bot: Bot = node as Bot
		if bot != null and bot.peer_id > 1:
			return bot
	return null

func _process(_delta: float) -> void:
	if _main == null or not _main.is_inside_tree():
		return
	var client: Bot = _client_bot()
	var dummy: Bot = _bot_of(DUMMY_PEER_ID)
	# The host keeps recording after the client has left; only the recording needs the bots.
	if client != null and dummy != null:
		_client_peer = client.peer_id
		if _pool == null:
			_pool = _main.get_node("Objects") as WorldObjects
			var kind: int = ItemIds.OBJECT_ROCKET if _rocket else ItemIds.OBJECT_BOMB
			_watch = _pool.slots()[_pool.slot_range(kind, client.slot, _cfg).x]
		if _is_host and not _hooked:
			_hooked = true
			# Connected now, so it runs after the resolver's own handler on every pass.
			NetworkRollback.after_process_tick.connect(_on_host_tick)
		if not _is_host and not _hooked and multiplayer.get_unique_id() == client.peer_id:
			_hooked = true
			# Connected after the bot's own input node, so this runs after it has gathered.
			NetworkTime.after_tick.connect(_on_client_tick.bind(client))
		_read_history(client, dummy)
	if _watch == null:
		return
	if _blast_seen_tick < 0 and _watch.blasts >= 1:
		_blast_seen_tick = NetworkTime.tick
	var linger: int = HOST_LINGER_TICKS if _is_host else CLIENT_LINGER_TICKS
	if _blast_seen_tick >= 0 and NetworkTime.tick >= _blast_seen_tick + linger:
		_dump()
		get_tree().quit(0)

# ---- host ----

func _on_host_tick(tick: int) -> void:
	var client: Bot = _client_bot()
	if client == null:
		return
	if _pin_from < 0:
		_pin_from = tick + 5
	if tick >= _pin_from:
		client.global_position = _target
		client.velocity = Vector2.ZERO
	if _rocket and client.arsenal.shots_fired == 0 and client.arsenal.picked_weapon != ItemIds.ROCKET_TUBE:
		client.arsenal.give_weapon(ItemIds.ROCKET_TUBE, MatchSettings.tuning_at(tick))

# ---- client ----

func _on_client_tick(_delta: float, tick: int, bot: Bot) -> void:
	var equipped: bool = not _rocket or bot.arsenal.active_weapon() == ItemIds.ROCKET_TUBE
	if _fire_tick < 0:
		_still = _still + 1 if bot.global_position.distance_to(_target) < 2.0 and equipped else 0
		if _still >= STILL_TICKS:
			_fire_tick = tick + LEAD_TICKS
	# The bomb goes straight down, next to the thrower's feet; the rocket goes left, at the dummy.
	bot.input.aim = Vector2.LEFT if _rocket else Vector2.DOWN
	var now: bool = _fire_tick >= 0 and tick == _fire_tick
	bot.input.fire = now and _rocket
	bot.input.gadget = now and not _rocket

# ---- recording ----

func _prop(snapshot: _Snapshot, node: Node, name: String) -> Variant:
	for path: NodePath in snapshot.get_subject_properties(node):
		if String(path).trim_prefix(":") == name:
			return snapshot.get_property(node, path)
	return null

# What netfox's history holds for each settled tick: the blast slot, the dummy and the client's bot.
func _read_history(client: Bot, dummy: Bot) -> void:
	for tick: int in range(NetworkTime.tick - SETTLE_TICKS - READ_WIDTH, NetworkTime.tick - SETTLE_TICKS):
		var snapshot: _Snapshot = NetworkHistoryServer._get_rollback_state_snapshot(tick)
		if snapshot == null or not snapshot.has_subject(_watch) or not snapshot.has_subject(dummy.vitals) or not snapshot.has_subject(client.vitals):
			continue
		_rows[tick] = {
			"active": _prop(snapshot, _watch, "active"),
			"explode": _prop(snapshot, _watch, "explode_tick"),
			"spawn": _prop(snapshot, _watch, "spawn_tick"),
			"blasts": _prop(snapshot, _watch, "blasts"),
			"slot_pos": _prop(snapshot, _watch, "global_position"),
			"dummy_pos": _prop(snapshot, dummy, "global_position"),
			"dummy_hp": _prop(snapshot, dummy.vitals, "health"),
			"dummy_hits": _prop(snapshot, dummy.vitals, "hits_taken"),
			"dummy_attacker": _prop(snapshot, dummy.vitals, "last_attacker"),
			"client_pos": _prop(snapshot, client, "global_position"),
			"client_hp": _prop(snapshot, client.vitals, "health"),
			"client_hits": _prop(snapshot, client.vitals, "hits_taken"),
		}

# The blast's numbers for this kind of object: radius in bot heights, push, damage at the centre.
func _blast_numbers() -> Array[float]:
	if _rocket:
		var stats: WeaponStats = _cfg.weapon_stats(ItemIds.ROCKET_TUBE)
		return [stats.blast_radius, stats.blast_push, stats.blast_damage]
	return [_cfg.bomb_blast_radius, _cfg.bomb_blast_push, _cfg.bomb_blast_damage]

func _rises(key: String, from_tick: int, to_tick: int) -> int:
	var count: int = 0
	var previous: int = -1
	for tick: int in range(from_tick, to_tick):
		if not _rows.has(tick):
			continue
		var value: int = (_rows[tick] as Dictionary)[key] as int
		if previous >= 0 and value > previous:
			count += 1
		previous = value
	return count

func _dump() -> void:
	var weapon: String = "rocket" if _rocket else "bomb"
	var explode: int = -1
	var spawn: int = -1
	var ticks: Array = _rows.keys()
	ticks.sort()
	for tick: int in ticks:
		var row: Dictionary = _rows[tick]
		if not (row["active"] as bool) and (row["explode"] as int) >= 0 and (row["blasts"] as int) >= 1:
			explode = row["explode"] as int
			spawn = row["spawn"] as int
			break
	if explode < 0 or not _rows.has(explode) or not _rows.has(explode + 1):
		print("COMBAT_RESULT role=%s weapon=%s explode=%d missing_rows=1" % ["host" if _is_host else "client", weapon, explode])
		return
	var before: Dictionary = _rows[explode]
	var after: Dictionary = _rows[explode + 1]
	var numbers: Array[float] = _blast_numbers()
	var px: float = _cfg.bot_height_px
	var centre: Vector2 = after["slot_pos"] as Vector2
	var expect_dummy: float = 0.0
	var expect_client: float = 0.0
	var d_dummy: float = (after["dummy_pos"] as Vector2).distance_to(centre) / px
	var d_client: float = (after["client_pos"] as Vector2).distance_to(centre) / px
	if d_dummy < numbers[0]:
		expect_dummy = numbers[2] * (1.0 - d_dummy / numbers[0])
	if d_client < numbers[0]:
		expect_client = _cfg.self_damage_scale * numbers[2] * (1.0 - d_client / numbers[0])
	var drop_dummy: float = (before["dummy_hp"] as float) - (after["dummy_hp"] as float)
	var drop_client: float = (before["client_hp"] as float) - (after["client_hp"] as float)
	var line: PackedStringArray = PackedStringArray()
	line.append("COMBAT_RESULT role=%s weapon=%s client_peer=%d spawn=%d explode=%d" % ["host" if _is_host else "client", weapon, _client_peer, spawn, explode])
	line.append("d_dummy=%.4f d_client=%.4f expect_dummy=%.4f drop_dummy=%.4f expect_client=%.4f drop_client=%.4f" % [d_dummy, d_client, expect_dummy, drop_dummy, expect_client, drop_client])
	line.append("dummy_hp=%.4f client_hp=%.4f attacker=%d" % [after["dummy_hp"] as float, after["client_hp"] as float, after["dummy_attacker"] as int])
	line.append("dummy_hit_rises=%d client_hit_rises=%d blasts=%d" % [_rises("dummy_hits", explode - 10, explode + 90), _rises("client_hits", explode - 10, explode + 90), after["blasts"] as int])
	line.append("slot_x=%.3f slot_y=%.3f" % [centre.x, centre.y])
	for offset: int in [1, 10, 20, 30, 45]:
		var at: Dictionary = _rows.get(explode + offset, {}) as Dictionary
		var pos: Vector2 = at.get("dummy_pos", Vector2.INF) as Vector2
		line.append("dummy_x%d=%.3f dummy_y%d=%.3f" % [offset, pos.x, offset, pos.y])
	print(" ".join(line))
