extends Node
## Regression tests for active unmerged geminiceo fixes (G-21a/b, G-22, G-26, G-27)
## against origin/main (2a9e175). Every check fails on origin/main without its fix.
## Run:
##   godot --headless --path . res://tests/test_security_audit.tscn
## Exits 0 when every check passes, 1 otherwise.

const BOT_SCENE: PackedScene = preload("res://scenes/bot.tscn")
const COMBAT_OBJECTS_SCRIPT: GDScript = preload("res://tests/test_combat_objects.gd")
const TIMEOUT_SECONDS: float = 30.0

var _failures: int = 0
var _checks: int = 0
var _cfg: TuningConfig = TuningConfig.get_default()

func _ready() -> void:
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
	await _test_rocket_hits_bot_before_wall_and_range()
	await _test_gadget_cycle_reset_ordering_and_skipped_tick()
	_test_touch_flick_curve_then_pull_back_inside_ring()
	_test_combat_objects_skips_unmerged_client_prediction()
	print("%d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)

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

func _test_touch_flick_curve_then_pull_back_inside_ring() -> void:
	var touch: TouchControls = TouchControls.new()
	touch.size = Vector2(1280.0, 720.0)
	add_child(touch)
	var origin: Vector2 = Vector2(900.0, 500.0)
	var out_dist: float = _cfg.stick_radius_px * (_cfg.fire_ring_fraction + 0.15)
	var in_dist: float = _cfg.stick_radius_px * (_cfg.fire_ring_fraction - 0.15)
	InputActions.pending_touch_fire_aim = Vector2.ZERO
	touch._touch(1, origin, true)
	touch._drag(1, origin + Vector2(out_dist, 0.0))
	touch._drag(1, origin + Vector2(0.0, -out_dist))
	touch._drag(1, origin + Vector2(0.0, -in_dist))
	touch._touch(1, origin + Vector2(0.0, -in_dist), false)
	var captured: Vector2 = InputActions.pending_touch_fire_aim
	_check(captured.y < -0.5 and absf(captured.x) < 0.2,
		"G-27: curved flick pulled back inside ring before tick keeps curved aim (got %s)" % [captured])
	InputActions.pending_touch_fire_aim = Vector2.ZERO
	touch.free()

func _test_combat_objects_skips_unmerged_client_prediction() -> void:
	var probe: Node = COMBAT_OBJECTS_SCRIPT.new()
	var rows: Dictionary = {}
	rows[100] = {
		"active": true, "explode": -1, "spawn": 10, "blasts": 0, "slot_pos": Vector2(100, 100),
		"dummy_pos": Vector2(64, 100), "dummy_hp": 100.0, "dummy_hits": 0, "dummy_attacker": -1,
		"client_pos": Vector2(128, 100), "client_hp": 100.0, "client_hits": 0,
		"watch_auth": true, "dummy_auth": true, "client_auth": true,
	}
	rows[101] = {
		"active": false, "explode": 100, "spawn": 10, "blasts": 1, "slot_pos": Vector2(100, 100),
		"dummy_pos": Vector2(64, 100), "dummy_hp": 75.0, "dummy_hits": 1, "dummy_attacker": 2,
		"client_pos": Vector2(128, 100), "client_hp": 100.0, "client_hits": 0,
		"watch_auth": true, "dummy_auth": true, "client_auth": false,
	}
	rows[102] = {
		"active": false, "explode": 100, "spawn": 10, "blasts": 1, "slot_pos": Vector2(100, 100),
		"dummy_pos": Vector2(54, 100), "dummy_hp": 75.0, "dummy_hits": 1, "dummy_attacker": 2,
		"client_pos": Vector2(128, 100), "client_hp": 79.17, "client_hits": 1,
		"watch_auth": true, "dummy_auth": true, "client_auth": true,
	}
	probe.set("_rows", rows)
	var picked: Dictionary = probe.call("_nearest_auth", "client_auth", 101, 106, 1) as Dictionary
	var rises: int = probe.call("_rises", "client_hits", "client_auth", 90, 110) as int
	_check(not picked.is_empty() and absf((picked["client_hp"] as float) - 79.17) < 0.01 and rises == 1,
		"G-26: combat objects test skips non-authoritative client.vitals row at explode+1 and reads 79.17 HP / 1 rise")
	probe.free()
