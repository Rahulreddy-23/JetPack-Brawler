extends Node
## Probe for tests/net_combat.sh: one process of a host plus client run of the real main scene
## with the hazard times shortened (a copy of the config made here; config/tuning.tres is not
## touched). Every bot idles on the floor, so the hazard knocks it out once the metal rises, it
## stays out until the next cycle starts (phase 1 test-cycle rule), and at the start of the next
## cycle everything resets and the bot is knocked out again when the hazard rises. Each process
## records the state it has for every bot and every tick, and at the end prints
##   ROUND start=R cycle=C expect_first_ko=T max_health=H
##   EV peer=P tick=T serial=S out=0|1 respawn=R cycle=I health=H
##       (every change of knocked_out, ko_serial or cycle_index)
##   LAST tick=N
##   DUMMY tick=T x=X y=Y
## which the script compares between the two processes.
## Launch: godot --headless --path . res://tests/test_combat_net.tscn -- --host|--join=ADDR
##   --port=P --sim-latency-ms=75

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const LAYOUT: ArenaLayout = preload("res://config/smelter.tres")
const HazardMath := preload("res://hazard/hazard_math.gd")
## A round start so far ahead that no hazard runs until the host sets the real one.
const FAR_TICK: int = 1000000
const START_DELAY_TICKS: int = 20
const CLIENT_SETTLE_TICKS: int = 60
const TAIL_TICKS: int = 120
const TIMEOUT_SECONDS: float = 90.0
## Ticks a recorded state has to age before it is read (twice the latency, in ticks, plus margin).
const SETTLE_TICKS: int = 12
const KNOCKED_OUT: NodePath = ^"knocked_out"
const KO_SERIAL: NodePath = ^"ko_serial"
const RESPAWN_TICK: NodePath = ^"respawn_tick"
const POSITION: NodePath = ^"global_position"
const CYCLE_INDEX: NodePath = ^"cycle_index"
const HEALTH: NodePath = ^"health"
## Shortened hazard timing for this test, seconds.
const HAZARD_START: float = 2.0
const HAZARD_CAP: float = 4.0
const HAZARD_CYCLE: float = 6.0
const RESPAWN: float = 1.0

var _is_host: bool = false
var _cfg: TuningConfig = null
var _main: Main = null
var _start: int = -1
## peer id -> {tick: [knocked_out, ko_serial, respawn_tick, position]}
var _rows: Dictionary = {}
var _last_tick: int = -1

