extends Node
## Headless test of the combat foundation (task A): the bot's synchronizer paths, the
## config numbers, MatchSettings, the arena's solid rectangles, the push window, the
## object pool and pickup spots, the resolver wiring and the smoke probe's fire counter.
## It opens no socket. Run:
##   godot --headless --path . res://tests/test_foundation.tscn
## Exits 0 when every check passes, 1 otherwise.

const BOT_SCENE: PackedScene = preload("res://scenes/bot.tscn")
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const LAYOUT: ArenaLayout = preload("res://config/smelter.tres")
const WORLD_SIZE: float = 200000.0
const EPS: float = 0.001
const TIMEOUT_SECONDS: float = 60.0

## Every bot state property registered for rollback.
const BOT_STATE: Array[String] = [
	":global_position", ":velocity", ":fuel", ":thrust_level", ":dash_left", ":dash_cooldown_left",
	":dash_dir", ":jet_buffer", ":jet_held_prev", ":dash_buffer", ":wall_grace_left", ":wall_nx",
	":facing", ":drop_left", ":aim_dir",
	"Vitals:health", "Vitals:knocked_out", "Vitals:respawn_tick", "Vitals:ko_serial", "Vitals:hits_taken",
	"Vitals:last_hit_push", "Vitals:last_hit_damage", "Vitals:last_attacker", "Vitals:last_attack_tick",
	"Vitals:knockouts", "Vitals:push_until_tick", "Vitals:cycle_index",
	"Arsenal:active_slot", "Arsenal:picked_weapon", "Arsenal:picked_ammo", "Arsenal:fire_ready_tick",
	"Arsenal:last_shot_tick", "Arsenal:shots_fired", "Arsenal:last_shot_weapon", "Arsenal:shot_dir",
	"Arsenal:melee_ready_tick", "Arsenal:last_melee_tick", "Arsenal:melee_serial",
	"Gadgets:gadget_a", "Gadgets:gadget_b", "Gadgets:gadget_ready_tick", "Gadgets:last_gadget_tick",
	"Gadgets:last_gadget_id", "Gadgets:gadget_dir", "Gadgets:gadget_serial",
]
const BOT_INPUT: Array[String] = ["Input:move", "Input:aim", "Input:jet", "Input:dash", "Input:fire", "Input:melee", "Input:gadget", "Input:swap"]
const OBJECT_STATE: Array[String] = [
	":active", ":kind", ":owner_peer", ":global_position", ":velocity", ":spawn_tick", ":arm_tick",
	":fuse_tick", ":explode_tick", ":landed", ":launches", ":blasts",
]

## Top-level config fields that are zero on purpose (ENet's throttle must never fall).
const CONFIG_ZERO_ON_PURPOSE: Array[String] = ["throttle_deceleration"]

## WeaponStats fields that are zero on purpose, by weapon index (rivet, bolt, scrap, rocket).
## Everything else in the config must be above zero.
const ZERO_MEANS_NONE: Dictionary = {
	0: ["ammo", "spread_degrees", "recoil", "projectile_speed", "projectile_radius", "blast_radius", "blast_push", "blast_damage"],
	1: ["spread_degrees", "recoil", "projectile_speed", "projectile_radius", "blast_radius", "blast_push", "blast_damage"],
	2: ["projectile_speed", "projectile_radius", "blast_radius", "blast_push", "blast_damage"],
	3: ["damage", "push", "spread_degrees", "recoil"],
}

var _cfg: TuningConfig = TuningConfig.get_default()
var _dt: float = 0.0
var _px: float = 0.0
var _failures: int = 0
var _checks: int = 0
var _tick: int = 0
var _nodes: Array[Node] = []

func _ready() -> void:
	get_tree().create_timer(TIMEOUT_SECONDS).timeout.connect(_on_timeout)
	_run()

# A script error inside a coroutine stops it silently; without this the run would hang.
func _on_timeout() -> void:
	print("FAIL timeout, the test did not finish")
	get_tree().quit(1)

func _run() -> void:
	_dt = 1.0 / float(_cfg.tick_rate)
	_px = _cfg.bot_height_px
	_test_config_numbers()
	_test_layout()
	_test_item_ids()
	_test_tuning_at()
	_test_hazard_ticks()
	_test_round_start_resim()
	_test_round_start_reset()
	_test_gdd_pushes()
	await _test_arena_solids()
	await _test_bot_paths()
	await _test_body_rect_and_knocked_out()
	await _test_push_window()
	await _test_input()
	await _test_pool_and_pickups()
	await _test_dummy_slot()
	await _test_main_scene()
	await _test_probe_fire_passes()
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

func _own(node: Node) -> void:
	_nodes.append(node)

