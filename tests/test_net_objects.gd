extends Node
## One process of the two-process world-object test (tests/net_world_objects.sh). It instances
## scenes/main.tscn directly under the root, the way the game does, and only watches and
## drives:
##   -- --host --port=P --sim-latency-ms=75     the host: records the slot of the client's bomb
##   -- --join=127.0.0.1 --port=P --sim-latency-ms=75
##        the client: its bot throws one Cooker Bomb, then it records the same slot
## Both print one OBJRESULT line and a few OBJTRACE lines; the script compares them. The bomb
## is thrown by setting the local bot's gadget and aim inputs after BotInput has gathered
## them, so no shared file is touched.
## The host also asks the rollback to run the launch tick and the explosion tick again (see
## _on_before_loop), counts the passes of each, and prints one RESIM line for each: every pass
## must have produced the same slot state, so a re-simulation neither repeats nor loses the launch.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_SECONDS: float = 40.0
const THROW_DELAY_TICKS: int = 60
const CLIENT_LINGER_TICKS: int = 60
const HOST_LINGER_TICKS: int = 240

var _main: Main = null
var _role: String = ""
var _pool: WorldObjects = null
var _watch: WorldObject = null
var _throw_tick: int = -1
## tick -> [active, explode_tick, spawn_tick, launches, blasts, position]
var _rows: Dictionary = {}
var _high_launches: int = 0
var _high_blasts: int = 0
var _launch_rises: int = 0
var _blast_rises: int = 0
var _drops: int = 0
var _blast_seen_tick: int = -1
## Host: tick -> passes in which the slot was launched / exploded at that tick, and the distinct
## slot states those passes ended with.
var _passes: Dictionary = {}
var _pass_states: Dictionary = {}
var _requested: Array[int] = []

func _ready() -> void:
	get_tree().create_timer(TIMEOUT_SECONDS).timeout.connect(_fail.bind("timeout"))
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--host":
			_role = "host"
		elif arg.begins_with("--join"):
			_role = "client"
	_main = MAIN_SCENE.instantiate() as Main
	# The spawner's node path must match the host's, so Main goes directly under root.
	get_tree().root.add_child.call_deferred(_main)

func _fail(reason: String) -> void:
	print("FAIL ", reason)
	get_tree().quit(1)

# The bot that throws: the client's own bot, or on the host the one player bot that is not the host's (peer 0 is the dummy).
func _thrower() -> Bot:
	var bots: Node = _main.get_node_or_null("Bots")
	if bots == null:
		return null
	for child: Node in bots.get_children():
		var bot: Bot = child as Bot
		if bot == null:
			continue
		if _role == "client" and bot.peer_id == multiplayer.get_unique_id():
			return bot
		if _role == "host" and bot.peer_id > 1:
			return bot
	return null

func _process(_delta: float) -> void:
	if _main == null or not _main.is_inside_tree():
		return
	if _pool == null:
		# The slot is found once; the thrower may leave later without ending the recording.
		var bot: Bot = _thrower()
		if bot == null:
			return
		_pool = _main.get_node("Objects") as WorldObjects
		var cfg: TuningConfig = MatchSettings.tuning_at(0)
		_watch = _pool.slots()[_pool.slot_range(ItemIds.OBJECT_BOMB, bot.slot, cfg).x]
		if _role == "host":
			# Connected now, so it runs after the resolver's own handler on every pass.
			NetworkRollback.after_process_tick.connect(_on_after_process_tick)
			NetworkRollback.before_loop.connect(_on_before_loop)
		if _role == "client":
			_throw_tick = NetworkTime.tick + THROW_DELAY_TICKS
			# Connected after the bot's own input node, so this runs after it has gathered.
			NetworkTime.after_tick.connect(_after_gather.bind(bot))
	_note_counters()
	_read_history()
	if _blast_seen_tick < 0 and _watch.blasts >= 1:
		_blast_seen_tick = NetworkTime.tick
	var linger: int = CLIENT_LINGER_TICKS if _role == "client" else HOST_LINGER_TICKS
	if _blast_seen_tick >= 0 and NetworkTime.tick >= _blast_seen_tick + linger:
		_dump()
		get_tree().quit(0)

# Every pass of every tick, re-simulated ones included: note the passes in which this slot was
# launched, or exploded, at that tick, and the state each pass left it in.
func _on_after_process_tick(tick: int) -> void:
	if not ((_watch.active and _watch.spawn_tick == tick) or _watch.explode_tick == tick):
		return
	_passes[tick] = (_passes.get(tick, 0) as int) + 1
	var states: Dictionary = _pass_states.get_or_add(tick, {}) as Dictionary
	states["launches=%d,blasts=%d,spawn=%d,explode=%d,active=%d" % [_watch.launches, _watch.blasts, _watch.spawn_tick, _watch.explode_tick, int(_watch.active)]] = true

