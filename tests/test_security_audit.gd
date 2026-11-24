extends Node
## Regression tests for findings audited on geminiceo (iterations 2-4, against main f479130).
## Every check verifies a concrete state/output invariant that fails without the fix.
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
	await _test_deflected_rocket_sweeps_traveled_path()
	await _test_gadget_cycle_reset_ordering_and_skipped_tick()
	_test_pickup_reset_after_skipped_cycle_tick()
	_test_pickups_reset_between_sessions()
	await _test_hud_resize_and_zero_max_health()
	_test_touch_flick_updates_aim_while_past_ring()
	_test_netfox_oversized_packet_warning_rate_limit()
	_test_netfox_bitset_and_redundant_bounds()
	_test_netfox_sanitize_and_sparse_bounds()
	print("%d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)

func _test_rocket_muzzle_wall_clamp() -> void:
	var px: float = _cfg.bot_height_px
	var solids: Array[Rect2] = LAYOUT.solid_rects_px(px)
	var bot: Bot = BOT_SCENE.instantiate() as Bot
	bot.peer_id = 1
	bot.slot = 0
	add_child(bot)
	# Stand flush against the left face of Smelter's column at x = 11 bh (704 px).
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
		"rocket fired flush against a wall does not spawn inside the wall (x=%.2f, wall=%.2f)" % [capture.launched_pos.x, wall_left])
	bot.free()

func _test_rocket_hits_bot_before_wall_and_range() -> void:
	var dt: float = 1.0 / float(_cfg.tick_rate)
	var px: float = _cfg.bot_height_px
	var radius: float = _cfg.weapon_stats(ItemIds.ROCKET_TUBE).projectile_radius * px
	# 1. Bot stands on a floor; angled rocket enters the bot before hitting the floor on the same tick.
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
	_check(rocket.explode_tick == 11 and absf(rocket.global_position.y - floor_contact_y) < 0.05,
		"rocket reaches the floor on tick 11 before bot contact check runs")
	var hits: Array[Hit] = []
	GadgetRules.collect(11, [victim], pool, pool.solids, _cfg, hits)
	var bot_left_grown: float = victim.body_rect().position.x - radius
	_check(absf(rocket.global_position.x - bot_left_grown) < 0.05 and rocket.global_position.y < floor_contact_y - 1.0,
		"rocket hitting a floor behind a bot explodes at the earlier bot contact (pos=%s, bot_x=%.2f, floor_y=%.2f)" % [rocket.global_position, bot_left_grown, floor_contact_y])
	victim.free()
	pool.free()

	# 2. Rocket reaching fuse_tick (max range) on the same tick it passes through a bot explodes on the bot, not past it.
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
		"rocket at max-range tick explodes at bot contact instead of overshooting (x=%.2f, want=%.2f)" % [r2.global_position.x, expected_x])
	victim2.free()
	pool2.free()