func _clear() -> void:
	for node: Node in _nodes:
		node.free()
	_nodes.clear()
	await get_tree().physics_frame
	await get_tree().physics_frame

func _add_floor() -> void:
	var body: StaticBody2D = StaticBody2D.new()
	body.position = Vector2(0.0, 50.0)
	body.collision_layer = Bot.LAYER_SOLID
	body.collision_mask = 0
	var shape_node: CollisionShape2D = CollisionShape2D.new()
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = Vector2(WORLD_SIZE, 100.0)
	shape_node.shape = shape
	body.add_child(shape_node)
	add_child(body)
	_own(body)

# A bot standing just above a floor whose top is at y = 0.
func _spawn_on_floor() -> Bot:
	var bot: Bot = BOT_SCENE.instantiate() as Bot
	bot.position = Vector2(0.0, -_px / 2.0 - 0.5)
	add_child(bot)
	_own(bot)
	await get_tree().physics_frame
	await get_tree().physics_frame
	return bot

func _step(bot: Bot, ticks: int = 1) -> void:
	for i: int in ticks:
		bot._rollback_tick(_dt, _tick, true)
		_tick += 1

# ---- config ----

func _test_config_numbers() -> void:
	var zero_fields: Array[String] = []
	for info: Dictionary in _cfg.get_property_list():
		if (info["usage"] as int) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		var field: String = info["name"] as String
		var value: Variant = _cfg.get(field)
		match typeof(value):
			TYPE_FLOAT, TYPE_INT:
				if CONFIG_ZERO_ON_PURPOSE.has(field):
					if value != 0:
						zero_fields.append(field + " (listed as zero but is not)")
				elif value == 0:
					zero_fields.append(field)
			TYPE_VECTOR2:
				if (value as Vector2).x == 0.0 or (value as Vector2).y == 0.0:
					zero_fields.append(field)
	_check(zero_fields.is_empty(), "no config field is zero (zero ones: %s)" % ", ".join(zero_fields))
	_check(_cfg.weapons.size() == ItemIds.WEAPON_COUNT, "four weapons in the config")
	for i: int in _cfg.weapons.size():
		var stats: WeaponStats = _cfg.weapons[i]
		var allowed: Array = ZERO_MEANS_NONE.get(i, []) as Array
		var weapon_zeros: Array[String] = []
		for info: Dictionary in stats.get_property_list():
			if (info["usage"] as int) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
				continue
			var field: String = info["name"] as String
			var value: Variant = stats.get(field)
			if (typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT) and value == 0 and not allowed.has(field):
				weapon_zeros.append(field)
			if (typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT) and value != 0 and allowed.has(field):
				weapon_zeros.append(field + " (listed as zero but is not)")
		_check(weapon_zeros.is_empty(), "weapon %d has no unexpected zero (%s)" % [i, ", ".join(weapon_zeros)])
	_check(_cfg.weapon_stats(ItemIds.BOLT_THROWER) == _cfg.weapons[1] and _cfg.weapon_stats(99) == null and _cfg.weapon_stats(-1) == null, "weapon_stats looks up by id")
	_check(_cfg.weapons[ItemIds.RIVET_GUN].infinite_ammo and not _cfg.weapons[ItemIds.BOLT_THROWER].infinite_ammo, "only the rivet gun has infinite ammo")
	# GDD numbers.
	_near(_cfg.max_health, 100.0, EPS, "config health (GDD 100)")
	_near(_cfg.knockout_repair, 20.0, EPS, "config knockout repair (GDD 20)")
	_near(_cfg.bomb_fuse_time, 3.0, EPS, "config bomb fuse (GDD 3 s)")
	_near(_cfg.hazard_start_time, 30.0, EPS, "config hazard start (GDD 30 s)")
	_near(_cfg.hazard_cap_time, 45.0, EPS, "config hazard cap (GDD 45 s)")
	_near(_cfg.low_health_push_multiplier, 2.0, EPS, "config low-health push multiplier (GDD about 2)")
	_check(_cfg.plate_slots_per_owner == 2 and _cfg.gadget_slot_count == 2, "two plates and two gadgets per player (GDD)")
	_near(_cfg.bomb_blast_radius, 3.0, EPS, "bomb blast reaches 0 at 3 bot heights (architecture)")
	_near(_cfg.bomb_blast_push, 5.0, EPS, "bomb blast push 5 at the centre (architecture)")
	# The bolt thrower empties a full health bar in about one second of hits.
	var bolt: WeaponStats = _cfg.weapons[ItemIds.BOLT_THROWER]
	var seconds_to_kill: float = ceilf(_cfg.max_health / bolt.damage) * bolt.fire_interval
	_check(seconds_to_kill >= 0.8 and seconds_to_kill <= 1.2, "bolt thrower empties a full bar in about 1 s (%.2f s)" % seconds_to_kill)
	_check(_cfg.push_window_control > 0.0 and _cfg.push_window_control < 1.0, "push window control is between 0 and 1")
	_check(_cfg.hazard_cap_time > _cfg.hazard_start_time and _cfg.hazard_cycle_time >= _cfg.hazard_cap_time, "hazard start < cap <= cycle")

