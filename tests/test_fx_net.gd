extends Node
## Two-process test of the effects director's first sight (task E), used by tests/net_fx.sh. Both
## processes run the real main scene, with a short bomb fuse (a copy of the config made here).
##   -- --host --port=P [--sim-latency-ms=N]
##        The host gives the dummy bot counters above zero and throws a real Cooker Bomb that has
##        already blasted before the client joins: history the client never saw. When the client's
##        bot has settled, it raises the dummy's hits_taken and shots_fired by one and throws
##        another bomb into the same slot, which blasts again.
##   -- --join=127.0.0.1 --port=P [--sim-latency-ms=N]
##        The client waits until netfox says it holds the host's state for the dummy's Vitals and
##        Arsenal and for the bomb's slot, and checks that the director has shown nothing for the
##        old history. When the raises arrive it checks that the director shows exactly one hit,
##        one shot and one blast, and nothing else (a launch shows nothing of its own), then
##        prints PASS or FAIL lines and exits.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_SECONDS: float = 70.0
## Counters the host sets on the dummy before the client joins.
const OLD_HITS: int = 4
const OLD_SHOTS: int = 5
const OLD_KNOCKOUTS: int = 3
const OLD_SWINGS: int = 2
const FUSE_SECONDS: float = 0.3
## Where the bombs are dropped, bot heights: on the Smelter's floor, far from every bot.
const BOMB_AT: Vector2 = Vector2(30.0, 14.0)
const SETTLE_TICKS: int = 90
const AFTER_TICKS: int = 90
const HOST_LINGER_SECONDS: float = 12.0

var _main: Main = null
var _is_host: bool = false
var _director: EffectsDirector = null
var _events: Array[Array] = []
var _failures: int = 0
var _first_throw_tick: int = -1
var _raise_tick: int = -1