func _test_deflected_rocket_sweeps_traveled_path() -> void:
	var dt: float = 1.0 / float(_cfg.tick_rate)
	for on_path: bool in [false, true]:
		var pool: WorldObjects = WorldObjects.new()
		add_child(pool)
		pool.bounds_px = Rect2(-10000.0, -10000.0, 20000.0, 20000.0)
		await get_tree().process_frame
		var target: Bot = BOT_SCENE.instantiate() as Bot
		target.peer_id = 11
		target.slot = 1
		target.position = Vector2(40.0, 500.0) if on_path else Vector2(100.0, 560.0)
		add_child(target)
		var flying: WorldObject = pool.launch(ItemIds.OBJECT_ROCKET, 0, 10, Vector2(0.0, 500.0), Vector2(100.0, 0.0) / dt, 10, _cfg)
		flying._rollback_tick(dt, 11, true)
		pool.deflect(flying, Vector2(0.0, -100.0) / dt, 12, 11, _cfg)
		var hits: Array[Hit] = []
		GadgetRules.collect(11, [target], pool, pool.solids, _cfg, hits)
		_check((flying.explode_tick == 11) == on_path and (not hits.is_empty()) == on_path,
			"deflected rocket contact uses traveled path (on_path=%s)" % str(on_path))
		target.free()
		pool.free()

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
	# Cycle-0 bomb whose fuse ends right on cycle 1 start, plus a landed armed Spring Plate on spawn.
	var old_bomb: WorldObject = pool.launch(ItemIds.OBJECT_BOMB, 1, 11, bot.center(), Vector2.ZERO, start + cycle - 90, _cfg)
	old_bomb.landed = true
	var old_plate: WorldObject = pool.launch(ItemIds.OBJECT_PLATE, 1, 11, Vector2(500.0, 522.0), Vector2.ZERO, start + 10, _cfg)
	old_plate.landed = true
	old_plate.arm_tick = start + 25
	# Bot throws its fresh cycle-1 bomb on the cycle-boundary tick.
	bot.input.gadget = true
	bot.input.aim = Vector2.RIGHT
	for slot: WorldObject in pool.slots():
		slot._rollback_tick(dt, start + cycle, true)
	bot.gadgets._rollback_tick(dt, start + cycle, true)
	var hits: Array[Hit] = []
	GadgetRules.collect(start + cycle, [bot], pool, pool.solids, _cfg, hits)
	var new_bomb: WorldObject = pool.slots()[pool.slot_range(ItemIds.OBJECT_BOMB, 0, _cfg).x]
	_check(hits.is_empty() and not old_bomb.active and not old_plate.active,
		"cycle-0 bomb and plate do not hit or launch freshly respawned bot on cycle start (hits=%d)" % hits.size())
	_check(new_bomb.active and new_bomb.spawn_tick == start + cycle,
		"gadget thrown on cycle boundary tick is not wiped by cycle reset")

	# Stall skipping the exact cycle-2 boundary tick (resuming at start + 2*cycle + 4) still clears cycle-1 objects.
	var skipped_hits: Array[Hit] = []
	GadgetRules.collect(start + 2 * cycle + 4, [bot], pool, pool.solids, _cfg, skipped_hits)
	_check(not new_bomb.active,
		"prior-cycle object is cleared even when a stall skips the exact boundary tick")

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
	var cooldown_tick: int = spot.ready_tick
	_check(cooldown_tick > cycle, "pickup enters cooldown across cycle boundary")
	bot.global_position = Vector2(-5000.0, -5000.0)
	pickups.resolve(cycle + 3, [bot], _cfg)
	_check(spot.ready_tick <= cycle + 3,
		"pickup resets when boundary tick is skipped (ready_tick=%d, tick=%d)" % [spot.ready_tick, cycle + 3])
	bot.global_position = spot.global_position
	pickups.resolve(cycle + 4, [bot], _cfg)
	var next_ready: int = spot.ready_tick
	pickups.resolve(cycle + 5, [bot], _cfg)
	_check(spot.ready_tick == next_ready and next_ready > cycle + 5,
		"pickup taken in new cycle keeps its cooldown")
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
	_check(wired, "pickups reset on server start/stop and client start/stop")
	for spot: PickupSpot in pickups.spots():
		spot.ready_tick = 5450
	pickups.reset_session()
	var all_zero: bool = true
	for spot: PickupSpot in pickups.spots():
		all_zero = all_zero and spot.ready_tick == 0
	_check(all_zero, "reset_session clears stale pickup ready_tick values from a previous session")
	pickups.free()

func _test_hud_resize_and_zero_max_health() -> void:
	var bot: Bot = BOT_SCENE.instantiate() as Bot
	add_child(bot)
	var hud: Hud = Hud.new()
	hud.size = Vector2(1280.0, 720.0)
	add_child(hud)
	hud.bot = bot
	await get_tree().process_frame
	await get_tree().process_frame
	var draws_before: int = hud.draw_count
	hud.size = Vector2(1600.0, 720.0)
	await get_tree().process_frame
	_check(hud.draw_count > draws_before, "HUD redraws when resized while bot state is unchanged")
	hud.free()
	bot.free()