func _test_layout() -> void:
	var bounds: Rect2 = LAYOUT.bounds
	_check(bounds.has_point(LAYOUT.dummy_spawn), "dummy spawn is inside the arena")
	_check(LAYOUT.hazard_top > 0.0 and LAYOUT.hazard_top < bounds.end.y, "hazard top is inside the arena")
	_check(LAYOUT.pickup_spots.size() == LAYOUT.pickup_items.size() and LAYOUT.pickup_spots.size() == 4, "four pickup spots with four items")
	var weapons: int = 0
	var plates: int = 0
	for item: int in LAYOUT.pickup_items:
		weapons += int(ItemIds.is_weapon(item) and item != ItemIds.RIVET_GUN)
		plates += int(item == ItemIds.SPRING_PLATE)
	_check(weapons == 3 and plates == 1, "three pickup weapons and one Spring Plate")
	var inside: bool = true
	for spot: Vector2 in LAYOUT.pickup_spots:
		inside = inside and bounds.has_point(spot)
	_check(inside, "every pickup spot is inside the arena")

func _test_item_ids() -> void:
	_check(ItemIds.is_weapon(ItemIds.ROCKET_TUBE) and not ItemIds.is_weapon(ItemIds.COOKER_BOMB) and not ItemIds.is_weapon(ItemIds.NONE), "is_weapon")
	_check(ItemIds.is_gadget(ItemIds.SPRING_PLATE) and not ItemIds.is_gadget(ItemIds.RIVET_GUN), "is_gadget")

# ---- MatchSettings ----

func _test_tuning_at() -> void:
	var same: bool = true
	for tick: int in [-5, 0, 1, 30, 100000]:
		same = same and MatchSettings.tuning_at(tick) == TuningConfig.get_default()
	_check(same, "MatchSettings.tuning_at returns the default config on every tick")

func _test_hazard_ticks() -> void:
	var saved: int = MatchSettings.round_start_tick
	var cycle: int = roundi(_cfg.hazard_cycle_time * float(_cfg.tick_rate))
	MatchSettings.round_start_tick = -1
	_check(MatchSettings.hazard_ticks(500) == -1, "hazard_ticks is -1 before a round starts")
	MatchSettings.round_start_tick = 100
	_check(MatchSettings.hazard_ticks(99) == -1, "hazard_ticks is -1 before the round start tick")
	_check(MatchSettings.hazard_ticks(100) == 0, "hazard_ticks is 0 at the round start tick")
	_check(MatchSettings.hazard_ticks(101) == 1, "hazard_ticks counts up")
	_check(MatchSettings.hazard_ticks(100 + cycle - 1) == cycle - 1, "hazard_ticks is cycle - 1 on the last tick of the cycle (%d)" % (cycle - 1))
	_check(MatchSettings.hazard_ticks(100 + cycle) == 0, "hazard_ticks wraps to 0 after one cycle (%d ticks)" % cycle)
	_check(MatchSettings.hazard_ticks(100 + 3 * cycle + 7) == 7, "hazard_ticks repeats every cycle")
	MatchSettings.round_start_tick = saved

# The receive side asks netfox for a re-simulation only for a tick in the past that is still
# inside the history. NetworkTime and NetworkRollback internals are set by hand for this.
func _test_round_start_resim() -> void:
	var saved_start: int = MatchSettings.round_start_tick
	var saved_tick: int = NetworkTime._tick
	var saved_resim: int = NetworkRollback._resim_from
	NetworkTime._tick = 100
	var oldest: int = NetworkRollback.history_start

	NetworkRollback._resim_from = 100
	MatchSettings._apply_round_start(90)
	NetworkRollback.before_loop.emit()
	_check(MatchSettings.round_start_tick == 90, "a received round start tick is stored")
	_check(NetworkRollback._resim_from == 90, "a start tick in the past asks netfox to re-simulate from it")
	_check(not NetworkRollback.before_loop.is_connected(MatchSettings._on_before_loop), "the re-simulation request is handed over once")

	NetworkRollback._resim_from = 100
	MatchSettings._apply_round_start(oldest - 1)
	NetworkRollback.before_loop.emit()
	_check(NetworkRollback._resim_from == 100, "a start tick older than the history asks for nothing")

	NetworkRollback._resim_from = 100
	MatchSettings._apply_round_start(150)
	NetworkRollback.before_loop.emit()
	_check(NetworkRollback._resim_from == 100, "a start tick in the future asks for nothing")

	NetworkRollback._resim_from = 100
	MatchSettings._apply_round_start(95)
	MatchSettings._apply_round_start(92)
	NetworkRollback.before_loop.emit()
	_check(NetworkRollback._resim_from == 92, "two requests before the loop keep the earliest tick")

	NetworkTime._tick = saved_tick
	NetworkRollback._resim_from = saved_resim
	MatchSettings.round_start_tick = saved_start