func _ready() -> void:
	get_tree().create_timer(TIMEOUT_SECONDS).timeout.connect(func() -> void:
		print("FAIL timeout")
		get_tree().quit(1))
	for arg: String in OS.get_cmdline_user_args():
		_is_host = _is_host or arg == "--host"
	# Both processes use the same shortened copy; it must exist before anything reads the config.
	_cfg = TuningConfig.get_default().duplicate() as TuningConfig
	_cfg.hazard_start_time = HAZARD_START
	_cfg.hazard_cap_time = HAZARD_CAP
	_cfg.hazard_cycle_time = HAZARD_CYCLE
	_cfg.respawn_time = RESPAWN
	TuningConfig._cached = _cfg
	_main = MAIN_SCENE.instantiate() as Main
	# The spawner's node path must match on both sides, so Main goes directly under the root.
	get_tree().root.add_child.call_deferred(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	NetworkRollback.on_record_tick.connect(_on_record_tick)
	if _is_host:
		MatchSettings.start_round(FAR_TICK)
	_run()

func _bots() -> Array[Bot]:
	var result: Array[Bot] = []
	for node: Node in get_tree().get_nodes_in_group(&"bots"):
		var bot: Bot = node as Bot
		if bot != null:
			result.append(bot)
	return result

# The state netfox holds for a tick that is SETTLE_TICKS old (corrections from the host have had
# time to arrive), read from its history and not from the live nodes: a bot this peer does not
# simulate keeps showing an older tick's values in the live node.
func _on_record_tick(tick: int) -> void:
	_last_tick = tick
	var old: int = tick - SETTLE_TICKS
	var snapshot: _Snapshot = NetworkHistoryServer._get_rollback_state_snapshot(old)
	if snapshot == null:
		return
	for bot: Bot in _bots():
		var vitals: BotVitals = bot.vitals
		if not snapshot.has_property(vitals, KNOCKED_OUT):
			continue
		var rows: Dictionary = _rows.get_or_add(bot.peer_id, {}) as Dictionary
		rows[old] = [
			snapshot.get_property(vitals, KNOCKED_OUT),
			snapshot.get_property(vitals, KO_SERIAL),
			snapshot.get_property(vitals, RESPAWN_TICK),
			snapshot.get_property(bot, POSITION),
			snapshot.get_property(vitals, CYCLE_INDEX),
			snapshot.get_property(vitals, HEALTH),
		]

func _run() -> void:
	if _is_host:
		# Wait for a client bot and let it settle, then start the round a little ahead.
		while not _has_client_bot():
			await get_tree().process_frame
		var settled_at: int = NetworkTime.tick + CLIENT_SETTLE_TICKS
		while NetworkTime.tick < settled_at:
			await get_tree().process_frame
		_start = NetworkTime.tick + START_DELAY_TICKS
		MatchSettings.start_round(_start)
	else:
		# The client sees the far value first, then the real start.
		while MatchSettings.round_start_tick < 0 or MatchSettings.round_start_tick >= FAR_TICK:
			await get_tree().process_frame
		_start = MatchSettings.round_start_tick
	var cycle: int = roundi(HAZARD_CYCLE * float(_cfg.tick_rate))
	while NetworkTime.tick < _start + cycle + TAIL_TICKS:
		await get_tree().process_frame
	_report(cycle)
	get_tree().quit(0)

func _has_client_bot() -> bool:
	for bot: Bot in _bots():
		if bot.peer_id > 1:
			return true
	return false

# The first tick at which a body resting on the floor is in the metal, plus one: the state shows
# the knockout one tick after the tick the resolver decided it.
func _expected_first_ko() -> int:
	var rest: float = LAYOUT.bounds.end.y * _cfg.bot_height_px
	for ticks: int in roundi(HAZARD_CYCLE * float(_cfg.tick_rate)):
		if HazardMath.is_in_metal(rest, ticks, _cfg.tick_rate, HAZARD_START, HAZARD_CAP, rest, LAYOUT.hazard_top * _cfg.bot_height_px):
			return _start + ticks + 1
	return -1

func _report(cycle: int) -> void:
	print("ROUND start=%d cycle=%d expect_first_ko=%d max_health=%d" % [_start, cycle, _expected_first_ko(), roundi(_cfg.max_health)])
	for peer: int in _rows:
		var rows: Dictionary = _rows[peer]
		var ticks: Array = rows.keys()
		ticks.sort()
		var previous: Array = []
		for tick: int in ticks:
			var row: Array = rows[tick]
			if not previous.is_empty() and (row[0] != previous[0] or row[1] != previous[1] or row[4] != previous[4]):
				print("EV peer=%d tick=%d serial=%d out=%d respawn=%d cycle=%d health=%d" % [peer, tick, row[1] as int, int(row[0] as bool), row[2] as int, row[4] as int, roundi(row[5] as float)])
			previous = row
	print("LAST tick=%d" % _last_tick)
	var probe_tick: int = _start + cycle + 60
	var dummy_rows: Dictionary = _rows.get(Bot.DUMMY_PEER, {}) as Dictionary
	if dummy_rows.has(probe_tick):
		var pos: Vector2 = (dummy_rows[probe_tick] as Array)[3]
		print("DUMMY tick=%d x=%.3f y=%.3f" % [probe_tick, pos.x, pos.y])
	else:
		print("DUMMY missing")
