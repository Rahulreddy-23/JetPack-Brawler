extends Node
## Two-process test of the fire path (task C), used by tests/net_fire.sh. It runs the real main
## scene. The host pins the client's bot a few bot heights from its own bot, in the line of
## fire (test scaffolding written in after_process_tick, like a rule would); the client then
## holds the fire input with the rivet gun for exactly SHOTS shots and stops. Each side prints
## what its own state says:
##   FIRE_RESULT role=host|client peer=P shots=N last_shot=T [first=F interval=I expect_last=L]
##   FIRE_HIT tick=T victims=PEERS count=K passes=P      (host only, one per fire tick)
##   FIRE_CHECK pass_mismatches=M settled=S settled_mismatches=X requested=R   (host only)
## The host also asks the rollback to run each fire tick again (see _on_before_loop), so every
## fire tick is processed at least twice, and compares the passes with each other and with
## the recorded history.
## The host's hit list comes from calling WeaponRules.collect itself on every pass (task B's
## rules are not in this tree), so what is checked is which bot the shot names as victim.
##   -- --host --port=P [--sim-latency-ms=N]      host, then wait for the client's shots
##   -- --join=127.0.0.1 --port=P [--sim-latency-ms=N]   client, hold fire, report

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const LAYOUT: ArenaLayout = preload("res://config/smelter.tres")
const SHOTS: int = 5
const TIMEOUT_SECONDS: float = 60.0
## Where the client's bot is pinned, bot centre in bot heights: five bot heights to the right
## of the host's bot, standing on the Smelter's floor (top at 16), nothing between them.
const TARGET_BH: Vector2 = Vector2(9.0, 15.5)
## Aim of the client: straight left, at the host's bot.
const AIM: Vector2 = Vector2.LEFT
## Ticks the client's bot must stand at the target before it starts firing.
const STILL_TICKS: int = 10
## Ticks between seeing it there and the first shot.
const LEAD_TICKS: int = 20
## Ticks after the last shot before the client reports.
const CLIENT_SETTLE_TICKS: int = 180
## Seconds the host waits, after the client's shot count stops changing, before it reports.
const HOST_SETTLE_SECONDS: float = 2.5
## Seconds the host waits for the client to leave after reporting.
const HOST_LINGER_SECONDS: float = 12.0

var _main: Main = null
var _is_host: bool = false
var _cfg: TuningConfig = TuningConfig.get_default()
var _solids: Array[Rect2] = []
var _target: Vector2 = Vector2.ZERO
var _interval: int = 0
# Host: tick from which the client's bot is pinned; per fire tick the victims and the passes.
var _pin_from: int = -1
var _victims: Dictionary = {}
var _passes: Dictionary = {}
# Per fire tick: what the first pass saw, what the latest pass saw (state only), and whether the
# host has been asked to run it again.
var _first_seen: Dictionary = {}
var _last_state: Dictionary = {}
var _requested: Array[int] = []
var _pass_mismatches: int = 0
var _settled: Array[int] = []
var _settled_mismatches: int = 0
var _seen_shots: int = -1
var _seen_since_msec: int = 0
var _reported: bool = false
var _report_msec: int = 0
# Client: first tick of the fire input, ticks the bot has been at the target.
var _hooked: bool = false
var _still: int = 0
var _first_tick: int = -1

func _ready() -> void:
	get_tree().create_timer(TIMEOUT_SECONDS).timeout.connect(_fail.bind("timeout"))
	for arg: String in OS.get_cmdline_user_args():
		_is_host = _is_host or arg == "--host"
	_target = TARGET_BH * _cfg.bot_height_px
	_solids = LAYOUT.solid_rects_px(_cfg.bot_height_px)
	_interval = int(round(_cfg.weapons[ItemIds.RIVET_GUN].fire_interval * float(_cfg.tick_rate)))
	# The spawner's node path must match the host's, so Main goes directly under the root.
	_main = MAIN_SCENE.instantiate() as Main
	get_tree().root.add_child.call_deferred(_main)
	if _is_host:
		await get_tree().process_frame
		NetworkRollback.after_process_tick.connect(_on_host_tick)
		NetworkRollback.before_loop.connect(_on_before_loop)

func _fail(reason: String) -> void:
	print("FAIL ", reason)
	get_tree().quit(1)

func _bots() -> Array[Bot]:
	var bots: Array[Bot] = []
	for node: Node in get_tree().get_nodes_in_group(&"bots"):
		bots.append(node as Bot)
	bots.sort_custom(func(a: Bot, b: Bot) -> bool: return a.peer_id < b.peer_id)
	return bots

func _bot_of(peer: int) -> Bot:
	for bot: Bot in _bots():
		if bot.peer_id == peer:
			return bot
	return null

func _client_bot() -> Bot:
	# Peer 1 is the host and peer 0 is the dummy; the client's bot is any other peer.
	for bot: Bot in _bots():
		if bot.peer_id > 1:
			return bot
	return null

# ---- host ----