# A session that stops between the RPC and the next loop must not leave a request behind.
func _test_round_start_reset() -> void:
	var saved_start: int = MatchSettings.round_start_tick
	var saved_tick: int = NetworkTime._tick
	NetworkTime._tick = 100
	MatchSettings._apply_round_start(90)
	_check(NetworkRollback.before_loop.is_connected(MatchSettings._on_before_loop), "a start tick in the past leaves a pending request")
	MatchSettings._reset()
	_check(not NetworkRollback.before_loop.is_connected(MatchSettings._on_before_loop) and MatchSettings._resim_from == -1, "stopping a session clears the pending re-simulation request")
	_check(MatchSettings.round_start_tick == -1, "stopping a session clears the round start tick")
	NetworkTime._tick = saved_tick
	MatchSettings.round_start_tick = saved_start

# Every push number the GDD gives (Starting values), in the unit of WeaponStats.push.
func _test_gdd_pushes() -> void:
	var rivet: WeaponStats = _cfg.weapons[ItemIds.RIVET_GUN]
	var bolt: WeaponStats = _cfg.weapons[ItemIds.BOLT_THROWER]
	var scrap: WeaponStats = _cfg.weapons[ItemIds.SCRAP_BLASTER]
	var rocket: WeaponStats = _cfg.weapons[ItemIds.ROCKET_TUBE]
	_near(bolt.push, 0.1, EPS, "GDD push from a bolt-thrower hit is 0.1")
	_near(float(scrap.pellets) * scrap.push, 1.5, EPS, "GDD push from a scrap blast at close range is 1.5 in total (pellets x push)")
	_near(scrap.recoil, 1.0, EPS, "GDD recoil on the scrap blaster's shooter is 1")
	_near(_cfg.melee_push, 2.5, EPS, "GDD push from melee is 2.5")
	_near(_cfg.bomb_blast_push, 5.0, EPS, "GDD push at the centre of a bomb blast is 5")
	_near(rocket.blast_push, 5.0, EPS, "GDD push at the centre of a rocket blast is 5")
	_near(_cfg.bomb_blast_radius, 3.0, EPS, "GDD bomb blast fades to nothing at 3 from the centre")
	_near(rocket.blast_radius, 3.0, EPS, "GDD rocket blast fades to nothing at 3 from the centre")
	_near(_cfg.low_health_threshold, 25.0, EPS, "GDD extra push below 25 health")
	_near(_cfg.low_health_push_multiplier, 2.0, EPS, "GDD up to double push at low health")
	_check(rivet.push > 0.0 and rivet.push - bolt.push <= 0.06, "the rivet gun's push (not in the GDD) is only a little above the bolt thrower's")

# ---- arena ----

func _rect_key(rect: Rect2) -> String:
	return "%.4f,%.4f,%.4f,%.4f" % [rect.position.x, rect.position.y, rect.size.x, rect.size.y]

func _test_arena_solids() -> void:
	var arena: Arena = Arena.new()
	arena.layout = LAYOUT
	add_child(arena)
	_own(arena)
	await get_tree().process_frame
	var from_shapes: Array[String] = []
	var thin_count: int = 0
	for child: Node in arena.get_children():
		var body: StaticBody2D = child as StaticBody2D
		if body == null:
			continue
		var shape: RectangleShape2D = (body.get_child(0) as CollisionShape2D).shape as RectangleShape2D
		if body.collision_layer == Bot.LAYER_SOLID:
			from_shapes.append(_rect_key(Rect2(body.position - shape.size / 2.0, shape.size)))
		else:
			thin_count += 1
	var from_layout: Array[String] = []
	for rect: Rect2 in LAYOUT.solid_rects_px(_px):
		from_layout.append(_rect_key(rect))
	from_shapes.sort()
	from_layout.sort()
	_check(from_layout.size() == 4 + LAYOUT.solids.size(), "solid_rects_px has the four walls and every solid block (%d)" % from_layout.size())
	_check(from_shapes == from_layout, "solid_rects_px matches the arena's collision shapes exactly")
	_check(thin_count == LAYOUT.thins.size(), "thin platforms are not in solid_rects_px (%d thin bodies)" % thin_count)
	await _clear()