func _ready() -> void:
	get_tree().create_timer(TIMEOUT_SECONDS).timeout.connect(func() -> void:
		print("FAIL timeout")
		get_tree().quit(1))
	for arg: String in OS.get_cmdline_user_args():
		_is_host = _is_host or arg == "--host"
	# Both processes use the same short fuse; it must exist before anything reads the config.
	var cfg: TuningConfig = TuningConfig.get_default().duplicate() as TuningConfig
	cfg.bomb_fuse_time = FUSE_SECONDS
	TuningConfig._cached = cfg
	_main = MAIN_SCENE.instantiate() as Main
	# The spawner's node path must match on both sides, so Main goes directly under the root.
	get_tree().root.add_child.call_deferred(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	_director = _main.get_node("Effects") as EffectsDirector
	_director.effect_triggered.connect(func(kind: StringName, source: Node) -> void: _events.append([kind, source]))
	if _is_host:
		await _run_host()
	else:
		await _run_client()

func _check(ok: bool, label: String) -> void:
	if ok:
		print("PASS ", label)
	else:
		_failures += 1
		print("FAIL ", label)

func _dummy() -> Bot:
	for node: Node in get_tree().get_nodes_in_group(&"bots"):
		var bot: Bot = node as Bot
		if bot != null and bot.peer_id == Bot.DUMMY_PEER:
			return bot
	return null

func _has_client_bot() -> bool:
	for node: Node in get_tree().get_nodes_in_group(&"bots"):
		var bot: Bot = node as Bot
		if bot != null and bot.peer_id > 1:
			return true
	return false

func _objects() -> WorldObjects:
	return _main.get_node("Objects") as WorldObjects

# The slot a bomb of the host's bot (slot 0) goes into first: the first of its bomb range.
func _bomb_slot() -> WorldObject:
	var cfg: TuningConfig = MatchSettings.tuning_at(0)
	return _objects().slots()[_objects().slot_range(ItemIds.OBJECT_BOMB, 0, cfg).x]

func _wait_ticks(ticks: int) -> void:
	var until: int = NetworkTime.tick + ticks
	while NetworkTime.tick < until:
		await get_tree().process_frame

# The host writes like a rule would, in after_process_tick with values that depend only on the
# tick, so every re-run of a tick writes the same thing and netfox records it. A write made from
# _process would be overwritten when netfox restores the recorded state.
func _on_after_process_tick(tick: int) -> void:
	var dummy: Bot = _dummy()
	if dummy == null:
		return
	var raised: bool = _raise_tick >= 0 and tick >= _raise_tick
	dummy.vitals.hits_taken = OLD_HITS + (1 if raised else 0)
	dummy.vitals.ko_serial = OLD_KNOCKOUTS
	dummy.arsenal.shots_fired = OLD_SHOTS + (1 if raised else 0)
	dummy.arsenal.melee_serial = OLD_SWINGS
	if _first_throw_tick < 0:
		_first_throw_tick = tick + 2
	if tick == _first_throw_tick or tick == _raise_tick:
		var cfg: TuningConfig = MatchSettings.tuning_at(tick)
		_objects().launch(ItemIds.OBJECT_BOMB, 0, 1, BOMB_AT * cfg.bot_height_px, Vector2.ZERO, tick, cfg)

func _run_host() -> void:
	NetworkRollback.after_process_tick.connect(_on_after_process_tick)
	print("HOST throws the first bomb and writes the old history")
	while not _has_client_bot():
		await get_tree().process_frame
	await _wait_ticks(SETTLE_TICKS)
	_raise_tick = NetworkTime.tick + 1
	print("HOST raises the counters and throws the second bomb at tick %d" % _raise_tick)
	await get_tree().create_timer(HOST_LINGER_SECONDS).timeout
	print("HOST done (bomb slot launches %d, blasts %d)" % [_bomb_slot().launches, _bomb_slot().blasts])
	# On the host both blasts are real events, and each shows once; the launches show nothing.
	_check(_bomb_slot().blasts == 2 and _count(&"blast", _bomb_slot()) == 2, "host: two blasts of the bomb slot show two blast effects (%d)" % _count(&"blast", _bomb_slot()))
	get_tree().quit(1 if _failures > 0 else 0)

func _count(kind: StringName, source: Node) -> int:
	var total: int = 0
	for event: Array in _events:
		if event[0] == kind and event[1] == source:
			total += 1
	return total

func _describe_events() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for event: Array in _events:
		parts.append("%s@%s" % [event[0], (event[1] as Node).name])
	return ", ".join(parts)

func _run_client() -> void:
	# Bots can be replaced while the session settles, so look them up each time.
	while _dummy() == null or not (NetworkHistoryServer.has_authoritative_state(_dummy().vitals) and NetworkHistoryServer.has_authoritative_state(_dummy().arsenal) and NetworkHistoryServer.has_authoritative_state(_bomb_slot())):
		await get_tree().process_frame
	# Let the display state catch up with the host's state, then look at what the director showed.
	await _wait_ticks(10)
	var dummy: Bot = _dummy()
	_check(dummy.vitals.hits_taken == OLD_HITS and dummy.arsenal.shots_fired == OLD_SHOTS and _bomb_slot().launches == 1 and _bomb_slot().blasts == 1, "the client holds the host's old state (hits %d, shots %d, bomb launches %d, blasts %d)" % [dummy.vitals.hits_taken, dummy.arsenal.shots_fired, _bomb_slot().launches, _bomb_slot().blasts])
	_check(_events.is_empty(), "the director showed nothing for the history the client never saw, a whole bomb included (%d events: %s)" % [_events.size(), _describe_events()])
	while _dummy().vitals.hits_taken == OLD_HITS or _dummy().arsenal.shots_fired == OLD_SHOTS or _bomb_slot().blasts < 2:
		await get_tree().process_frame
	await _wait_ticks(AFTER_TICKS)
	dummy = _dummy()
	_check(_count(&"hit", dummy) == 1 and _count(&"shot", dummy) == 1 and _count(&"blast", _bomb_slot()) == 1, "the raises and the second bomb show exactly one hit, one shot and one blast (%s)" % _describe_events())
	_check(_events.size() == 3, "and nothing else was shown, the second launch included (%d events)" % _events.size())
	print("%d failures" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)
