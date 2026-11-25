extends Node
## Headless test of how far a push moves a bot (the push-distance rule, see CombatRules). The real
## Bot movement and the real CombatRules / BotArsenal run on instanced bots, tick by tick. Run:
##   godot --headless --path . res://tests/test_push_distance.tscn
## Exits 0 when every check passes, 1 otherwise. Numbers come from the shared config.

const BOT_SCENE: PackedScene = preload("res://scenes/bot.tscn")
const LAYOUT: ArenaLayout = preload("res://config/smelter.tres")
const CombatMath := preload("res://combat/combat_math.gd")
const TIMEOUT_SECONDS: float = 120.0
const SETTLE_TICKS: int = 5
const RUN_TICKS: int = 180
const AIR_HEIGHT_BH: float = 150.0
## "0 health" in the tests: zero itself is a knockout, and a knocked-out bot is not pushed.
const ALMOST_ZERO: float = 0.0001

var _cfg: TuningConfig = TuningConfig.get_default()
var _px: float = 0.0
var _dt: float = 0.0
var _tick: int = 100
var _failures: int = 0
var _checks: int = 0
var _nodes: Array[Node] = []

func _ready() -> void:
	get_tree().create_timer(TIMEOUT_SECONDS).timeout.connect(func() -> void:
		print("FAIL timeout, the test did not finish")
		get_tree().quit(1))
	_run()