# ---- bot ----

func _test_bot_paths() -> void:
	var bot: Bot = BOT_SCENE.instantiate() as Bot
	add_child(bot)
	_own(bot)
	await get_tree().process_frame
	var sync: RollbackSynchronizer = bot.get_node("RollbackSynchronizer") as RollbackSynchronizer
	var state: Array[String] = sync.state_properties
	var inputs: Array[String] = sync.input_properties
	_check(state.size() == BOT_STATE.size(), "the bot synchronizer lists %d state properties (expected %d)" % [state.size(), BOT_STATE.size()])
	var missing: Array[String] = []
	for path: String in BOT_STATE:
		if not state.has(path):
			missing.append(path)
	_check(missing.is_empty(), "every architecture state property is listed (missing: %s)" % ", ".join(missing))
	var bad: Array[String] = []
	for path: String in state + inputs:
		var entry: PropertyEntry = PropertyEntry.parse(sync.root, path)
		if not entry.is_valid():
			bad.append(path)
	_check(bad.is_empty(), "every state and input path resolves on an instanced bot (bad: %s)" % ", ".join(bad))
	_check(inputs == BOT_INPUT, "the bot synchronizer lists the eight inputs")
	_check(bot.vitals != null and bot.arsenal != null and bot.gadgets != null and bot.visual != null, "the bot has Vitals, Arsenal, Gadgets and Visual")
	_check(bot.visual.hit_freeze != null and bot.visual.hit_flash != null, "the Visual has HitFreeze and HitFlash")
	_check(bot.visual.hit_freeze.target == bot.visual and bot.visual.hit_flash.target == bot.visual, "freeze and flash target the Visual, not the body")
	_near(bot.vitals.health, _cfg.max_health, EPS, "a new bot starts at full health")
	_check(not bot.vitals.knocked_out and bot.vitals.is_out() == false, "a new bot is not knocked out")
	_check(bot.arsenal.active_weapon() == ItemIds.RIVET_GUN and not bot.arsenal.fired_at(0) and not bot.arsenal.meleed_at(0), "a new bot holds the rivet gun and has not fired")
	_check(not bot.gadgets.used_at(0) and bot.gadgets.used_id() == ItemIds.NONE, "a new bot has not used a gadget")
	_check(Bot.NO_PEER == -1, "NO_PEER is -1")
	await _clear()

func _test_body_rect_and_knocked_out() -> void:
	_add_floor()
	var bot: Bot = await _spawn_on_floor()
	_step(bot, 5)
	var rect: Rect2 = bot.body_rect()
	_near(rect.size.x, _cfg.bot_width_bh * _px, EPS, "body_rect width")
	_near(rect.size.y, _px, EPS, "body_rect height")
	_check(rect.get_center().is_equal_approx(bot.global_position) and bot.center() == bot.global_position, "body_rect is centred on the bot and center() is its position")
	# Knocked out: no movement, but the tick is still noted.
	bot.input.move = Vector2.RIGHT
	bot.vitals.knocked_out = true
	var start: Vector2 = bot.position
	_step(bot, 10)
	_check(bot.position == start and bot.velocity.x == 0.0, "a knocked-out bot does not move")
	_check(bot.last_sim_tick == _tick - 1, "a knocked-out bot still records the tick")
	bot.vitals.knocked_out = false
	_step(bot, 10)
	_check(bot.position.x > start.x, "the bot moves again when no longer knocked out")
	await _clear()

# One tick of braking at a given speed: how much speed is lost.
func _speed_lost(bot: Bot) -> float:
	var speed: float = _cfg.run_speed * _px
	bot.velocity.x = speed
	_step(bot)
	return speed - bot.velocity.x

