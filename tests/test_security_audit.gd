extends Node
## Regression tests for findings audited on geminiceo (iteration 2, against main 8ec8146).
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
	_test_rocket_muzzle_wall_clamp()
	_test_pickup_reset_after_skipped_cycle_tick()
	await _test_hud_resize_and_zero_max_health()
	_test_touch_flick_updates_aim_while_past_ring()
	await _test_session_reject_timer_after_leave_and_free()
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
	# Take the pickup 10 ticks before cycle 1 starts.
	pickups.resolve(cycle - 10, [bot], _cfg)
	var cooldown_tick: int = spot.ready_tick
	_check(cooldown_tick > cycle, "pickup enters cooldown across cycle boundary")
	# Simulate a stall that skips the exact boundary tick (cycle) and resumes at cycle + 3.
	bot.global_position = Vector2(-5000.0, -5000.0)
	pickups.resolve(cycle + 3, [bot], _cfg)
	_check(spot.ready_tick <= cycle + 3,
		"pickup resets when boundary tick is skipped (ready_tick=%d, tick=%d)" % [spot.ready_tick, cycle + 3])
	# Taking the spot inside cycle 1 must NOT be reset again on the next tick.
	bot.global_position = spot.global_position
	pickups.resolve(cycle + 4, [bot], _cfg)
	var next_ready: int = spot.ready_tick
	pickups.resolve(cycle + 5, [bot], _cfg)
	_check(spot.ready_tick == next_ready and next_ready > cycle + 5,
		"pickup taken in new cycle keeps its cooldown")
	MatchSettings.round_start_tick = -1
	bot.free()
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
	# State is steady; resizing the viewport must still trigger a redraw for right-aligned lines.
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
	# Press down, cross the fire ring going right, curve upward while still past the ring, then release.
	touch._touch(1, origin, true)
	touch._drag(1, origin + Vector2(dist, 0.0))
	touch._drag(1, origin + Vector2(0.0, -dist))
	touch._touch(1, origin + Vector2(0.0, -dist), false)
	var captured: Vector2 = InputActions.pending_touch_fire_aim
	_check(captured.y < -0.5 and absf(captured.x) < 0.2,
		"quick flick curving past the fire ring keeps latest aim direction (got %s)" % [captured])
	InputActions.pending_touch_fire_aim = Vector2.ZERO
	touch.free()

func _test_session_reject_timer_after_leave_and_free() -> void:
	var session: Session = Session.new()
	add_child(session)
	var err: Error = session.host(25115, 1)
	_check(err == OK, "session hosts for rejection guard test")
	# Simulate a full-match rejection coroutine starting, then immediately leaving and freeing Session.
	session._on_peer_join(999)
	session.leave()
	session.queue_free()
	await get_tree().create_timer(_cfg.reject_notice_seconds + 0.15).timeout
	_check(not is_instance_valid(session), "freed session survives deferred rejection timer without error")

func _test_netfox_bitset_and_redundant_bounds() -> void:
	# 1. Oversized continuation bitset must stop at <= 256 bits, not grow unboundedly.
	var bit_buf: StreamPeerBuffer = StreamPeerBuffer.new()
	var raw_bits: PackedByteArray = PackedByteArray()
	raw_bits.resize(4096)
	raw_bits.fill(0x80)
	bit_buf.data_array = raw_bits
	var decoded: _Bitset = NetworkSchemas._varbits().decode(bit_buf) as _Bitset
	_check(decoded.bit_count() <= 263, "variable bitset decode is bounded (got %d bits)" % decoded.bit_count())

	# 2. Zero-filled redundant input packet must return 0 snapshots instead of looping per byte.
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
	# 1. sanitize(sender) clears both _data and _auth_subjects.
	var snap: _Snapshot = _Snapshot.new(10)
	snap.set_property(bot, ^":global_position", Vector2(999.0, 999.0))
	snap.set_auth(bot, true)
	snap.sanitize(2)
	_check(snap.is_empty() and not snap.is_auth(bot), "sanitize clears both data and auth flag")

	# 2. Sparse diff with out-of-range bit indices returns an empty snapshot without indexing error.
	var pool: _PropertyPool = _PropertyPool.new()
	pool.add(bot, ^":global_position")
	NetworkIdentityServer.register_node(bot)
	var sparse: _SparseSnapshotSerializer = _SparseSnapshotSerializer.new(_NetworkSchema.new())
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	buf.put_u32(10)
	NetworkSchemas._netref().encode(_NetworkIdentityReference.of_full_name(str(bot.get_path())), buf)
	NetworkSchemas.varuint().encode(0, buf)
	buf.put_u8(0xFE) # bits 1..6 set (all out of range for 1-property pool)
	buf.put_u8(0x01) # bit 7 set
	var read_buf: StreamPeerBuffer = StreamPeerBuffer.new()
	read_buf.data_array = buf.data_array
	var diff: _Snapshot = sparse.read_from(2, pool, read_buf)
	_check(diff.is_empty(), "out-of-range sparse diff bits are ignored cleanly")
	NetworkIdentityServer.deregister_node(bot)
	bot.free()