func _test_touch_flick_updates_aim_while_past_ring() -> void:
	var touch: TouchControls = TouchControls.new()
	touch.size = Vector2(1280.0, 720.0)
	add_child(touch)
	var origin: Vector2 = Vector2(900.0, 500.0)
	var dist: float = _cfg.stick_radius_px * (_cfg.fire_ring_fraction + 0.15)
	InputActions.pending_touch_fire_aim = Vector2.ZERO
	touch._touch(1, origin, true)
	touch._drag(1, origin + Vector2(dist, 0.0))
	touch._drag(1, origin + Vector2(0.0, -dist))
	touch._touch(1, origin + Vector2(0.0, -dist), false)
	var captured: Vector2 = InputActions.pending_touch_fire_aim
	_check(captured.y < -0.5 and absf(captured.x) < 0.2,
		"quick flick curving past the fire ring keeps latest aim direction (got %s)" % [captured])
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
		"oversized-packet warnings are rate-limited to at most 1 per second per peer (got %d for 20 packets)" % _size_warnings.count)
	NetworkSynchronizationServer.erase_peer(peer_id)
	_check(not NetworkSynchronizationServer._last_size_warning_msec.has(peer_id),
		"erase_peer clears oversized-packet warning timestamp for disconnected peer")

func _test_netfox_bitset_and_redundant_bounds() -> void:
	var bit_buf: StreamPeerBuffer = StreamPeerBuffer.new()
	var raw_bits: PackedByteArray = PackedByteArray()
	raw_bits.resize(4096)
	raw_bits.fill(0x80)
	bit_buf.data_array = raw_bits
	var decoded: Variant = NetworkSchemas._varbits().decode_limited(bit_buf, 64)
	_check(decoded == null and bit_buf.get_position() <= 10,
		"variable bitset decode_limited stops at max_bits bytes (pos=%d)" % bit_buf.get_position())

	var red: _RedundantSnapshotSerializer = _RedundantSnapshotSerializer.new(_NetworkSchema.new())
	var zero_buf: StreamPeerBuffer = StreamPeerBuffer.new()
	var zeros: PackedByteArray = PackedByteArray()
	zeros.resize(2048)
	zeros.fill(0)
	zero_buf.data_array = zeros
	var snaps: Array[_Snapshot] = red.read_from(2, _PropertyPool.new(), zero_buf, true)
	_check(snaps.is_empty(), "zero-filled redundant input packet yields 0 snapshots (got %d)" % snaps.size())

func _test_netfox_sanitize_and_sparse_bounds() -> void:
	var bot: Bot = BOT_SCENE.instantiate() as Bot
	bot.set_multiplayer_authority(1)
	add_child(bot)
	var snap: _Snapshot = _Snapshot.new(10)
	snap.set_property(bot, ^":global_position", Vector2(999.0, 999.0))
	snap.set_auth(bot, true)
	snap.sanitize(2)
	_check(snap.is_empty() and not snap.is_auth(bot), "sanitize clears both data and auth flag")

	var pool: _PropertyPool = _PropertyPool.new()
	pool.add(bot, ^":global_position")
	NetworkIdentityServer.register_node(bot)
	var sparse: _SparseSnapshotSerializer = _SparseSnapshotSerializer.new(_NetworkSchema.new())
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	buf.put_u32(10)
	NetworkSchemas._netref().encode(_NetworkIdentityReference.of_full_name(str(bot.get_path())), buf)
	NetworkSchemas.varuint().encode(0, buf)
	buf.put_u8(0x02)
	buf.seek(0)
	var parsed: _Snapshot = sparse.read_from(1, pool, buf, true)
	_check(parsed.is_empty(), "sparse diff with out-of-range changed-bits index returns empty snapshot without error")
	NetworkIdentityServer.deregister_node(bot)
	bot.free()