func _test_push_window() -> void:
	var control: float = _cfg.push_window_control
	var full_brake: float = _cfg.ground_brake * _px * _dt

	# Without the window the braking is exactly the configured ground braking.
	_add_floor()
	var plain: Bot = await _spawn_on_floor()
	_step(plain, 5)
	_near(_speed_lost(plain), full_brake, EPS, "no push window: ground braking is unchanged (px/s per tick)")
	_check(plain.vitals.push_until_tick == 0, "push_until_tick starts at 0")

	# Inside the window the braking is reduced by the control factor.
	var window: Bot = await _spawn_on_floor()
	_step(window, 5)
	window.vitals.push_until_tick = _tick + 4
	_near(_speed_lost(window), full_brake * control, EPS, "inside the push window: braking is scaled by the control factor")
	_step(window, 2)
	_near(_speed_lost(window), full_brake * control, EPS, "still inside the window on its last tick")
	# The window covers the ticks below push_until_tick, so this tick is the first outside it.
	_near(_speed_lost(window), full_brake, EPS, "the window closes exactly at push_until_tick")

	# Steering is reduced too: accelerating from rest with the stick pushed.
	var steer_plain: Bot = await _spawn_on_floor()
	var steer_window: Bot = await _spawn_on_floor()
	_step(steer_plain, 5)
	_step(steer_window, 5)
	steer_window.vitals.push_until_tick = _tick + 100
	steer_plain.input.move = Vector2.RIGHT
	steer_window.input.move = Vector2.RIGHT
	steer_plain._rollback_tick(_dt, _tick, true)
	steer_window._rollback_tick(_dt, _tick, true)
	_tick += 1
	var plain_gain: float = steer_plain.velocity.x
	var window_gain: float = steer_window.velocity.x
	_near(plain_gain, _cfg.ground_accel * _px * _dt, EPS, "no push window: ground steering is unchanged")
	_near(window_gain, plain_gain * control, EPS, "inside the push window: steering is scaled by the control factor")
	await _clear()

	# A grounded bot with a sideways velocity travels measurably further inside the window.
	var distances: Array[float] = []
	for in_window: bool in [false, true]:
		_add_floor()
		var bot: Bot = await _spawn_on_floor()
		_step(bot, 5)
		var start_x: float = bot.position.x
		bot.velocity.x = _cfg.run_speed * _px
		if in_window:
			bot.vitals.push_until_tick = _tick + int(_cfg.push_window_time * float(_cfg.tick_rate)) + 1
		_step(bot, 30)
		distances.append(bot.position.x - start_x)
		await _clear()
	_check(distances[1] > distances[0] * 2.0, "a pushed grounded bot travels further inside the push window (%.1f px against %.1f px)" % [distances[1], distances[0]])

# ---- input ----

func _test_input() -> void:
	var bot: Bot = BOT_SCENE.instantiate() as Bot
	add_child(bot)
	_own(bot)
	await get_tree().process_frame
	var input: BotInput = bot.input
	_check(input.fire == false and input.melee == false and input.gadget == false and input.swap == false, "the four new inputs start false")
	_check(not input.dummy, "dummy starts false")
	_check(not Bot.clean_bool("yes") and not Bot.clean_bool(1) and not Bot.clean_bool(Vector2.UP) and Bot.clean_bool(true), "a wrong-typed button value is not pressed")
	# A scripted bot gathers input; the same bot as a dummy does not.
	input.autopilot = true
	input._on_after_tick(_dt, 0)
	_check((input.aim as Vector2).length() > 0.5, "an autopilot bot gathers input")
	input.aim = Vector2.ZERO
	input.dummy = true
	input._on_after_tick(_dt, 1)
	_check((input.aim as Vector2) == Vector2.ZERO, "a dummy bot gathers nothing")
	await _clear()

# ---- pool, pickups, main scene ----

func _slot_names(pool: WorldObjects) -> Array[String]:
	var names: Array[String] = []
	for slot: WorldObject in pool.slots():
		names.append(String(slot.name))
	return names