# Runs on every pass of every tick, including re-simulated ones. It must give the same result
# for the same tick every time, so everything here is a function of the tick and the state.
func _on_host_tick(tick: int) -> void:
	var client: Bot = _client_bot()
	if client == null or _bot_of(1) == null:
		return
	if _pin_from < 0:
		_pin_from = tick + 5
	if tick >= _pin_from:
		client.global_position = _target
		client.velocity = Vector2.ZERO
	# What the host's rules would produce for this tick, from the state as it is now.
	if not client.arsenal.fired_at(tick):
		_victims.erase(tick)
		# A fire tick that stops being one on a later pass is a mismatch.
		if _first_seen.has(tick):
			_pass_mismatches += 1
		return
	var hits: Array[Hit] = []
	WeaponRules.collect(tick, _bots(), _main.get_node("Objects") as WorldObjects, _solids, MatchSettings.tuning_at(tick), hits)
	var peers: PackedStringArray = PackedStringArray()
	for hit: Hit in hits:
		if hit.attacker_peer == client.peer_id:
			peers.append(str(hit.victim.peer_id))
	_victims[tick] = ",".join(peers)
	_passes[tick] = (_passes.get(tick, 0) as int) + 1
	var state: String = _state_text(client)
	var seen: String = "%s|%s" % [state, _victims[tick] as String]
	if not _first_seen.has(tick):
		_first_seen[tick] = seen
	elif _first_seen[tick] != seen:
		_pass_mismatches += 1
	_last_state[tick] = state

func _state_text(client: Bot) -> String:
	var arsenal: BotArsenal = client.arsenal
	return "%d,%d,%d,%d" % [arsenal.shots_fired, arsenal.picked_ammo, arsenal.last_shot_tick, arsenal.fire_ready_tick]

# Test stimulus: a few ticks after each fire tick, ask the rollback to run it again from two
# ticks earlier, the way a late input from a second client would. netfox's own re-simulations are
# counted the same way.
func _on_before_loop() -> void:
	for tick: int in _passes.keys():
		if (_passes[tick] as int) == 1 and not _requested.has(tick) and NetworkTime.tick >= tick + 2 and tick - 2 >= NetworkRollback.history_start:
			_requested.append(tick)
			NetworkRollback.notify_resimulation_start(tick - 2)

# What the host's recorded history holds for the tick after a fire tick, once it has settled.
func _sample_settled(client: Bot) -> void:
	for tick: int in _last_state.keys():
		if _settled.has(tick) or NetworkTime.tick < tick + 10:
			continue
		var snapshot: _Snapshot = NetworkHistoryServer._get_rollback_state_snapshot(tick + 1)
		if snapshot == null or not snapshot.has_property(client.arsenal, ^"shots_fired"):
			continue
		_settled.append(tick)
		var arsenal: BotArsenal = client.arsenal
		var recorded: String = "%d,%d,%d,%d" % [
			snapshot.get_property(arsenal, ^"shots_fired") as int, snapshot.get_property(arsenal, ^"picked_ammo") as int,
			snapshot.get_property(arsenal, ^"last_shot_tick") as int, snapshot.get_property(arsenal, ^"fire_ready_tick") as int]
		if recorded != _last_state[tick]:
			_settled_mismatches += 1

func _process(_delta: float) -> void:
	if _is_host:
		_process_host()
	elif not _hooked:
		_hook_client()

func _process_host() -> void:
	var client: Bot = _client_bot()
	var now: int = Time.get_ticks_msec()
	if _reported:
		if client == null or now - _report_msec > int(HOST_LINGER_SECONDS * 1000.0):
			get_tree().quit(0)
		return
	if client == null:
		if _seen_shots >= 0:
			_fail("the client left before the host reported")
		return
	_sample_settled(client)
	if client.arsenal.shots_fired != _seen_shots:
		_seen_shots = client.arsenal.shots_fired
		_seen_since_msec = now
		return
	if _seen_shots == SHOTS and now - _seen_since_msec >= int(HOST_SETTLE_SECONDS * 1000.0):
		_report_host(client)

func _report_host(client: Bot) -> void:
	print("FIRE_RESULT role=host peer=%d shots=%d last_shot=%d" % [client.peer_id, client.arsenal.shots_fired, client.arsenal.last_shot_tick])
	var ticks: Array = _victims.keys()
	ticks.sort()
	for tick: int in ticks:
		var victims: String = _victims[tick] as String
		print("FIRE_HIT tick=%d victims=%s count=%d passes=%d" % [tick, victims, victims.split(",", false).size(), _passes.get(tick, 0) as int])
	print("FIRE_CHECK pass_mismatches=%d settled=%d settled_mismatches=%d requested=%d" % [_pass_mismatches, _settled.size(), _settled_mismatches, _requested.size()])
	_reported = true
	_report_msec = Time.get_ticks_msec()

# ---- client ----

# The bot's own input node gathers in NetworkTime.after_tick; this handler is connected after
# the bot exists, so it runs after the gathering and overrides it.
func _hook_client() -> void:
	if multiplayer.get_unique_id() == 1 or _bot_of(multiplayer.get_unique_id()) == null:
		return
	_hooked = true
	NetworkTime.after_tick.connect(_on_client_tick)

func _on_client_tick(_delta: float, tick: int) -> void:
	var bot: Bot = _bot_of(multiplayer.get_unique_id())
	if bot == null:
		return
	if _first_tick < 0:
		_still = _still + 1 if bot.global_position.distance_to(_target) < 2.0 else 0
		if _still >= STILL_TICKS:
			_first_tick = tick + LEAD_TICKS
	var last_tick: int = _first_tick + _interval * (SHOTS - 1)
	bot.input.aim = AIM
	bot.input.fire = _first_tick >= 0 and tick >= _first_tick and tick <= last_tick
	if _first_tick >= 0 and tick >= last_tick + CLIENT_SETTLE_TICKS:
		print("FIRE_RESULT role=client peer=%d shots=%d last_shot=%d first=%d interval=%d expect_last=%d" % [bot.peer_id, bot.arsenal.shots_fired, bot.arsenal.last_shot_tick, _first_tick, _interval, last_tick])
		get_tree().quit(0)
