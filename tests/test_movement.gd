extends Node
## Headless movement test. Drives the real Bot scene and the real tuning config
## one network tick at a time, with no network. Run:
##   godot --headless --path . res://tests/test_movement.tscn
## Exits 0 when every check passes, 1 otherwise.

const BOT_SCENE: PackedScene = preload("res://scenes/bot.tscn")
const AIR_Y: float = -50000.0
const WORLD_SIZE: float = 200000.0
const EPS: float = 0.001
const TIMEOUT_SECONDS: float = 60.0

var _cfg: TuningConfig = TuningConfig.get_default()
var _dt: float = 0.0
var _px: float = 0.0
var _failures: int = 0
var _checks: int = 0
var _nodes: Array[Node] = []
var _tick: int = 0

func _ready() -> void:
	get_tree().create_timer(TIMEOUT_SECONDS).timeout.connect(_on_timeout)
	_run()

# A script error inside a coroutine stops it silently; without this the run
# would hang instead of failing.
func _on_timeout() -> void:
	print("FAIL timeout, the test did not finish")
	get_tree().quit(1)

func _run() -> void:
	_dt = 1.0 / float(_cfg.tick_rate)
	_px = _cfg.bot_height_px
	_test_config()
	await _test_run_speed()
	await _test_climb_and_tap()
	await _test_fall_cap()
	await _test_dash()
	await _test_dash_cooldown_and_buffer()
	await _test_fuel_burn()
	await _test_fuel_refill()
	await _test_no_air_refill()
	await _test_wall()
	await _test_wall_jump_needs_slide()
	await _test_wall_climb_gains_nothing()
	await _test_proportional_run()
	await _test_wrong_input_types()
	await _test_aim_direction()
	await _test_thin_platform()
	await _test_input_sanitising()
	print("%d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)

# ---- checks ----

func _check(ok: bool, label: String) -> void:
	_checks += 1
	if ok:
		print("PASS ", label)
	else:
		_failures += 1
		print("FAIL ", label)

func _near(got: float, want: float, tol: float, label: String) -> void:
	_check(absf(got - want) <= tol, "%s (got %.4f, want %.4f +-%.4f)" % [label, got, want, tol])

# ---- world and bot helpers ----

func _clear() -> void:
	for node: Node in _nodes:
		node.free()
	_nodes.clear()
	await get_tree().physics_frame
	await get_tree().physics_frame

func _add_static(rect: Rect2, thin: bool) -> void:
	var body: StaticBody2D = StaticBody2D.new()
	body.position = rect.get_center()
	body.collision_layer = Bot.LAYER_THIN if thin else Bot.LAYER_SOLID
	body.collision_mask = 0
	var shape_node: CollisionShape2D = CollisionShape2D.new()
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = rect.size
	shape_node.shape = shape
	shape_node.one_way_collision = thin
	body.add_child(shape_node)
	add_child(body)
	_nodes.append(body)

# A floor with its top at y = 0.
func _add_floor() -> void:
	_add_static(Rect2(-WORLD_SIZE / 2.0, 0.0, WORLD_SIZE, 100.0), false)

# A wall with its right face at x = 0, tall enough for the air tests.
func _add_left_wall() -> void:
	_add_static(Rect2(-100.0, -WORLD_SIZE, 100.0, WORLD_SIZE * 2.0), false)

func _spawn_bot(pos: Vector2) -> Bot:
	var bot: Bot = BOT_SCENE.instantiate() as Bot
	bot.position = pos
	add_child(bot)
	_nodes.append(bot)
	await get_tree().physics_frame
	await get_tree().physics_frame
	return bot

# Bot standing just above the floor surface (floor top at y = 0).
func _spawn_on_floor(x: float) -> Bot:
	return await _spawn_bot(Vector2(x, -_px / 2.0 - 0.5))

func _step(bot: Bot, ticks: int = 1) -> void:
	for i: int in ticks:
		bot._rollback_tick(_dt, _tick, true)
		_tick += 1

func _idle_input(bot: Bot) -> void:
	bot.input.move = Vector2.ZERO
	bot.input.aim = Vector2.ZERO
	bot.input.jet = false
	bot.input.dash = false

# ---- tests ----

func _test_config() -> void:
	_near(_cfg.run_speed, 6.0, EPS, "config run speed (GDD 6)")
	_near(_cfg.climb_speed, 7.0, EPS, "config climb speed (GDD 7)")
	_near(_cfg.fall_speed_limit, 12.0, EPS, "config fall limit (GDD 12)")
	_check(_cfg.fall_speed_limit > _cfg.climb_speed, "falling is faster than rising")
	_near(_cfg.thrust_ramp_time, 0.15, EPS, "config thrust ramp (GDD 0.15)")
	_near(_cfg.fuel_capacity, 2.5, EPS, "config fuel (GDD 2.5 s)")
	_near(_cfg.fuel_refill_time, 2.0, EPS, "config refill (GDD 2 s)")
	_near(_cfg.dash_distance, 3.0, EPS, "config dash distance (GDD 3)")
	_near(_cfg.dash_time, 0.15, EPS, "config dash time (GDD 0.15)")
	_near(_cfg.dash_cooldown, 3.0, EPS, "config dash cooldown (GDD 3)")
	_near(_cfg.input_buffer_time, 0.1, EPS, "config input buffer (GDD 0.1)")
	_near(_cfg.wall_jump_grace, 0.1, EPS, "config wall-jump grace (GDD 0.1)")
	_check(_cfg.tick_rate == 30, "config tick rate 30")
	_check(NetworkTime.tickrate == _cfg.tick_rate, "netfox tickrate matches config")
	_check(_cfg.max_players == 4, "config max players 4")

func _test_run_speed() -> void:
	_add_floor()
	var bot: Bot = await _spawn_on_floor(0.0)
	_step(bot, 5)
	bot.input.move = Vector2.RIGHT
	_step(bot, 30)
	_near(bot.velocity.x / _px, _cfg.run_speed, 0.01, "run speed reached (bh/s)")
	var start_x: float = bot.position.x
	_step(bot, 30)
	_near((bot.position.x - start_x) / _px / (30.0 * _dt), _cfg.run_speed, 0.01, "run speed measured over 1 s (bh/s)")
	await _clear()

func _test_climb_and_tap() -> void:
	_add_floor()
	var bot: Bot = await _spawn_on_floor(0.0)
	_step(bot, 5)
	bot.input.jet = true
	_step(bot, 1)
	_check(bot.thrust_level > 0.0 and bot.thrust_level < 1.0, "thrust ramps, not instant (level %.3f after 1 tick)" % bot.thrust_level)
	var fastest: float = 0.0
	for i: int in 40:
		_step(bot)
		fastest = maxf(fastest, -bot.velocity.y)
	_near(fastest / _px, _cfg.climb_speed, 0.01, "climb speed at full thrust (bh/s)")
	await _clear()

	_add_floor()
	var tapper: Bot = await _spawn_on_floor(0.0)
	_step(tapper, 5)
	var floor_y: float = tapper.position.y
	var highest: float = floor_y
	tapper.input.jet = true
	_step(tapper, 3)
	tapper.input.jet = false
	for i: int in 60:
		_step(tapper)
		highest = minf(highest, tapper.position.y)
	var hop: float = floor_y - highest
	_check(hop > 1.0 and hop < _px, "3-tick tap gives a small hop (%.2f px, under one bot height)" % hop)
	await _clear()

	# Even one tick of thrust lifts the bot off the floor.
	_add_floor()
	var quick_tapper: Bot = await _spawn_on_floor(0.0)
	_step(quick_tapper, 5)
	var start_y: float = quick_tapper.position.y
	var quick_peak: float = start_y
	quick_tapper.input.jet = true
	_step(quick_tapper)
	quick_tapper.input.jet = false
	_check(quick_tapper.position.y < start_y - EPS, "1-tick jetpack tap lifts off the floor")
	for i: int in 60:
		_step(quick_tapper)
		quick_peak = minf(quick_peak, quick_tapper.position.y)
	var quick_hop: float = start_y - quick_peak
	_check(quick_hop > EPS and quick_hop < hop, "1-tick tap hop %.2f px is smaller than the 3-tick hop %.2f px" % [quick_hop, hop])
	await _clear()

func _test_fall_cap() -> void:
	var bot: Bot = await _spawn_bot(Vector2(0.0, AIR_Y))
	var fastest: float = 0.0
	for i: int in 150:
		_step(bot)
		fastest = maxf(fastest, bot.velocity.y)
	_near(fastest / _px, _cfg.fall_speed_limit, 0.01, "fall speed cap (bh/s)")
	await _clear()

func _test_dash() -> void:
	var bot: Bot = await _spawn_bot(Vector2(0.0, AIR_Y))
	bot.input.move = Vector2.RIGHT
	bot.input.dash = true
	var start: Vector2 = bot.position
	_step(bot)
	bot.input.dash = false
	var ticks: int = 1
	while bot.dash_left > 0.0 and ticks < 100:
		_step(bot)
		ticks += 1
	_check(ticks == int(ceil(_cfg.dash_time / _dt)), "dash lasts 0.15 s (%d ticks at %d tps)" % [ticks, _cfg.tick_rate])
	_near((bot.position.x - start.x) / _px, _cfg.dash_distance, 0.01, "dash distance mid-air (bh)")
	_near(bot.position.y - start.y, 0.0, 0.5, "no gravity during dash (px drift)")
	_near(bot.velocity.length() / _px, _cfg.dash_exit_speed, 0.01, "momentum resumes at exit speed (bh/s)")
	await _clear()

	# Neutral stick dashes in the facing direction.
	var left: Bot = await _spawn_bot(Vector2(0.0, AIR_Y))
	left.facing = -1
	left.input.dash = true
	var left_start: float = left.position.x
	_step(left, int(ceil(_cfg.dash_time / _dt)))
	_check(left.position.x < left_start, "neutral-stick dash goes the facing way")
	await _clear()

func _test_dash_cooldown_and_buffer() -> void:
	# A dash pressed every tick starts again exactly when the cooldown ends.
	var bot: Bot = await _spawn_bot(Vector2(0.0, AIR_Y))
	bot.input.move = Vector2.RIGHT
	bot.input.dash = true
	_step(bot)
	var restart: int = -1
	for i: int in 200:
		var was_dashing: bool = bot.dash_left > 0.0
		_step(bot)
		if bot.dash_left > 0.0 and not was_dashing:
			restart = i + 1
			break
	var seconds: float = float(restart) * _dt
	_check(restart > 0 and absf(seconds - _cfg.dash_cooldown) <= _dt + EPS, "dash cooldown %.3f s (want 3 s, one tick tolerance)" % seconds)
	await _clear()

	# One press 0.067 s before the cooldown ends is buffered and fires.
	var early: Bot = await _spawn_bot(Vector2(0.0, AIR_Y))
	early.input.move = Vector2.RIGHT
	early.input.dash = true
	_step(early)
	early.input.dash = false
	_step(early, 87)
	early.input.dash = true
	_step(early)
	early.input.dash = false
	var fired: bool = false
	for i: int in 5:
		_step(early)
		fired = fired or early.dash_left > 0.0
	_check(fired, "dash pressed 0.07 s early still counts")
	await _clear()

	# One press 0.17 s before the cooldown ends is too early.
	var too_early: Bot = await _spawn_bot(Vector2(0.0, AIR_Y))
	too_early.input.move = Vector2.RIGHT
	too_early.input.dash = true
	_step(too_early)
	too_early.input.dash = false
	_step(too_early, 84)
	too_early.input.dash = true
	_step(too_early)
	too_early.input.dash = false
	var fired_late: bool = false
	for i: int in 20:
		_step(too_early)
		fired_late = fired_late or too_early.dash_left > 0.0
	_check(not fired_late, "dash pressed 0.17 s early does not count")
	await _clear()

func _test_fuel_burn() -> void:
	_add_floor()
	var bot: Bot = await _spawn_on_floor(0.0)
	_step(bot, 5)
	_near(bot.fuel, _cfg.fuel_capacity, EPS, "fuel starts full")
	bot.input.jet = true
	var ticks: int = 0
	while bot.fuel > EPS and ticks < 500:
		_step(bot)
		ticks += 1
	_near(float(ticks) * _dt, _cfg.fuel_capacity, _dt + EPS, "fuel burns out after 2.5 s of thrust (s)")
	await _clear()

func _test_fuel_refill() -> void:
	_add_floor()
	var bot: Bot = await _spawn_on_floor(0.0)
	_step(bot, 5)
	bot.fuel = 0.0
	var ticks: int = 0
	while bot.fuel < _cfg.fuel_capacity - EPS and ticks < 500:
		_step(bot)
		ticks += 1
	_near(float(ticks) * _dt, _cfg.fuel_refill_time, _dt + EPS, "fuel refills fully in 2 s on the ground (s)")
	await _clear()

func _test_no_air_refill() -> void:
	var bot: Bot = await _spawn_bot(Vector2(0.0, AIR_Y))
	bot.fuel = 1.0
	_step(bot, 60)
	_near(bot.fuel, 1.0, EPS, "fuel does not refill in the air")
	await _clear()

func _test_wall() -> void:
	_add_left_wall()
	var half_width: float = _cfg.bot_width_bh * _px / 2.0
	# Sliding: pushing into the wall caps the fall.
	var bot: Bot = await _spawn_bot(Vector2(half_width + 0.1, AIR_Y))
	bot.input.move = Vector2.LEFT
	var fastest: float = 0.0
	for i: int in 90:
		_step(bot)
		fastest = maxf(fastest, bot.velocity.y)
	_near(fastest / _px, _cfg.wall_slide_speed, 0.01, "wall-slide fall speed (bh/s)")
	# Wall-jump: push away while sliding.
	bot.input.move = Vector2.RIGHT
	_step(bot)
	_near(bot.velocity.x / _px, _cfg.wall_jump_speed_x - _cfg.air_accel * _dt, 0.01, "wall-jump horizontal speed after one tick (bh/s)")
	_near(bot.velocity.y / _px, -(_cfg.wall_jump_speed_y - _cfg.gravity * _dt), 0.01, "wall-jump vertical speed (bh/s)")
	await _clear()

	# Grace: still allowed just after the wall was left, not long after.
	_add_left_wall()
	var grace: Bot = await _spawn_bot(Vector2(half_width + 0.1, AIR_Y))
	grace.input.move = Vector2.LEFT
	_step(grace, 3)
	grace.position.x += 20.0
	grace.velocity = Vector2.ZERO
	grace.input.move = Vector2.RIGHT
	_step(grace)
	_check(grace.velocity.y < -_px * (_cfg.climb_speed), "wall-jump still works just after leaving the wall")
	await _clear()

	_add_left_wall()
	var late: Bot = await _spawn_bot(Vector2(half_width + 0.1, AIR_Y))
	late.input.move = Vector2.LEFT
	_step(late, 3)
	late.position.x += 20.0
	late.velocity = Vector2.ZERO
	late.input.move = Vector2.ZERO
	_step(late, 6)
	late.input.move = Vector2.RIGHT
	_step(late)
	_check(late.velocity.y > 0.0, "wall-jump no longer works 0.2 s after leaving the wall")
	await _clear()

func _test_thin_platform() -> void:
	_add_floor()
	var platform_top: float = -300.0
	_add_static(Rect2(-500.0, platform_top, 1000.0, 16.0), true)
	# Falls from above and lands on it.
	var bot: Bot = await _spawn_bot(Vector2(0.0, platform_top - 400.0))
	_step(bot, 90)
	_near(bot.position.y, platform_top - _px / 2.0, 1.0, "lands on a thin platform from above")
	# Stick down drops through to the floor.
	bot.input.move = Vector2.DOWN
	_step(bot, 90)
	_near(bot.position.y, -_px / 2.0, 1.0, "stick down drops through a thin platform")
	# Jetpack passes up through it from below.
	bot.input.move = Vector2.ZERO
	bot.input.jet = true
	_step(bot, 20)
	bot.input.jet = false
	_step(bot, 90)
	_near(bot.position.y, platform_top - _px / 2.0, 1.0, "jetpack goes up through a thin platform and lands on top")
	await _clear()

func _test_input_sanitising() -> void:
	_add_floor()
	var bot: Bot = await _spawn_on_floor(0.0)
	_step(bot, 5)
	bot.input.move = Vector2(NAN, 1.0)
	bot.input.aim = Vector2(INF, 0.0)
	_step(bot, 5)
	_check(is_finite(bot.position.x) and is_finite(bot.position.y), "NaN input leaves position finite")
	_near(bot.velocity.x, 0.0, EPS, "NaN move ignored")
	_check(bot.aim_dir.is_finite(), "non-finite aim ignored")
	bot.input.move = Vector2(1.0e9, 0.0)
	_step(bot, 40)
	_near(bot.velocity.x / _px, _cfg.run_speed, 0.01, "huge move vector clamped to run speed (bh/s)")
	await _clear()

func _test_wall_jump_needs_slide() -> void:
	_add_left_wall()
	var half_width: float = _cfg.bot_width_bh * _px / 2.0
	# Resting against the wall in the air, never pushed into it: no wall-jump.
	var bot: Bot = await _spawn_bot(Vector2(half_width + 0.1, AIR_Y))
	bot.input.move = Vector2.RIGHT
	_step(bot)
	_check(bot.velocity.y >= 0.0, "pushing away without sliding first does not wall-jump")
	await _clear()

	# Rising along the wall (jetpack) while pushing into it is not a slide.
	_add_left_wall()
	var riser: Bot = await _spawn_bot(Vector2(half_width + 0.1, AIR_Y))
	riser.input.move = Vector2.LEFT
	riser.input.jet = true
	_step(riser, 10)
	riser.input.jet = false
	riser.input.move = Vector2.RIGHT
	_step(riser)
	_check(riser.velocity.x < _cfg.wall_jump_speed_x * _px * 0.5, "rising along a wall does not open the wall-jump window")
	await _clear()

# Alternating away from and back to one wall with an empty tank must not
# climb: every wall-jump starts no higher than the first.
func _test_wall_climb_gains_nothing() -> void:
	_add_left_wall()
	var half_width: float = _cfg.bot_width_bh * _px / 2.0
	var bot: Bot = await _spawn_bot(Vector2(half_width + 0.1, AIR_Y))
	bot.fuel = 0.0
	var jump_heights: Array[float] = []
	for i: int in 240:
		var touching: bool = bot.position.x - half_width <= 2.0
		if bot.wall_grace_left > 0.0 and touching:
			bot.input.move = Vector2.RIGHT
			jump_heights.append(bot.position.y)
		else:
			bot.input.move = Vector2.LEFT
		_step(bot)
	_check(jump_heights.size() >= 3, "same-wall wall-jumps happened (%d jumps in 8 s)" % jump_heights.size())
	var worst_gain: float = 0.0
	for height: float in jump_heights:
		worst_gain = maxf(worst_gain, jump_heights[0] - height)
	_check(worst_gain <= 1.0, "same-wall wall-jumps with an empty tank do not gain height (worst gain %.1f px)" % worst_gain)
	await _clear()

func _test_proportional_run() -> void:
	_add_floor()
	var bot: Bot = await _spawn_on_floor(0.0)
	_step(bot, 5)
	var half: float = (_cfg.stick_deadzone + 1.0) / 2.0
	bot.input.move = Vector2(half, 0.0)
	_step(bot, 30)
	_near(bot.velocity.x / _px, _cfg.run_speed / 2.0, 0.01, "half stick beyond the dead zone runs at half speed (bh/s)")
	bot.input.move = Vector2(_cfg.stick_deadzone * 0.5, 0.0)
	_step(bot, 30)
	_near(bot.velocity.x, 0.0, EPS, "stick inside the dead zone does not run")
	bot.input.move = Vector2.RIGHT
	_step(bot, 30)
	_near(bot.velocity.x / _px, _cfg.run_speed, 0.01, "full stick runs at full speed (bh/s)")
	await _clear()

# Clients can send any type; every wrong type must act as neutral input.
func _test_wrong_input_types() -> void:
	_add_floor()
	var bot: Bot = await _spawn_on_floor(0.0)
	_step(bot, 5)
	var start: Vector2 = bot.position
	bot.input.move = "right"
	bot.input.aim = 5
	bot.input.jet = Vector2.UP
	bot.input.dash = "yes"
	_step(bot, 30)
	_near(bot.position.distance_to(start), 0.0, 0.5, "wrong-typed input leaves the bot where it was (px)")
	_check(bot.fuel == _cfg.fuel_capacity and bot.dash_left == 0.0, "wrong-typed jet and dash do nothing")
	bot.input.move = Vector2.RIGHT
	bot.input.aim = Vector2.RIGHT
	bot.input.jet = false
	bot.input.dash = false
	_step(bot, 30)
	_check(bot.position.x > start.x + _px, "input works again once it is valid")
	await _clear()

func _test_aim_direction() -> void:
	var bot: Bot = await _spawn_bot(Vector2(0.0, AIR_Y))
	bot.input.aim = Vector2.UP
	_step(bot)
	_check(bot.aim_dir == Vector2.UP, "the aim line follows the held stick")
	bot.input.aim = Vector2.ZERO
	bot.input.move = Vector2.LEFT
	_step(bot)
	_check(bot.aim_dir == Vector2.LEFT, "the aim line follows the new facing on the tick the aim stick is released")
	await _clear()