func _test_pool_and_pickups() -> void:
	var expected: int = _cfg.max_players * (_cfg.rocket_slots_per_owner + _cfg.bomb_slots_per_owner + _cfg.plate_slots_per_owner)
	# Two pools built the same way, as a host and a client each build theirs.
	var host_parent: Node = Node.new()
	var client_parent: Node = Node.new()
	add_child(host_parent)
	add_child(client_parent)
	_own(host_parent)
	_own(client_parent)
	var host_pool: WorldObjects = WorldObjects.new()
	var client_pool: WorldObjects = WorldObjects.new()
	host_parent.add_child(host_pool)
	client_parent.add_child(client_pool)
	await get_tree().process_frame
	_check(host_pool.slots().size() == expected and expected == 24, "the object pool has the configured number of slots (%d)" % host_pool.slots().size())
	_check(_slot_names(host_pool) == _slot_names(client_pool), "two pools have identical slot names")
	var names: Array[String] = _slot_names(host_pool)
	_check(names[0] == "Obj0" and names[expected - 1] == "Obj%d" % (expected - 1), "slots are named Obj0 to ObjN-1")
	var slot: WorldObject = host_pool.slots()[0]
	_check(not slot.active and slot.kind == ItemIds.NONE and slot.get_multiplayer_authority() == 1, "a new slot is inactive and owned by the host")
	var sync: RollbackSynchronizer = slot.get_node("RollbackSynchronizer") as RollbackSynchronizer
	var bad: Array[String] = []
	for path: String in sync.state_properties:
		if not PropertyEntry.parse(sync.root, path).is_valid():
			bad.append(path)
	_check(bad.is_empty() and sync.state_properties.size() == OBJECT_STATE.size() and sync.input_properties.is_empty(), "a slot synchronizer has the object state and no input (bad: %s)" % ", ".join(bad))
	_check(slot.get_node_or_null("TickInterpolator") != null, "a slot has a TickInterpolator")
	_check(host_pool.launch(ItemIds.OBJECT_BOMB, 0, 1, Vector2.ZERO, Vector2.ZERO, 0, _cfg) == host_pool.slots()[_cfg.rocket_slots_per_owner], "launch returns the first bomb slot of the owner")

	var pickups: Pickups = Pickups.new()
	pickups.layout = LAYOUT
	host_parent.add_child(pickups)
	await get_tree().process_frame
	_check(pickups.spots().size() == LAYOUT.pickup_spots.size(), "one pickup spot per layout spot")
	var spot: PickupSpot = pickups.spots()[0]
	_check(String(spot.name) == "Spot0" and spot.item == LAYOUT.pickup_items[0] and spot.position == LAYOUT.pickup_spots[0] * _px, "a spot has its name, item and position")
	var spot_sync: RollbackSynchronizer = spot.get_node("RollbackSynchronizer") as RollbackSynchronizer
	_check(spot_sync.state_properties.size() == 1 and spot_sync.state_properties[0] == ":ready_tick" and PropertyEntry.parse(spot_sync.root, ":ready_tick").is_valid(), "a spot synchronizer holds ready_tick")
	await _clear()

func _test_dummy_slot() -> void:
	var dummy_slot: int = _cfg.max_players
	# Slot ranges: every owner has its own range, the ranges tile the pool, the dummy has none.
	var pool: WorldObjects = WorldObjects.new()
	add_child(pool)
	_own(pool)
	await get_tree().process_frame
	var covered: Array[int] = []
	var counts: Array[int] = [_cfg.rocket_slots_per_owner, _cfg.bomb_slots_per_owner, _cfg.plate_slots_per_owner]
	var sizes_ok: bool = true
	for owner_slot: int in _cfg.max_players:
		for kind: int in ItemIds.OBJECT_KIND_COUNT:
			var slots: Vector2i = pool.slot_range(kind, owner_slot, _cfg)
			sizes_ok = sizes_ok and slots.y == counts[kind]
			for i: int in slots.y:
				covered.append(slots.x + i)
	covered.sort()
	var tiles: bool = covered.size() == pool.slots().size()
	for i: int in covered.size():
		tiles = tiles and covered[i] == i
	_check(sizes_ok, "every owner has the configured count of slots for every kind")
	_check(tiles, "slot ranges tile the whole pool without overlap")
	var none: bool = true
	for kind: int in ItemIds.OBJECT_KIND_COUNT:
		none = none and pool.slot_range(kind, dummy_slot, _cfg).y == 0 and pool.slot_range(kind, -1, _cfg).y == 0
	_check(none, "the dummy's owner slot (and -1) has no world-object range")
	_check(pool.slot_range(99, 0, _cfg).y == 0, "a bad kind has no range")
	_check(pool.launch(ItemIds.OBJECT_BOMB, dummy_slot, Bot.DUMMY_PEER, Vector2.ZERO, Vector2.ZERO, 0, _cfg) == null, "the dummy cannot launch")

	# The spawner: players never get the dummy's slot, and the dummy's slot is accepted.
	var spawner: BotSpawner = BotSpawner.new()
	spawner.bot_scene = BOT_SCENE
	spawner.layout = LAYOUT
	add_child(spawner)
	_own(spawner)
	await get_tree().process_frame
	for player: int in _cfg.max_players:
		var bot: Bot = spawner._spawn_bot({"peer_id": 100 + player, "slot": spawner._free_slot()}) as Bot
		add_child(bot)
		_own(bot)
	var used: Array[int] = []
	for bot: Bot in spawner.get_bots().values():
		used.append(bot.slot)
	used.sort()
	_check(used == [0, 1, 2, 3], "four players take slots 0 to 3, never the dummy's")
	_check(spawner._free_slot() < dummy_slot, "a full match never hands out the dummy's slot")
	var dummy: Bot = spawner._spawn_bot({"peer_id": Bot.DUMMY_PEER, "slot": dummy_slot}) as Bot
	add_child(dummy)
	_own(dummy)
	_check(dummy.slot == dummy_slot and dummy.peer_id == 0 and Bot.DUMMY_PEER != Bot.NO_PEER, "the dummy keeps slot max_players and peer id 0")
	_check(dummy.position == LAYOUT.dummy_spawn * _px, "the dummy spawns at the layout's dummy spawn")
	var wild: Bot = spawner._spawn_bot({"peer_id": 55, "slot": 99}) as Bot
	add_child(wild)
	_own(wild)
	_check(wild.slot == dummy_slot, "a bad slot is clamped to the dummy's slot, not to a player's")
	await _clear()