func _run() -> void:
	_px = _cfg.bot_height_px
	_dt = 1.0 / float(_cfg.tick_rate)
	_add_floor()
	await _test_ground_distances()
	await _test_air_distances()
	await _test_summed_pushes()
	await _test_recoil()
	await _test_vertical()
	await _test_push_during_dash()
	await _test_window()
	await _test_opposing_push_window()
	_test_inverse()
	await _test_travel_distance_in_play()
	await _test_accumulation()
	await _test_stick()
	await _test_window_sideways()
	await _test_diagonal()
	print("%d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)

# ---- helpers ----

func _check(ok: bool, label: String) -> void:
	_checks += 1
	if ok:
		print("PASS ", label)
	else:
		_failures += 1
		print("FAIL ", label)

func _add_floor() -> void:
	var body: StaticBody2D = StaticBody2D.new()
	body.position = Vector2(0.0, 50.0)
	body.collision_layer = Bot.LAYER_SOLID
	body.collision_mask = 0
	var shape_node: CollisionShape2D = CollisionShape2D.new()
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = Vector2(400000.0, 100.0)
	shape_node.shape = shape
	body.add_child(shape_node)
	add_child(body)

# A bot at rest: standing on the floor (top at y = 0), or far above it. Settled for a few ticks.
func _spawn(grounded: bool) -> Bot:
	var bot: Bot = BOT_SCENE.instantiate() as Bot
	bot.position = Vector2(0.0, -_px / 2.0 - 0.5) if grounded else Vector2(0.0, -AIR_HEIGHT_BH * _px)
	add_child(bot)
	_nodes.append(bot)
	await get_tree().physics_frame
	await get_tree().physics_frame
	bot.arsenal.reset_for_spawn(_cfg)
	bot.fuel = 0.0
	_run_ticks(bot, SETTLE_TICKS)
	if not grounded:
		bot.velocity = Vector2.ZERO
	return bot

func _free_bots() -> void:
	for node: Node in _nodes:
		node.free()
	_nodes.clear()
	await get_tree().physics_frame
	await get_tree().physics_frame

# Tick the bot's own movement, then its arsenal, the way netfox orders them.
func _run_ticks(bot: Bot, ticks: int) -> void:
	for i: int in ticks:
		bot._rollback_tick(_dt, _tick, true)
		bot.arsenal._rollback_tick(_dt, _tick, true)
		_tick += 1

func _push_hit(victim: Bot, push: Vector2) -> Hit:
	var hit: Hit = Hit.new()
	hit.victim = victim
	hit.attacker_peer = 2
	hit.push = push
	return hit

func _apply(bot: Bot, hits: Array[Hit]) -> void:
	var bots: Array[Bot] = [bot]
	CombatRules.apply(_tick - 1, bots, hits, LAYOUT, _cfg)

# Travel in bot heights of a bot at rest hit by the given pushes (all in one tick) with a neutral
# stick: x is the sideways travel when the bot has stopped sideways (the run is long enough that
# an airborne bot has stopped and still not landed), y is the highest point reached above the start.
func _travel(grounded: bool, health: float, pushes: Array[Vector2]) -> Vector2:
	var bot: Bot = await _spawn(grounded)
	bot.vitals.health = health
	var start: Vector2 = bot.position
	var hits: Array[Hit] = []
	for push: Vector2 in pushes:
		hits.append(_push_hit(bot, push))
	_apply(bot, hits)
	var rise: float = 0.0
	for i: int in RUN_TICKS:
		_run_ticks(bot, 1)
		rise = maxf(rise, start.y - bot.position.y)
	var travel: Vector2 = Vector2((bot.position.x - start.x) / _px, rise / _px)
	_check(absf(bot.velocity.x) < 0.001, "the bot has stopped sideways before the run ends (grounded %s, pushes %s, vx %.3f)" % [grounded, pushes, bot.velocity.x])
	await _free_bots()
	return travel

# The same for the scrap blaster's recoil on the shooter, fired once toward aim.
func _recoil_travel(grounded: bool, aim: Vector2, health: float) -> Vector2:
	var bot: Bot = await _spawn(grounded)
	bot.vitals.health = health
	bot.arsenal.give_weapon(ItemIds.SCRAP_BLASTER, _cfg)
	bot.input.aim = aim
	bot.input.fire = true
	# The firing tick moves the bot before the shot (gravity in the air), so the hop is
	# measured from where the bot was when it fired.
	_run_ticks(bot, 1)
	bot.input.fire = false
	var start: Vector2 = bot.position
	var rise: float = 0.0
	for i: int in RUN_TICKS:
		_run_ticks(bot, 1)
		rise = maxf(rise, start.y - bot.position.y)
	var travel: Vector2 = Vector2((bot.position.x - start.x) / _px, rise / _px)
	await _free_bots()
	return travel

func _scrap_pellets() -> Array[Vector2]:
	var scrap: WeaponStats = _cfg.weapon_stats(ItemIds.SCRAP_BLASTER)
	var pellets: Array[Vector2] = []
	for i: int in scrap.pellets:
		pellets.append(Vector2.RIGHT * scrap.push)
	return pellets

# The design's tolerance: within 5 percent or 0.05 bot heights, whichever is larger.
func _within(got: float, want: float, label: String) -> void:
	_check(absf(got - want) <= maxf(0.05 * want, 0.05), "%s (got %.3f bh, want %.3f bh)" % [label, got, want])

# Every push of the design with its distance in bot heights (all pushes along +x).
func _cases() -> Array:
	var scrap: WeaponStats = _cfg.weapon_stats(ItemIds.SCRAP_BLASTER)
	var bolt: WeaponStats = _cfg.weapon_stats(ItemIds.BOLT_THROWER)
	var rocket: WeaponStats = _cfg.weapon_stats(ItemIds.ROCKET_TUBE)
	var centre: Vector2 = CombatMath.blast_push(Vector2(0.001, 0.0), Vector2.ZERO, rocket.blast_push, rocket.blast_radius)
	var half: Vector2 = CombatMath.blast_push(Vector2(rocket.blast_radius / 2.0, 0.0), Vector2.ZERO, rocket.blast_push, rocket.blast_radius)
	return [
		["melee", [Vector2.RIGHT * _cfg.melee_push] as Array[Vector2], _cfg.melee_push],
		["scrap blast, point blank (all pellets)", _scrap_pellets(), scrap.push * float(scrap.pellets)],
		["bolt", [Vector2.RIGHT * bolt.push] as Array[Vector2], bolt.push],
		["blast at the centre", [centre] as Array[Vector2], rocket.blast_push],
		["blast at half the radius", [half] as Array[Vector2], rocket.blast_push / 2.0],
	]

# THE RULE: on flat ground with a neutral stick a push of P bot heights moves the bot P bot
# heights, twice that at 0 health and 1.5 times at half the low-health threshold.
func _test_ground_distances() -> void:
	for case: Array in _cases():
		var pushes: Array[Vector2] = case[1]
		var want: float = case[2]
		var full: float = (await _travel(true, _cfg.max_health, pushes)).x
		var low: float = (await _travel(true, _cfg.low_health_threshold, pushes)).x
		var half: float = (await _travel(true, _cfg.low_health_threshold / 2.0, pushes)).x
		var zero: float = (await _travel(true, ALMOST_ZERO, pushes)).x
		print("TABLE ground %-38s design %.2f | full %.3f | at 25 %.3f | at 12.5 %.3f | at 0 %.3f" % [case[0], want, full, low, half, zero])
		_within(full, want, "ground, full health: %s moves the bot its design distance" % case[0])
		_within(low, want, "ground, at the low-health threshold: %s is not multiplied" % case[0])
		_within(half, want * 1.5, "ground, at half the threshold: %s moves the bot 1.5 times as far" % case[0])
		_within(zero, want * 2.0, "ground, at 0 health: %s moves the bot twice as far, not four times" % case[0])

# In the air braking is weaker, so a push carries further (the GDD's "momentum carries"). Not a
# distance to hold to the design number; reported, and never shorter than on the ground.
func _test_air_distances() -> void:
	for case: Array in _cases():
		var pushes: Array[Vector2] = case[1]
		var ground: float = (await _travel(true, _cfg.max_health, pushes)).x
		var full: float = (await _travel(false, _cfg.max_health, pushes)).x
		var zero: float = (await _travel(false, ALMOST_ZERO, pushes)).x
		print("TABLE air    %-38s design %.2f | full %.3f | at 0 %.3f (sideways travel until it stops, floor far below)" % [case[0], case[2], full, zero])
		_check(full > ground and zero > full, "air, %s: carries further than on the ground, and further still at 0 health" % case[0])

# A scripted run. hits is [[offset, push], ...]: a hit with offset k lands after k ticks have run
# (0 is before the first tick) and all hits with one offset land in the same tick. The stick is held
# throughout and the bot starts with a sideways speed of start_vx bh/s. Returns the sideways travel
# when the run ends, the furthest sideways travel and the highest rise, all in bot heights.
func _scripted(grounded: bool, health: float, hits: Array, stick: Vector2 = Vector2.ZERO, start_vx: float = 0.0) -> Dictionary:
	var bot: Bot = await _spawn(grounded)
	bot.vitals.health = health
	bot.velocity.x = start_vx * _px
	bot.input.move = stick
	var start: Vector2 = bot.position
	var last: int = 0
	for entry: Array in hits:
		last = maxi(last, entry[0] as int)
	var furthest: float = 0.0
	var rise: float = 0.0
	for k: int in last + RUN_TICKS + 1:
		var now: Array[Hit] = []
		for entry: Array in hits:
			if (entry[0] as int) == k:
				now.append(_push_hit(bot, entry[1] as Vector2))
		if not now.is_empty():
			_apply(bot, now)
		_run_ticks(bot, 1)
		furthest = maxf(furthest, bot.position.x - start.x)
		rise = maxf(rise, start.y - bot.position.y)
	var result: Dictionary = {"dx": (bot.position.x - start.x) / _px, "max_dx": furthest / _px, "rise": rise / _px}
	await _free_bots()
	return result

# Several hits in one tick: the distance vectors add, then the sum is converted.
func _test_summed_pushes() -> void:
	var same: float = (await _travel(true, _cfg.max_health, [Vector2.RIGHT * _cfg.melee_push, Vector2.RIGHT * 1.5] as Array[Vector2])).x
	_within(same, _cfg.melee_push + 1.5, "two pushes the same way in one tick move the bot the sum of their distances")
	var opposed: float = (await _travel(true, _cfg.max_health, [Vector2.RIGHT * _cfg.melee_push, Vector2.LEFT * 1.0] as Array[Vector2])).x
	_within(opposed, _cfg.melee_push - 1.0, "pushes in opposite directions in one tick move the bot the difference of their distances")
	var cancelled: float = (await _travel(true, _cfg.max_health, [Vector2.RIGHT * 2.0, Vector2.LEFT * 2.0] as Array[Vector2])).x
	_check(absf(cancelled) < 0.01, "equal opposite pushes in one tick leave the bot where it was")
	var low: float = (await _travel(true, ALMOST_ZERO, [Vector2.RIGHT * _cfg.melee_push, Vector2.RIGHT * 1.5] as Array[Vector2])).x
	_within(low, 2.0 * (_cfg.melee_push + 1.5), "a summed push at 0 health is doubled once, as a sum")

# Recoil is a push on the shooter under the same rule, whatever the shooter's health.
func _test_recoil() -> void:
	var recoil: float = _cfg.weapon_stats(ItemIds.SCRAP_BLASTER).recoil
	var ground: float = (await _recoil_travel(true, Vector2.LEFT, _cfg.max_health)).x
	_within(ground, recoil, "ground: the scrap blaster's recoil moves the shooter its design distance, opposite the shot")
	var weak: float = (await _recoil_travel(true, Vector2.LEFT, ALMOST_ZERO)).x
	_within(weak, recoil, "ground: recoil is not multiplied by the shooter's low health")
	# Recoil from shots on separate ticks adds up like any push: a full magazine moves the shooter
	# ammo x recoil, not more.
	var scrap: WeaponStats = _cfg.weapon_stats(ItemIds.SCRAP_BLASTER)
	var shooter: Bot = await _spawn(true)
	shooter.arsenal.give_weapon(ItemIds.SCRAP_BLASTER, _cfg)
	shooter.input.aim = Vector2.LEFT
	shooter.input.fire = true
	var start: float = shooter.position.x
	_run_ticks(shooter, scrap.ammo * roundi(scrap.fire_interval * float(_cfg.tick_rate)) + RUN_TICKS)
	var magazine: float = (shooter.position.x - start) / _px
	print("TABLE %d scrap shots in a row, shooter's travel (design %.1f): %.3f" % [scrap.ammo, float(scrap.ammo) * recoil, magazine])
	_check(shooter.arsenal.picked_weapon == ItemIds.NONE, "the shooter used up the whole magazine")
	_within(magazine, float(scrap.ammo) * recoil, "ground: a magazine of scrap blaster shots moves the shooter ammo x recoil")
	await _free_bots()
	# A shooter's own speed counts as distance still to travel, as for any push: one shot to the
	# right at a bot running right (further) and running left (less far). The window is held open
	# so the braking is the window's all the way; one tick of it passes before the shot.
	var decel: float = _cfg.ground_brake * _cfg.push_window_control
	for direction: float in [1.0, -1.0]:
		var runner: Bot = await _spawn(true)
		runner.arsenal.give_weapon(ItemIds.SCRAP_BLASTER, _cfg)
		runner.vitals.push_until_tick = _tick + 1000
		runner.velocity.x = direction * _cfg.run_speed * _px
		runner.input.aim = Vector2.LEFT
		runner.input.fire = true
		_run_ticks(runner, 1)
		runner.input.fire = false
		var from_x: float = runner.position.x
		_run_ticks(runner, RUN_TICKS)
		var moved: float = (runner.position.x - from_x) / _px
		var carried: float = CombatMath.travel_distance(_cfg.run_speed - decel * _dt, decel, _dt)
		print("TABLE one scrap shot (recoil %.1f to the right) at a bot running %s at %.0f bh/s: travel %.3f" % [recoil, "right" if direction > 0.0 else "left", _cfg.run_speed, moved])
		_within(moved, direction * carried + recoil, "a shot's recoil adds to the shooter's own run: %s" % ("along it" if direction > 0.0 else "against it"))
		await _free_bots()
	var air: float = (await _recoil_travel(false, Vector2.LEFT, _cfg.max_health)).x
	print("TABLE recoil: design %.2f | ground %.3f | air %.3f" % [recoil, ground, air])
	_check(air > ground, "air: recoil carries further than on the ground")
	var hop_ground: float = (await _recoil_travel(true, Vector2.DOWN, _cfg.max_health)).y
	var hop_air: float = (await _recoil_travel(false, Vector2.DOWN, _cfg.max_health)).y
	print("TABLE hop firing down: ground %.3f bh, air %.3f bh (the air bot had already fallen one tick when it fired)" % [hop_ground, hop_air])
	_within(hop_ground, recoil, "ground: firing straight down hops the shooter its recoil distance")
	_check(hop_air > 0.7 * recoil and hop_air <= recoil + 0.05, "air: firing straight down hops the shooter about its recoil distance (a little less, it was already falling)")

# Up and down: gravity acts, so the same speed-for-distance rule gives the rise of a straight-up
# push and the mirrored speed for a straight-down push.
func _test_vertical() -> void:
	var up_ground: float = (await _travel(true, _cfg.max_health, [Vector2.UP * _cfg.melee_push] as Array[Vector2])).y
	var up_air: float = (await _travel(false, _cfg.max_health, [Vector2.UP * _cfg.melee_push] as Array[Vector2])).y
	_within(up_ground, _cfg.melee_push, "a straight-up push of 2.5 lifts a bot standing on the ground 2.5 bot heights")
	_within(up_air, _cfg.melee_push, "a straight-up push of 2.5 lifts a bot in the air 2.5 bot heights")
	var bot: Bot = await _spawn(false)
	_apply(bot, [_push_hit(bot, Vector2.DOWN * _cfg.melee_push)] as Array[Hit])
	var down_speed: float = bot.velocity.y / _px
	var control: Bot = await _spawn(false)
	_run_ticks(bot, 15)
	_run_ticks(control, 15)
	var extra_fall: float = (bot.position.y - control.position.y) / _px
	print("TABLE straight down 2.5 in the air: speed %.2f bh/s, %.2f bh further down than a bot that was not pushed after half a second" % [down_speed, extra_fall])
	var up_speed: float = CombatRules.push_change(Vector2.ZERO, Vector2.UP * _cfg.melee_push, _cfg).y
	_check(absf(down_speed + up_speed) < 0.001, "a straight-down push has the speed that the same straight-up push has, mirrored")
	_check(extra_fall > 1.0, "a straight-down push makes a falling bot fall further than one that was not pushed")
	await _free_bots()

# A push that lands on a dashing bot ends the dash and adds to the dash-exit speed.
func _test_push_during_dash() -> void:
	for direction: Vector2 in [Vector2.RIGHT, Vector2.LEFT]:
		var bot: Bot = await _spawn(true)
		bot.input.move = Vector2.RIGHT
		bot.input.dash = true
		_run_ticks(bot, 1)
		bot.input.dash = false
		bot.input.move = Vector2.ZERO
		_check(bot.dash_left > 0.0, "the bot is dashing when the push lands")
		_apply(bot, [_push_hit(bot, direction * _cfg.melee_push)] as Array[Hit])
		var want: Vector2 = Vector2(_cfg.dash_exit_speed * _px, 0.0) + CombatRules.push_change(Vector2(_cfg.dash_exit_speed, 0.0), direction * _cfg.melee_push, _cfg) * _px
		_check(bot.dash_left == 0.0 and bot.velocity.distance_to(want) < 0.01, "a push %s on a dashing bot ends the dash and leaves the dash-exit speed plus the push (vx %.1f, want %.1f)" % [direction, bot.velocity.x, want.x])
		if direction == Vector2.RIGHT:
			var start: float = bot.position.x
			_run_ticks(bot, 5)
			_check(bot.position.x - start > _px, "a push along the dash carries the bot on in the next ticks, the dash does not overwrite it")
		await _free_bots()

# The window lasts until the push is braked away: the bot has stopped before the window closes,
# and the window is not longer than needed by more than the tick of rounding.
func _test_window() -> void:
	var bot: Bot = await _spawn(true)
	_apply(bot, [_push_hit(bot, Vector2.RIGHT * _cfg.melee_push)] as Array[Hit])
	var until: int = bot.vitals.push_until_tick
	var moving_at_close: bool = false
	var stopped_at: int = -1
	while _tick < until + 5:
		_run_ticks(bot, 1)
		if stopped_at < 0 and bot.velocity.x == 0.0:
			stopped_at = _tick
	moving_at_close = stopped_at < 0 or stopped_at > until
	_check(not moving_at_close and until - stopped_at <= 1, "the push window closes within a tick of the push being braked away (stopped at tick %d, window until %d)" % [stopped_at, until])
	await _free_bots()

func _test_opposing_push_window() -> void:
	var hit_bot: Bot = await _spawn(true)
	_apply(hit_bot, [_push_hit(hit_bot, Vector2.RIGHT * _cfg.melee_push)] as Array[Hit])
	var original_end: int = hit_bot.vitals.push_until_tick
	_run_ticks(hit_bot, 1)
	_apply(hit_bot, [_push_hit(hit_bot, Vector2.LEFT * _cfg.melee_push)] as Array[Hit])
	var needed_end: int = _tick + CombatRules.push_window_ticks(hit_bot.velocity.x / _px, _cfg)
	_check(needed_end < original_end and hit_bot.vitals.push_until_tick == needed_end, "an opposing hit shortens the push window to match the remaining sideways speed (end %d, need %d)" % [hit_bot.vitals.push_until_tick, needed_end])

	var shooter: Bot = await _spawn(true)
	_apply(shooter, [_push_hit(shooter, Vector2.RIGHT * _cfg.melee_push)] as Array[Hit])
	original_end = shooter.vitals.push_until_tick
	shooter.arsenal.give_weapon(ItemIds.SCRAP_BLASTER, _cfg)
	shooter.input.aim = Vector2.RIGHT
	shooter.input.fire = true
	_run_ticks(shooter, 1)
	needed_end = _tick + CombatRules.push_window_ticks(shooter.velocity.x / _px, _cfg)
	_check(needed_end < original_end and shooter.vitals.push_until_tick == needed_end, "opposing recoil shortens the push window too (end %d, need %d)" % [shooter.vitals.push_until_tick, needed_end])
	await _free_bots()

# ---- pushes on separate ticks, and the bot's own speed ----

# travel_distance is the inverse of launch_speed, both ways, with the config's own braking and tick.
func _test_inverse() -> void:
	var decel: float = _cfg.ground_brake * _cfg.push_window_control
	var exact: bool = true
	for distance: float in [0.05, 0.1, 0.5, 1.0, 2.5, 5.0, 12.0]:
		exact = exact and absf(CombatMath.travel_distance(CombatMath.launch_speed(distance, decel, _dt), decel, _dt) - distance) < 0.000001
	_check(exact, "travel_distance(launch_speed(d)) is d")
	exact = true
	for speed: float in [decel * _dt * 1.5, 1.0, 3.0, 6.0, 10.0, 14.0]:
		exact = exact and absf(CombatMath.launch_speed(CombatMath.travel_distance(speed, decel, _dt), decel, _dt) - speed) < 0.000001
	_check(exact, "launch_speed(travel_distance(v)) is v for v above one tick of braking")
	_check(CombatMath.travel_distance(0.0, decel, _dt) == 0.0 and CombatMath.travel_distance(decel * _dt * 0.5, decel, _dt) == 0.0 and CombatMath.travel_distance(-3.0, decel, _dt) == 0.0, "no distance at or below one tick of braking, and none for a speed that is not positive")

# travel_distance is what the real movement code carries a bot, with the window open and a neutral stick.
func _test_travel_distance_in_play() -> void:
	var decel: float = _cfg.ground_brake * _cfg.push_window_control
	for speed: float in [3.0, 6.0, 10.0]:
		var bot: Bot = await _spawn(true)
		bot.velocity.x = speed * _px
		bot.vitals.push_until_tick = _tick + 1000
		var start: float = bot.position.x
		_run_ticks(bot, 120)
		var real: float = (bot.position.x - start) / _px
		var want: float = CombatMath.travel_distance(speed, decel, _dt)
		_check(absf(real - want) <= 0.01, "a bot at %.0f bh/s in the push window slides what travel_distance says (real %.4f bh, formula %.4f bh)" % [speed, real, want])
		await _free_bots()

# Distances add across ticks exactly as they add within one tick.
func _test_accumulation() -> void:
	var bolt: WeaponStats = _cfg.weapon_stats(ItemIds.BOLT_THROWER)
	var gap: int = roundi(bolt.fire_interval * float(_cfg.tick_rate))
	var burst: Array = []
	for i: int in 30:
		burst.append([i * gap, Vector2.RIGHT * bolt.push])
	var full: Dictionary = await _scripted(true, _cfg.max_health, burst)
	var zero: Dictionary = await _scripted(true, ALMOST_ZERO, burst)
	var air: Dictionary = await _scripted(false, _cfg.max_health, burst)
	print("TABLE 30 bolts every %d ticks (design sum 3.0): ground full %.3f | ground 0 hp %.3f | air full %.3f (until the bot stops, floor far below)" % [gap, full["dx"], zero["dx"], air["dx"]])
	_within(full["dx"] as float, 30.0 * bolt.push, "30 bolts one every %d ticks move a grounded bot the sum of their distances" % gap)
	_within(zero["dx"] as float, 60.0 * bolt.push, "the same 30 bolts at 0 health move it twice as far")
	var melee: float = _cfg.melee_push
	var twice: Dictionary = await _scripted(true, _cfg.max_health, [[0, Vector2.RIGHT * melee], [8, Vector2.RIGHT * melee]])
	var twice_air: Dictionary = await _scripted(false, _cfg.max_health, [[0, Vector2.RIGHT * melee], [8, Vector2.RIGHT * melee]])
	print("TABLE two melee hits 8 ticks apart (design 5.0): ground %.3f | air %.3f" % [twice["dx"], twice_air["dx"]])
	_within(twice["dx"] as float, 2.0 * melee, "two melee hits 8 ticks apart move a grounded bot 5.0")
	var against: Dictionary = await _scripted(true, _cfg.max_health, [[0, Vector2.RIGHT * melee], [4, Vector2.LEFT * 1.0]])
	print("TABLE melee, then a push of 1.0 back 4 ticks later (design 1.5): ground %.3f" % against["dx"])
	_within(against["dx"] as float, melee - 1.0, "a push against the motion of an earlier push takes its distance off: 2.5 then 1.0 back leaves 1.5")
	# The bot's own speed counts as distance still to travel.
	var run: float = _cfg.run_speed
	var carried: float = CombatMath.travel_distance(run, _cfg.ground_brake * _cfg.push_window_control, _dt)
	var into: Dictionary = await _scripted(true, _cfg.max_health, [[0, Vector2.LEFT * melee]], Vector2.ZERO, run)
	var along: Dictionary = await _scripted(true, _cfg.max_health, [[0, Vector2.RIGHT * melee]], Vector2.ZERO, run)
	print("TABLE melee on a bot running at %.0f bh/s (own speed carries %.3f bh): against %.3f | along %.3f" % [run, carried, into["dx"], along["dx"]])
	_within(-(into["dx"] as float), melee - carried, "a bot running into a push of 2.5 is slowed: it ends %.2f bh the other way" % (melee - carried))
	_within(along["dx"] as float, melee + carried, "a bot running away from a push of 2.5 goes further than 2.5")
	_check((along["dx"] as float) > melee + 0.5 and -(into["dx"] as float) < melee - 0.5, "running into a push shortens it and running away lengthens it")
	# The same to the left: the sign of the bot's own speed is carried through.
	var into_left: Dictionary = await _scripted(true, _cfg.max_health, [[0, Vector2.RIGHT * melee]], Vector2.ZERO, -run)
	var along_left: Dictionary = await _scripted(true, _cfg.max_health, [[0, Vector2.LEFT * melee]], Vector2.ZERO, -run)
	print("TABLE melee on a bot running left at %.0f bh/s: against %.3f | along %.3f" % [run, into_left["dx"], along_left["dx"]])
	_within(into_left["dx"] as float, melee - carried, "a bot running left into a push of 2.5 is slowed the same way")
	_within(-(along_left["dx"] as float), melee + carried, "a bot running left away from a push of 2.5 goes further than 2.5")

# On the ground, a stick held against a push never carries the bot further than a released stick.
func _test_stick() -> void:
	var push: Array = [[0, Vector2.RIGHT * _cfg.melee_push]]
	var against: Dictionary = await _scripted(true, _cfg.max_health, push, Vector2.LEFT)
	var neutral: Dictionary = await _scripted(true, _cfg.max_health, push, Vector2.ZERO)
	var along: Dictionary = await _scripted(true, _cfg.max_health, push, Vector2.RIGHT)
	print("TABLE melee 2.5 on the ground, furthest travel: stick against %.3f | neutral %.3f | along %.3f" % [against["max_dx"], neutral["max_dx"], along["max_dx"]])
	_check((against["max_dx"] as float) <= (neutral["max_dx"] as float) + 0.01, "a stick held against a push does not carry the bot further than a neutral stick")
	_within(neutral["max_dx"] as float, _cfg.melee_push, "neutral stick: the push moves the bot its distance")
	_check((along["max_dx"] as float) > (neutral["max_dx"] as float), "a stick held along the push carries the bot further")

# Only sideways speed needs the window: a push or launch with no sideways part opens none, and a
# push with one opens exactly the window its sideways speed needs.
func _test_window_sideways() -> void:
	var brake: float = _cfg.ground_brake * _cfg.push_window_control * _dt
	var up: Bot = await _spawn(true)
	_apply(up, [_push_hit(up, Vector2.UP * _cfg.melee_push)] as Array[Hit])
	_check(up.vitals.push_until_tick == 0, "a push straight up opens no push window")
	var plate: Bot = await _spawn(true)
	var launch: Hit = _push_hit(plate, Vector2(0.0, -_cfg.plate_launch_speed))
	launch.launch = true
	launch.scale_push = false
	_apply(plate, [launch] as Array[Hit])
	_check(plate.vitals.push_until_tick == 0, "a Spring Plate launch with no sideways part opens no push window")
	var runner: Bot = await _spawn(true)
	runner.velocity.x = _cfg.run_speed * _px
	var launch_runner: Hit = _push_hit(runner, Vector2(0.0, -_cfg.plate_launch_speed))
	launch_runner.launch = true
	launch_runner.scale_push = false
	_apply(runner, [launch_runner] as Array[Hit])
	_check(runner.vitals.push_until_tick == 0 and runner.velocity.x == _cfg.run_speed * _px, "a plate under a running bot opens no window and leaves its run alone")
	var diagonal: Bot = await _spawn(true)
	_apply(diagonal, [_push_hit(diagonal, Vector2(1.0, -1.0).normalized() * _cfg.melee_push)] as Array[Hit])
	var ticks: int = diagonal.vitals.push_until_tick - (_tick - 1) - 1
	var sideways: float = absf(diagonal.velocity.x) / _px
	_check(float(ticks) * brake >= sideways - 0.0001 and float(ticks - 1) * brake < sideways, "a 45 degree push opens exactly the window its sideways speed needs (%d ticks for %.2f bh/s)" % [ticks, sideways])
	await _free_bots()

# A push at 45 degrees lifts the bot, so its sideways travel follows the air figures.
func _test_diagonal() -> void:
	var push: Vector2 = Vector2(1.0, -1.0).normalized() * _cfg.melee_push
	var ground: Vector2 = await _travel(true, _cfg.max_health, [push] as Array[Vector2])
	var air: Vector2 = await _travel(false, _cfg.max_health, [push] as Array[Vector2])
	var flat: float = (await _travel(true, _cfg.max_health, [Vector2.RIGHT * push.x] as Array[Vector2])).x
	print("TABLE push of %.1f at 45 degrees (%.3f sideways, %.3f up): ground sideways %.3f, rise %.3f | air sideways %.3f, rise %.3f | the same sideways part alone on the ground %.3f" % [_cfg.melee_push, push.x, -push.y, ground.x, ground.y, air.x, air.y, flat])
	_check(ground.x > 2.0 * flat, "a 45 degree push on the ground carries sideways like the air figure, far past the flat distance of its sideways part")
	_within(ground.y, -push.y, "a 45 degree push lifts the bot the vertical part of its distance")