# Test stimulus: a few ticks after each of those ticks, ask the rollback to run it again from two
# ticks earlier, the way a late input from a second client would.
func _on_before_loop() -> void:
	for tick: int in _passes.keys():
		if (_passes[tick] as int) == 1 and not _requested.has(tick) and NetworkTime.tick >= tick + 2 and tick - 2 >= NetworkRollback.history_start:
			_requested.append(tick)
			NetworkRollback.notify_resimulation_start(tick - 2)

func _after_gather(_delta: float, tick: int, bot: Bot) -> void:
	bot.input.aim = Vector2(-1.0, 0.0)
	bot.input.gadget = tick == _throw_tick

# What the effects would see: every change of the counters, frame by frame.
func _note_counters() -> void:
	if _watch.launches > _high_launches:
		_launch_rises += 1
		_high_launches = _watch.launches
	elif _watch.launches < _high_launches:
		_drops += 1
		_high_launches = _watch.launches
	if _watch.blasts > _high_blasts:
		_blast_rises += 1
		_high_blasts = _watch.blasts
	elif _watch.blasts < _high_blasts:
		_drops += 1
		_high_blasts = _watch.blasts

# The state of the watched slot at each tick, as netfox's own history holds it, read once the
# tick is old enough to be settled (a few round trips) and before the history forgets it.
func _read_history() -> void:
	for tick: int in range(NetworkTime.tick - 20, NetworkTime.tick - 11):
		var snapshot: _Snapshot = NetworkHistoryServer._get_rollback_state_snapshot(tick)
		if snapshot == null or not snapshot.has_subject(_watch):
			continue
		var row: Array = []
		for prop: String in ["active", "explode_tick", "spawn_tick", "launches", "blasts", "global_position"]:
			row.append(_property(snapshot, prop))
		_rows[tick] = row

func _property(snapshot: _Snapshot, prop: String) -> Variant:
	for path: NodePath in snapshot.get_subject_properties(_watch):
		if String(path).trim_prefix(":") == prop:
			return snapshot.get_property(_watch, path)
	return null

func _dump() -> void:
	if _role == "host":
		_print_resim()
	var ticks: Array = _rows.keys()
	ticks.sort()
	var on_tick: int = -1
	var off_tick: int = -1
	for tick: int in ticks:
		var row: Array = _rows[tick]
		if on_tick < 0 and row[0] as bool:
			on_tick = tick
		elif on_tick >= 0 and off_tick < 0 and not (row[0] as bool):
			off_tick = tick
	if on_tick < 0 or off_tick < 0:
		print("OBJRESULT role=%s on_tick=%d off_tick=%d" % [_role, on_tick, off_tick])
		return
	for tick: int in range(on_tick - 1, on_tick + 2):
		print("OBJTRACE role=%s tick=%d active=%d" % [_role, tick, int((_rows[tick] as Array)[0] as bool) if _rows.has(tick) else -1])
	for tick: int in range(off_tick - 1, off_tick + 2):
		print("OBJTRACE role=%s tick=%d active=%d" % [_role, tick, int((_rows[tick] as Array)[0] as bool) if _rows.has(tick) else -1])
	var gone: Array = _rows[off_tick]
	var pos: Vector2 = gone[5] as Vector2
	var active_ticks: int = 0
	for tick: int in ticks:
		if tick >= on_tick and tick < off_tick and not (_rows[tick] as Array)[0] as bool:
			active_ticks += 1
	print("OBJRESULT role=%s on_tick=%d off_tick=%d explode_tick=%d spawn_tick=%d x=%.3f y=%.3f launches=%d blasts=%d launch_rises=%d blast_rises=%d drops=%d holes=%d" % [
		_role, on_tick, off_tick, gone[1] as int, (_rows[on_tick] as Array)[2] as int, pos.x, pos.y, gone[3] as int, gone[4] as int, _launch_rises, _blast_rises, _drops, active_ticks])

# One RESIM line per such tick: how many passes the host made and how many distinct slot states
# they left (1 when every pass agrees).
func _print_resim() -> void:
	var ticks: Array = _passes.keys()
	ticks.sort()
	for tick: int in ticks:
		var states: Dictionary = _pass_states[tick] as Dictionary
		print("RESIM tick=%d passes=%d states=%d requested=%d state=%s" % [tick, _passes[tick] as int, states.size(), int(_requested.has(tick)), states.keys()[0] as String])