func _test_main_scene() -> void:
	var main: Node = MAIN_SCENE.instantiate()
	add_child(main)
	_own(main)
	await get_tree().process_frame
	var names: Array[String] = ["Objects", "Pickups", "Resolver", "Effects", "PartsBurst", "HazardVisual", "Camera/ScreenShake"]
	var missing: Array[String] = []
	for node_name: String in names:
		if main.get_node_or_null(node_name) == null:
			missing.append(node_name)
	_check(missing.is_empty(), "main.tscn has every combat node (missing: %s)" % ", ".join(missing))
	var objects: WorldObjects = main.get_node("Objects") as WorldObjects
	var resolver: CombatResolver = main.get_node("Resolver") as CombatResolver
	var effects: EffectsDirector = main.get_node("Effects") as EffectsDirector
	_check(objects.slots().size() == 24, "the Objects node builds the pool on its own")
	_check(NetworkRollback.after_process_tick.is_connected(resolver._on_after_process_tick), "the resolver is connected to after_process_tick")
	_check(resolver.objects == objects and resolver.pickups == main.get_node("Pickups") and resolver.layout == LAYOUT, "the resolver has its references")
	_check(effects.layout == LAYOUT, "the effects director has the arena layout")
	_check(main.get_node("HazardVisual").get_index() > main.get_node("Bots").get_index(), "the hazard visual is after Bots in the tree, so the metal draws in front of bots")
	_check(effects.burst == main.get_node("PartsBurst") and effects.shake == main.get_node("Camera/ScreenShake") and effects.hazard_visual == main.get_node("HazardVisual") and effects.objects == objects, "the effects director has its references")
	_check(main.get_node("PartsBurst").get_parent() == main, "PartsBurst is under the world, not under a bot")
	# The source calls the four rule functions in the documented order.
	var source: String = FileAccess.get_file_as_string("res://scripts/game/combat_resolver.gd")
	var order: Array[int] = [source.find("WeaponRules.collect"), source.find("GadgetRules.collect"), source.find("pickups.resolve"), source.find("CombatRules.apply")]
	_check(order[0] >= 0 and order[0] < order[1] and order[1] < order[2] and order[2] < order[3], "the resolver calls weapons, gadgets, pickups, combat rules in that order")
	# A resolver pass over two bots runs without error and changes nothing.
	var bot_a: Bot = BOT_SCENE.instantiate() as Bot
	var bot_b: Bot = BOT_SCENE.instantiate() as Bot
	bot_a.peer_id = 7
	bot_b.peer_id = 3
	main.add_child(bot_a)
	main.add_child(bot_b)
	await get_tree().process_frame
	var sorted: Array[Bot] = resolver._sorted_bots()
	_check(sorted.size() == 2 and sorted[0] == bot_b and sorted[1] == bot_a, "the resolver sorts bots by peer id, not tree order")
	var health: float = bot_a.vitals.health
	resolver.resolve(10, sorted)
	_check(bot_a.vitals.health == health and bot_b.vitals.health == health, "a resolver pass with the stub rules changes nothing")
	await _clear()

func _test_probe_fire_passes() -> void:
	var probe: SmokeProbe = SmokeProbe.new()
	add_child(probe)
	_own(probe)
	var bot: Bot = BOT_SCENE.instantiate() as Bot
	bot.peer_id = 5
	add_child(bot)
	_own(bot)
	await get_tree().process_frame
	# The bot "fires" at tick 5 and the tick is processed three times; tick 6 is not a fire tick.
	bot.arsenal.last_shot_tick = 5
	for pass_number: int in 3:
		bot.last_sim_tick = 5
		probe._on_record_tick(6)
	bot.arsenal.last_shot_tick = -1
	bot.last_sim_tick = 6
	probe._on_record_tick(7)
	var passes: Dictionary = probe.fire_passes()
	var for_bot: Dictionary = passes.get(5, {}) as Dictionary
	_check(for_bot.get(5, 0) == 3 and for_bot.size() == 1, "the probe counts the passes of a fire tick")
	# A tick the bot did not really simulate is not counted.
	bot.arsenal.last_shot_tick = 8
	bot.last_sim_tick = 3
	probe._on_record_tick(9)
	_check(not (probe.fire_passes().get(5, {}) as Dictionary).has(8), "a pass that did not simulate the bot is not counted")
	await _clear()
