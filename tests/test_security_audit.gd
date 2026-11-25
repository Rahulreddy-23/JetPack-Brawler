extends Node
## Regression tests for active geminiceo fixes (G-15, G-17, G-19, G-21a/b, G-22, G-23, G-24)
## against origin/main (0c8e6a4). Every check fails on origin/main without its fix.
## Run:
##   godot --headless --path . res://tests/test_security_audit.tscn
## Exits 0 when every check passes, 1 otherwise.

const BOT_SCENE: PackedScene = preload("res://scenes/bot.tscn")
const LAYOUT: ArenaLayout = preload("res://config/smelter.tres")
const TIMEOUT_SECONDS: float = 30.0
const EPS: float = 0.01

class RocketCapture extends WorldObjects:
	var launched_pos: Vector2 = Vector2.INF
	var launch_count: int = 0

	func launch(_kind: int, _owner_slot: int, _owner_peer: int, pos_px: Vector2, _vel_px: Vector2, _tick: int, _cfg: TuningConfig) -> WorldObject:
		launched_pos = pos_px
		launch_count += 1
		return null

class SizeWarningCounter extends Logger:
	var count: int = 0

	func _log_error(_fn: String, _file: String, _line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING and ("over the limit" in code or "over the limit" in rationale):
			count += 1

var _failures: int = 0
var _checks: int = 0
var _cfg: TuningConfig = TuningConfig.get_default()
var _size_warnings: SizeWarningCounter = SizeWarningCounter.new()

func _ready() -> void:
	OS.add_logger(_size_warnings)
	get_tree().create_timer(TIMEOUT_SECONDS).timeout.connect(_on_timeout)
	_run()

func _on_timeout() -> void:
	print("FAIL timeout, security audit test did not finish")
	get_tree().quit(1)

func _check(ok: bool, label: String) -> void:
	_checks += 1
	if ok:
		print("PASS ", label)
	else:
		_failures += 1
		print("FAIL ", label)

func _run() -> void:
	InputActions.ensure_registered()
	_test_rocket_muzzle_wall_clamp()
	await _test_rocket_hits_bot_before_wall_and_range()
	await _test_gadget_cycle_reset_ordering_and_skipped_tick()
	_test_pickup_reset_after_skipped_cycle_tick()
	_test_pickups_reset_between_sessions()
	_test_touch_flick_updates_aim_without_extra_shot()
	_test_netfox_oversized_packet_warning_rate_limit()
	print("%d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)

func _test_rocket_muzzle_wall_clamp() -> void:
	var px: float = _cfg.bot_height_px
	var solids: Array[Rect2] = LAYOUT.solid_rects_px(px)
	var bot: Bot = BOT_SCENE.instantiate() as Bot
	bot.peer_id = 1
	bot.slot = 0
	add_child(bot)
	var wall_left: float = 11.0 * px
	var half_w: float = _cfg.bot_width_bh * px / 2.0
	bot.global_position = Vector2(wall_left - half_w, 12.0 * px)
	bot.arsenal.give_weapon(ItemIds.ROCKET_TUBE, _cfg)
	bot.arsenal.last_shot_tick = 10
	bot.arsenal.shot_dir = Vector2.RIGHT
	var capture: RocketCapture = RocketCapture.new()
	var hits: Array[Hit] = []
	WeaponRules.collect(10, [bot], capture, solids, _cfg, hits)
	_check(capture.launch_count == 1 and capture.launched_pos.x <= wall_left + EPS,
		"G-15: rocket fired flush against a wall does not spawn inside the wall (x=%.2f, wall=%.2f)" % [capture.launched_pos.x, wall_left])
	bot.free()

func _test_rocket_hits_bot_before_wall_and_range() -> void:
	var dt: float = 1.0 / float(_cfg.tick_rate)
	var px: float = _cfg.bot_height_px
	var radius: float = _cfg.weapon_stats(ItemIds.ROCKET_TUBE).projectile_radius * px
	var pool: WorldObjects = WorldObjects.new()
	add_child(pool)
	pool.solids = [Rect2(-5000.0, 1024.0, 10000.0, 500.0)]
	pool.bounds_px = Rect2(-10000.0, -10000.0, 20000.0, 20000.0)
	await get_tree().process_frame
	var victim: Bot = BOT_SCENE.instantiate() as Bot
	victim.peer_id = 11
	victim.slot = 1
	victim.position = Vector2(140.0, 992.0)
	add_child(victim)
	var speed: float = _cfg.weapon_stats(ItemIds.ROCKET_TUBE).projectile_speed * px
	var vel: Vector2 = Vector2(1.0, 1.0).normalized() * speed
	var rocket: WorldObject = pool.launch(ItemIds.OBJECT_ROCKET, 0, 10, Vector2(100.0, 995.0), vel, 10, _cfg)
	rocket._rollback_tick(dt, 11, true)
	var floor_contact_y: float = 1024.0 - radius
	var hits: Array[Hit] = []
	GadgetRules.collect(11, [victim], pool, pool.solids, _cfg, hits)
	var bot_left_grown: float = victim.body_rect().position.x - radius
	_check(absf(rocket.global_position.x - bot_left_grown) < 0.05 and rocket.global_position.y < floor_contact_y - 1.0,
		"G-21a: rocket hitting a floor behind a bot explodes at earlier bot contact (pos=%s)" % [rocket.global_position])
	victim.free()
	pool.free()

	var pool2: WorldObjects = WorldObjects.new()
	add_child(pool2)
	pool2.bounds_px = Rect2(-10000.0, -10000.0, 20000.0, 20000.0)
	await get_tree().process_frame
	var victim2: Bot = BOT_SCENE.instantiate() as Bot
	victim2.peer_id = 11
	victim2.slot = 1
	victim2.position = Vector2(150.0, 500.0)
	add_child(victim2)
	var r2: WorldObject = pool2.launch(ItemIds.OBJECT_ROCKET, 0, 10, Vector2(100.0, 500.0), Vector2(100.0 * float(_cfg.tick_rate), 0.0), 10, _cfg)
	r2.fuse_tick = 11
	r2._rollback_tick(dt, 11, true)
	var hits2: Array[Hit] = []
	GadgetRules.collect(11, [victim2], pool2, pool2.solids, _cfg, hits2)
	var expected_x: float = victim2.body_rect().position.x - radius
	_check(absf(r2.global_position.x - expected_x) < 0.05,
		"G-21b: rocket at max-range tick explodes at bot contact instead of overshooting (x=%.2f, want=%.2f)" % [r2.global_position.x, expected_x])
	victim2.free()
	pool2.free()

func _test_gadget_cycle_reset_ordering_and_skipped_tick() -> void:
	var dt: float = 1.0 / float(_cfg.tick_rate)
	var cycle: int = roundi(_cfg.hazard_cycle_time * float(_cfg.tick_rate))
	var start: int = 100
	var saved: int = MatchSettings.round_start_tick
	MatchSettings.round_start_tick = start

	var pool: WorldObjects = WorldObjects.new()
	add_child(pool)
	pool.bounds_px = Rect2(-10000.0, -10000.0, 20000.0, 20000.0)
	await get_tree().process_frame
	var bot: Bot = BOT_SCENE.instantiate() as Bot
	bot.peer_id = 10
	bot.slot = 0
	bot.position = Vector2(500.0, 500.0)
	add_child(bot)
	var old_bomb: WorldObject = pool.launch(ItemIds.OBJECT_BOMB, 1, 11, bot.center(), Vector2.ZERO, start + cycle - 90, _cfg)
	old_bomb.landed = true
	var old_plate: WorldObject = pool.launch(ItemIds.OBJECT_PLATE, 1, 11, Vector2(500.0, 522.0), Vector2.ZERO, start + 10, _cfg)
	old_plate.landed = true
	old_plate.arm_tick = start + 25
	bot.input.gadget = true
	bot.input.aim = Vector2.RIGHT
	for slot: WorldObject in pool.slots():
		slot._rollback_tick(dt, start + cycle, true)
	bot.gadgets._rollback_tick(dt, start + cycle, true)
	var hits: Array[Hit] = []
	GadgetRules.collect(start + cycle, [bot], pool, pool.solids, _cfg, hits)
	var new_bomb: WorldObject = pool.slots()[pool.slot_range(ItemIds.OBJECT_BOMB, 0, _cfg).x]
	_check(hits.is_empty() and not old_bomb.active and not old_plate.active,
		"G-22a: cycle-0 bomb and plate do not hit or launch freshly respawned bot on cycle start")
	_check(new_bomb.active and new_bomb.spawn_tick == start + cycle,
		"G-22b: gadget thrown on cycle boundary tick survives cycle reset")

	var skipped_hits: Array[Hit] = []
	GadgetRules.collect(start + 2 * cycle + 4, [bot], pool, pool.solids, _cfg, skipped_hits)
	_check(not new_bomb.active,
		"G-22c: prior-cycle object is cleared even when a stall skips the exact boundary tick")

	MatchSettings.round_start_tick = saved
	bot.free()
	pool.free()

func _test_pickup_reset_after_skipped_cycle_tick() -> void:
	var pickups: Pickups = Pickups.new()
	pickups.layout = LAYOUT
	add_child(pickups)
	var bot: Bot = BOT_SCENE.instantiate() as Bot
	bot.peer_id = 1
	bot.slot = 0
	add_child(bot)
	MatchSettings.round_start_tick = 0
	var cycle: int = roundi(_cfg.hazard_cycle_time * float(_cfg.tick_rate))
	var spot: PickupSpot = pickups.spots()[0]
	bot.global_position = spot.global_position
	pickups.resolve(cycle - 10, [bot], _cfg)
	bot.global_position = Vector2(-5000.0, -5000.0)
	pickups.resolve(cycle + 3, [bot], _cfg)
	_check(spot.ready_tick <= cycle + 3,
		"G-17: pickup resets when boundary tick is skipped (ready_tick=%d, tick=%d)" % [spot.ready_tick, cycle + 3])
	MatchSettings.round_start_tick = -1
	bot.free()
	pickups.free()

func _test_pickups_reset_between_sessions() -> void:
	var pickups: Pickups = Pickups.new()
	pickups.layout = LAYOUT
	add_child(pickups)
	var wired: bool = (NetworkEvents.on_server_start.is_connected(pickups.reset_session)
		and NetworkEvents.on_server_stop.is_connected(pickups.reset_session)
		and NetworkEvents.on_client_start.is_connected(pickups._on_client_start)
		and NetworkEvents.on_client_stop.is_connected(pickups.reset_session))
	for spot: PickupSpot in pickups.spots():
		spot.ready_tick = 5450
	pickups.reset_session()
	var all_zero: bool = true
	for spot: PickupSpot in pickups.spots():
		all_zero = all_zero and spot.ready_tick == 0
	_check(wired and all_zero,
		"G-23: pickups connect all four session signals and reset stale ready_tick values")
	pickups.free()

func _test_touch_flick_updates_aim_without_extra_shot() -> void:
	var touch: TouchControls = TouchControls.new()
	touch.size = Vector2(1280.0, 720.0)
	add_child(touch)
	var origin: Vector2 = Vector2(900.0, 500.0)
	var out_dist: float = _cfg.stick_radius_px * (_cfg.fire_ring_fraction + 0.15)
	var in_dist: float = _cfg.stick_radius_px * (_cfg.fire_ring_fraction - 0.15)
	InputActions.pending_touch_fire_aim = Vector2.ZERO
	# 1. Quick flick: cross ring right, curve up before next tick, lift -> keeps latest aim.
	touch._touch(1, origin, true)
	touch._drag(1, origin + Vector2(out_dist, 0.0))
	touch._drag(1, origin + Vector2(0.0, -out_dist))
	touch._touch(1, origin + Vector2(0.0, -out_dist), false)
	var captured: Vector2 = InputActions.pending_touch_fire_aim
	_check(captured.y < -0.5 and absf(captured.x) < 0.2,
		"G-19a: quick flick curving past the fire ring keeps latest aim direction (got %s)" % [captured])
	# 2. Held fire already sampled on a tick (pending cleared), then dragged past ring and pulled back inside -> no extra pending shot.
	InputActions.pending_touch_fire_aim = Vector2.ZERO
	touch._touch(2, origin, true)
	touch._drag(2, origin + Vector2(out_dist, 0.0))
	InputActions.pending_touch_fire_aim = Vector2.ZERO # BotInput sampled tick 1
	touch._drag(2, origin + Vector2(out_dist, 10.0))   # Slight move while still past ring
	touch._drag(2, origin + Vector2(in_dist, 0.0))     # Pulled back inside ring before tick 2
	_check(InputActions.pending_touch_fire_aim == Vector2.ZERO and not Input.is_action_pressed(InputActions.FIRE),
		"G-19b: pulling thumb back inside the ring after a sampled tick does not queue an extra shot")
	touch._touch(2, origin + Vector2(in_dist, 0.0), false)
	InputActions.pending_touch_fire_aim = Vector2.ZERO
	touch.free()

func _test_netfox_oversized_packet_warning_rate_limit() -> void:
	var peer_id: int = 777
	NetworkSynchronizationServer.erase_peer(peer_id)
	var big: PackedByteArray = PackedByteArray()
	big.resize(NetworkSynchronizationServer._max_packet_size * 4 + 16)
	_size_warnings.count = 0
	for _i: int in 20:
		NetworkSynchronizationServer._handle_full_state(peer_id, big)
	_check(_size_warnings.count == 1,
		"G-24a: oversized-packet warnings are rate-limited to at most 1 per second per peer (got %d)" % _size_warnings.count)
	NetworkSynchronizationServer.erase_peer(peer_id)
	_check(not NetworkSynchronizationServer._last_size_warning_msec.has(peer_id),
		"G-24b: erase_peer clears oversized-packet warning timestamp for disconnected peer")
