extends Node
## Headless test of the presentation layer (task E): the counter watcher rules, the effects the
## counters trigger, the bot picture hiding, the hazard visual, and the rule above all others:
## effects never touch the simulation. It instances scenes/main.tscn offline and drives the
## counters by setting state directly, the way the simulation would. It opens no socket. Run:
##   godot --headless --path . res://tests/test_fx_director.tscn
## Exits 0 when every check passes, 1 otherwise.

const BOT_SCENE: PackedScene = preload("res://scenes/bot.tscn")
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const HazardMath: GDScript = preload("res://hazard/hazard_math.gd")
const TIMEOUT_SECONDS: float = 90.0
const SUSTAINED_SECONDS: float = 3.0
const WARM_UP_SECONDS: float = 1.0
const EPS: float = 0.01

var _cfg: TuningConfig = TuningConfig.get_default()
var _px: float = 0.0
var _failures: int = 0
var _checks: int = 0
var _main: Node
var _director: EffectsDirector
var _bots: Array[Bot] = []
var _events: Array[Array] = []
var _draws: int = 0

func _ready() -> void:
	get_tree().create_timer(TIMEOUT_SECONDS).timeout.connect(_on_timeout)
	_run()

# A script error inside a coroutine stops it silently; without this the run would hang.
func _on_timeout() -> void:
	print("FAIL timeout, the test did not finish")
	get_tree().quit(1)

func _run() -> void:
	_px = _cfg.bot_height_px
	await _setup()
	_test_wiring()
	await _test_watcher_rules()
	await _test_slot_counters()
	await _test_session_marks()
	await _test_blast()
	await _test_hits()
	await _test_freeze_edge()
	await _test_knockout()
	await _test_shots()
	await _test_shot_and_pickup_same_tick()
	await _test_swing()
	await _test_picture_hides()
	await _test_health_bar()
	_test_hazard()
	await _test_process_drives_scan()
	await _test_no_simulation_writes()
	await _test_no_allocation_growth()
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

func _setup() -> void:
	_main = MAIN_SCENE.instantiate()
	add_child(_main)
	await get_tree().process_frame
	_director = _main.get_node("Effects") as EffectsDirector
	# The test drives scan() by hand so every frame is exactly what it says.
	_director.set_process(false)
	_director.effect_triggered.connect(_on_effect)
	_director.scan()

func _on_effect(kind: StringName, source: Node) -> void:
	_events.append([kind, source])

func _count(kind: StringName, source: Node = null) -> int:
	var total: int = 0
	for event: Array in _events:
		if event[0] == kind and (source == null or event[1] == source):
			total += 1
	return total

func _frame() -> void:
	await get_tree().process_frame

func _add_bot(peer: int, slot: int, at: Vector2) -> Bot:
	var bot: Bot = BOT_SCENE.instantiate() as Bot
	bot.peer_id = peer
	bot.slot = slot
	bot.name = "Bot%d" % peer
	bot.position = at
	_main.add_child(bot)
	_bots.append(bot)
	await _frame()
	return bot

func _clear_bots() -> void:
	for bot: Bot in _bots:
		if is_instance_valid(bot):
			bot.free()
	_bots.clear()
	await _frame()
	_events.clear()

func _local_peer() -> int:
	return multiplayer.get_unique_id()

func _settle_shake() -> void:
	var shake: ScreenShake = _director.shake
	var guard: int = 0
	while shake.is_shaking() and guard < 600:
		await _frame()
		guard += 1

# Every registered state property of every bot, slot and pickup spot, plus the round start,
# as bytes, so two snapshots can be compared exactly.
func _snapshot() -> PackedByteArray:
	var values: Array = []
	for node: Node in _main.find_children("*", "RollbackSynchronizer", true, false):
		var sync: RollbackSynchronizer = node as RollbackSynchronizer
		for path: String in sync.state_properties:
			var parts: PackedStringArray = path.split(":")
			var holder: Node = sync.root if parts[0].is_empty() else sync.root.get_node(parts[0])
			values.append(holder.get(parts[1]))
	values.append(MatchSettings.round_start_tick)
	return var_to_bytes(values)

# ---- wiring ----

func _test_wiring() -> void:
	var burst: PartsBurst = _director.burst
	var shake: ScreenShake = _director.shake
	_check(burst.piece_count == _cfg.debris_piece_count and burst.lifetime == _cfg.debris_lifetime and burst.fade_time == _cfg.debris_fade_time, "the parts burst numbers come from the config")
	_check(burst.impulse == _cfg.debris_impulse_px and burst.impulse_variation == _cfg.debris_impulse_variation and burst.spread_degrees == _cfg.debris_spread_degrees and burst.spin == _cfg.debris_spin, "the burst's impulse, spread and spin come from the config")
	_check(burst.piece_size_min == _cfg.debris_size_min_px and burst.piece_size_max == _cfg.debris_size_max_px and burst.bounce == _cfg.debris_bounce and burst.max_debris == _cfg.debris_max, "the burst's sizes, bounce and cap come from the config")
	_check(shake.decay_per_second == _cfg.shake_decay_per_second, "the screen shake decay comes from the config")
	_check(_director.shot_fx().capacity() == 2 * _cfg.fx_pool_size, "the shape rings are sized from the config")

# ---- watcher rules ----

func _test_watcher_rules() -> void:
	var cw: CounterWatch = CounterWatch.new(2)
	_check(cw.step(0, 7) == 0 and cw.mark(0) == 7, "CounterWatch: first sight records and reports nothing")
	_check(cw.step(0, 8) == 1, "CounterWatch: one step up reports one")
	_check(cw.step(1, 3) == 0 and cw.step(0, 8) == 0, "CounterWatch: counters are independent and an unchanged value reports nothing")
	_check(cw.step(0, 5) == 0 and cw.mark(0) == 8, "CounterWatch: a drop reports nothing and keeps the mark")
	_check(cw.step(0, 100) == 92 and cw.mark(0) == 100, "CounterWatch: a big rise is reported in full (there is no catch-up limit)")
	_check(cw.step(5, 1) == 0 and cw.step(0, -4) == 0, "CounterWatch: a bad index or a negative value reports nothing")

	var bot: Bot = await _add_bot(2, 1, Vector2(900.0, 300.0))
	bot.arsenal.shots_fired = 10
	bot.vitals.hits_taken = 4
	bot.vitals.ko_serial = 2
	bot.arsenal.melee_serial = 3
	_director.scan()
	_check(_events.is_empty(), "a node seen for the first time triggers nothing, whatever its counters hold")
	bot.arsenal.shots_fired = 11
	_director.scan()
	_check(_count(&"shot", bot) == 1, "one increase triggers one shot effect")
	bot.arsenal.shots_fired = 14
	_director.scan()
	_check(_count(&"shot", bot) == 4, "an increase of 3 in one frame triggers 3 shot effects")
	bot.arsenal.melee_serial = 6
	_director.scan()
	_check(_count(&"swing", bot) == 3, "an increase of 3 in one frame triggers 3 swings")
	bot.vitals.ko_serial = 5
	bot.vitals.hits_taken = 7
	_director.scan()
	_check(_count(&"knockout", bot) == 1 and _count(&"hit", bot) == 1, "a jump of 3 in a knockout serial or in the hit count triggers once")
	_events.clear()
	bot.arsenal.shots_fired = 12
	_director.scan()
	bot.arsenal.shots_fired = 14
	_director.scan()
	_check(_events.is_empty(), "a drop followed by a return to the same value triggers nothing")
	bot.arsenal.shots_fired = 15
	_director.scan()
	_check(_count(&"shot") == 1, "a rise above the mark after that triggers once")
	bot.arsenal.shots_fired = 10
	_director.scan()
	bot.arsenal.shots_fired = 16
	_director.scan()
	_check(_count(&"shot") == 2, "a drop followed by a rise above the mark triggers once")
	var watched: int = _director.watched_bot_count()
	_bots.erase(bot)
	bot.free()
	await _frame()
	_check(_director.watched_bot_count() == watched - 1, "a removed bot is dropped from the watch list")
	_events.clear()
	var fresh: Bot = await _add_bot(9, 3, Vector2(500.0, 300.0))
	_director.scan()
	_check(_events.is_empty() and _director.watched_bot_count() == watched, "a new bot added after that, with counters at 0, triggers nothing (first sight)")
	fresh.arsenal.shots_fired = 1
	_director.scan()
	_check(_count(&"shot", fresh) == 1, "and its first real increase triggers")
	await _clear_bots()

func _test_slot_counters() -> void:
	var slot: WorldObject = _director.objects.slots()[0]
	var other: WorldObject = _director.objects.slots()[1]
	_check(_count(&"blast") == 0, "the pool's first sight (at start, all counters 0) triggered nothing")
	slot.blasts = 3
	_director.scan()
	_check(_count(&"blast", slot) == 1, "a slot's blasts rising by 3 in one frame triggers one blast effect")
	_events.clear()
	slot.blasts = 1
	_director.scan()
	slot.blasts = 3
	_director.scan()
	_check(_events.is_empty(), "a slot's blasts dropping and returning triggers nothing")
	slot.blasts = 4
	other.blasts = 1
	_director.scan()
	_check(_count(&"blast", slot) == 1 and _count(&"blast", other) == 1, "each slot's blasts are watched on their own")
	slot.blasts = 0
	other.blasts = 0
	_director.scan()
	_events.clear()

# ---- marks do not survive a session ----

func _test_session_marks() -> void:
	_check(NetworkEvents.on_server_start.is_connected(_director.forget_marks) and NetworkEvents.on_server_stop.is_connected(_director.forget_marks) and NetworkEvents.on_client_stop.is_connected(_director.forget_marks) and NetworkEvents.on_client_start.is_connected(_director._on_client_start), "the director forgets its marks when a session starts or stops (all four signals)")
	var slot: WorldObject = _director.objects.slots()[3]
	slot.blasts = 0
	_director.scan()
	for i: int in 20:
		slot.blasts += 1
		_director.scan()
	_check(_count(&"blast", slot) == 20 and slot.blasts == 20, "a session in which slot 3 reaches 20 blasts")
	var bot: Bot = await _add_bot(2, 1, Vector2(900.0, 300.0))
	_director.scan()
	for i: int in 20:
		bot.arsenal.shots_fired += 1
		_director.scan()
	_events.clear()
	NetworkEvents.on_client_stop.emit()
	# A restarted host counts from 0 again.
	slot.blasts = 0
	bot.arsenal.shots_fired = 0
	_director.scan()
	slot.blasts = 1
	bot.arsenal.shots_fired = 1
	_director.scan()
	_check(_count(&"blast", slot) == 1, "after the session ended, the first real blast of the new session (1 against the old mark 20) triggers")
	_check(_count(&"shot", bot) == 1, "and so does a bot's first real shot (1 against its old mark 20)")
	slot.blasts = 0
	await _clear_bots()
	_director.forget_marks()
	_director.scan()
	_events.clear()

# ---- blasts: where the parts go and how the shake falls off ----

func _test_blast() -> void:
	var local: Bot = await _add_bot(_local_peer(), 0, Vector2(600.0, 500.0))
	_director.scan()
	await _settle_shake()
	var slot: WorldObject = _director.objects.slots()[4]
	var shake: ScreenShake = _director.shake
	var range_px: float = _cfg.blast_shake_range_bh * _px
	var strength: float = _cfg.shake_strength_knockout_px
	var known: Array[DebrisPiece] = DebrisPiece.live.duplicate()
	slot.global_position = local.global_position
	slot.blasts += 1
	_director.scan()
	var fresh: Array[DebrisPiece] = _pieces_not_in(known)
	var at_blast: bool = not fresh.is_empty()
	for piece: DebrisPiece in fresh:
		at_blast = at_blast and piece.position.is_equal_approx(slot.global_position)
	_check(fresh.size() == _cfg.debris_piece_count and at_blast, "a blast throws the configured number of parts from the slot's position")
	_check(absf(shake._strength - strength) < EPS, "a blast on top of the local bot shakes at full strength (%.2f)" % shake._strength)
	await _settle_shake()
	slot.global_position = local.global_position + Vector2(range_px * 0.25, 0.0)
	slot.blasts += 1
	_director.scan()
	_check(absf(shake._strength - strength * 0.75) < EPS, "a quarter of the way out the shake is 3/4 of full (%.2f)" % shake._strength)
	await _settle_shake()
	slot.global_position = local.global_position + Vector2(0.0, range_px * 0.5)
	slot.blasts += 1
	_director.scan()
	_check(absf(shake._strength - strength * 0.5) < EPS, "halfway out the shake is half (%.2f)" % shake._strength)
	await _settle_shake()
	slot.global_position = local.global_position + Vector2(range_px * 1.5, 0.0)
	slot.blasts += 1
	_director.scan()
	_check(not shake.is_shaking(), "a blast beyond the range does not shake")
	await _clear_bots()
	slot.global_position = Vector2(300.0, 500.0)
	slot.blasts += 1
	_director.scan()
	_check(not shake.is_shaking(), "with no local bot a blast does not shake")
	slot.blasts = 0
	_director.forget_marks()
	_director.scan()
	await get_tree().create_timer(_cfg.debris_lifetime + 0.5).timeout
	_events.clear()

# ---- the freeze threshold edge ----

func _test_freeze_edge() -> void:
	var at_edge: Bot = await _add_bot(2, 1, Vector2(700.0, 300.0))
	var below: Bot = await _add_bot(3, 2, Vector2(1000.0, 300.0))
	_director.scan()
	at_edge.vitals.last_hit_push = Vector2(_cfg.hit_freeze_min_push, 0.0)
	at_edge.vitals.hits_taken += 1
	below.vitals.last_hit_push = Vector2(_cfg.hit_freeze_min_push - 0.001, 0.0)
	below.vitals.hits_taken += 1
	_director.scan()
	_check(at_edge.visual.hit_freeze.is_frozen(), "a hit exactly at the freeze threshold freezes")
	_check(not below.visual.hit_freeze.is_frozen() and below.visual.hit_flash.is_flashing(), "a hit just below the threshold flashes and does not freeze")
	await _clear_bots()

# ---- hits ----

func _test_hits() -> void:
	var local: Bot = await _add_bot(_local_peer(), 0, Vector2(400.0, 300.0))
	var light: Bot = await _add_bot(_local_peer() + 1, 1, Vector2(800.0, 300.0))
	var heavy: Bot = await _add_bot(_local_peer() + 2, 2, Vector2(1200.0, 300.0))
	_director.scan()
	await _settle_shake()
	var shake: ScreenShake = _director.shake
	light.vitals.last_hit_push = Vector2(_cfg.hit_freeze_min_push * 0.5, 0.0)
	light.vitals.hits_taken += 1
	_director.scan()
	_check(light.visual.hit_flash.is_flashing(), "a light hit flashes the bot's picture")
	_check(not light.visual.hit_freeze.is_frozen(), "a light hit does not freeze it")
	heavy.vitals.last_hit_push = Vector2(0.0, -_cfg.hit_freeze_min_push * 2.0)
	heavy.vitals.hits_taken += 1
	_director.scan()
	_check(heavy.visual.hit_flash.is_flashing(), "a heavy hit flashes the bot's picture")
	_check(heavy.visual.hit_freeze.is_frozen(), "a heavy hit freezes it")
	_check(not shake.is_shaking(), "hits on other players' bots do not shake the screen")
	local.vitals.last_hit_push = Vector2(0.1, 0.0)
	local.vitals.hits_taken += 1
	_director.scan()
	_check(shake.is_shaking(), "a hit on the local player's bot shakes the screen")
	_check(local.visual.hit_flash.is_flashing() and not local.visual.hit_freeze.is_frozen(), "the local bot's light hit flashes and does not freeze")
	await _settle_shake()
	await _clear_bots()

# ---- knockout ----

# The parts made since known was taken (the debris cap may have freed older ones meanwhile).
func _pieces_not_in(known: Array[DebrisPiece]) -> Array[DebrisPiece]:
	var fresh: Array[DebrisPiece] = []
	for piece: DebrisPiece in DebrisPiece.live:
		if not known.has(piece):
			fresh.append(piece)
	return fresh

func _test_knockout() -> void:
	var local: Bot = await _add_bot(_local_peer(), 0, Vector2(400.0, 300.0))
	var victim: Bot = await _add_bot(_local_peer() + 1, 2, Vector2(900.0, 500.0))
	_director.scan()
	await _settle_shake()
	var known: Array[DebrisPiece] = DebrisPiece.live.duplicate()
	victim.vitals.last_hit_push = Vector2(3.0, 0.0)
	victim.vitals.ko_serial += 1
	_director.scan()
	var fresh: Array[DebrisPiece] = _pieces_not_in(known)
	_check(fresh.size() == _cfg.debris_piece_count, "a knockout throws the configured number of parts (%d)" % fresh.size())
	var at_victim: bool = not fresh.is_empty()
	var mean: Vector2 = Vector2.ZERO
	for piece: DebrisPiece in fresh:
		at_victim = at_victim and piece.position.is_equal_approx(victim.global_position)
		mean += piece.linear_velocity
	_check(at_victim, "the parts start at the knocked-out bot")
	_check(mean.x > absf(mean.y), "the parts are thrown along the last hit push")
	_check(not fresh.is_empty() and fresh[0]._color == BotVisual.body_color(victim.slot, _cfg), "the parts are in the bot's colour")
	_check(_director.shake.is_shaking(), "a knockout shakes the screen for everyone (a bot that is not the local one)")
	_check(local != null, "the local bot exists in this check")
	await _settle_shake()
	known = DebrisPiece.live.duplicate()
	victim.vitals.last_hit_push = Vector2.ZERO
	victim.vitals.ko_serial += 1
	_director.scan()
	var up: Vector2 = Vector2.ZERO
	for piece: DebrisPiece in _pieces_not_in(known):
		up += piece.linear_velocity
	_check(up.y < 0.0 and absf(up.y) > absf(up.x), "with no push the parts go up")
	await _settle_shake()
	await _clear_bots()

# ---- shots and the tracer ----

func _shoot(bot: Bot, dir: Vector2) -> int:
	bot.arsenal.last_shot_weapon = bot.arsenal.active_weapon()
	bot.arsenal.shot_dir = dir
	bot.arsenal.shots_fired += 1
	_director.scan()
	return _director.shot_fx().last_shot_index()

func _test_shots() -> void:
	var fx: ShotFx = _director.shot_fx()
	var bot: Bot = await _add_bot(2, 1, Vector2(14.0, 7.0) * _px)
	_director.scan()
	await _frame()
	await _frame()
	fx.draw.connect(func() -> void: _draws += 1)
	var draws_before: int = _draws
	var index: int = _shoot(bot, Vector2.RIGHT)
	await _frame()
	# By the time the next frame starts the shot was drawn twice: at the end of the frame that
	# triggered it and at the end of the next. Without the redraw request at trigger time the
	# first of the two is missing.
	_check(_draws == draws_before + 2, "a shot is drawn on the very frame it was triggered, not one frame later (%d draws)" % (_draws - draws_before))
	var range_px: float = _cfg.weapon_stats(ItemIds.RIVET_GUN).range_bh * _px
	_check(fx.shot_has_tracer(index), "the rivet gun gets a tracer")
	_check(fx.shot_end(index).distance_to(bot.global_position + Vector2.RIGHT * range_px) < EPS, "a tracer through open space ends at the weapon's range")
	_check(fx.shot_start(index).distance_to(bot.global_position + Vector2.RIGHT * _cfg.muzzle_offset_bh * _px) < EPS, "the muzzle flash sits at the muzzle")
	_check(fx.active_count() == 1, "one shot is one flash and tracer")
	await get_tree().create_timer(_cfg.tracer_seconds + _cfg.muzzle_flash_seconds + 0.3).timeout
	_check(fx.active_count() == 0, "the tracer and flash fade away")

	# The tracer length is the weapon's own range: shorten the bolt thrower's for this check.
	var bolt: WeaponStats = _cfg.weapon_stats(ItemIds.BOLT_THROWER)
	var saved_range: float = bolt.range_bh
	bolt.range_bh = 6.0
	bot.arsenal.active_slot = 1
	bot.arsenal.picked_weapon = ItemIds.BOLT_THROWER
	index = _shoot(bot, Vector2.RIGHT)
	_check(fx.shot_has_tracer(index) and fx.shot_end(index).distance_to(bot.global_position + Vector2.RIGHT * 6.0 * _px) < EPS, "the bolt thrower gets a tracer as long as its own range")
	bolt.range_bh = saved_range

	for weapon: int in [ItemIds.SCRAP_BLASTER, ItemIds.ROCKET_TUBE]:
		bot.arsenal.picked_weapon = weapon
		index = _shoot(bot, Vector2.RIGHT)
		_check(not fx.shot_has_tracer(index) and fx.shot_start(index).distance_to(bot.global_position + Vector2.RIGHT * _cfg.muzzle_offset_bh * _px) < EPS, "weapon %d gets a muzzle flash and no tracer" % weapon)
	bot.arsenal.active_slot = 0
	bot.arsenal.picked_weapon = ItemIds.NONE

	bot.global_position = Vector2(20.0, 15.45) * _px
	index = _shoot(bot, Vector2.LEFT)
	var pillar_face: float = 12.0 * _px
	_check(absf(fx.shot_end(index).x - pillar_face) < EPS and absf(fx.shot_end(index).y - bot.global_position.y) < EPS, "a tracer ends at the first wall in its path (the left pillar's face)")
	index = _shoot(bot, Vector2.RIGHT)
	_check(absf(fx.shot_end(index).x - 28.0 * _px) < EPS, "and the right pillar's face the other way")
	bot.aim_dir = Vector2.LEFT
	index = _shoot(bot, Vector2.ZERO)
	_check(absf(fx.shot_end(index).x - pillar_face) < EPS, "with no shot direction the aim direction is used")
	await _clear_bots()

func _test_shot_and_pickup_same_tick() -> void:
	var resolver: CombatResolver = _main.get_node("Resolver") as CombatResolver
	var pickups: Pickups = resolver.pickups
	var spot: PickupSpot = pickups.spots()[pickups.layout.pickup_items.find(ItemIds.BOLT_THROWER)]
	var bot: Bot = await _add_bot(2, 1, spot.global_position)
	bot.arsenal.give_weapon(ItemIds.ROCKET_TUBE, _cfg)
	_director.scan()
	bot.input.aim = Vector2.UP
	bot.input.fire = true
	bot.arsenal._rollback_tick(1.0 / float(_cfg.tick_rate), 1, true)
	resolver.resolve(1, [bot])
	_check(bot.arsenal.fired_at(1) and bot.arsenal.active_weapon() == ItemIds.BOLT_THROWER, "the bot fires its rocket and picks up the bolt thrower on the same tick")
	_director.scan()
	var fx: ShotFx = _director.shot_fx()
	_check(_count(&"shot", bot) == 1 and not fx.shot_has_tracer(fx.last_shot_index()), "the rocket gets no tracer even after the same-tick bolt thrower pickup")
	spot.ready_tick = 0
	await _clear_bots()

func _test_swing() -> void:
	var fx: ShotFx = _director.shot_fx()
	await get_tree().create_timer(_cfg.melee_arc_seconds + 0.3).timeout
	var bot: Bot = await _add_bot(2, 1, Vector2(900.0, 300.0))
	_director.scan()
	bot.aim_dir = Vector2.UP
	await _frame()
	await _frame()
	var draws_before: int = _draws
	bot.arsenal.melee_serial += 1
	_director.scan()
	await _frame()
	_check(_draws == draws_before + 2, "a swing is drawn on the frame it was triggered too (%d draws)" % (_draws - draws_before))
	_check(_count(&"swing", bot) == 1 and fx.active_count() == 1, "a swing draws one arc")
	_check(absf(fx.swing_radius - _cfg.melee_range * _px) < EPS and absf(fx.swing_span - deg_to_rad(_cfg.melee_arc_degrees)) < EPS, "the arc uses the config's melee range and angle")
	await get_tree().create_timer(_cfg.melee_arc_seconds + 0.3).timeout
	_check(fx.active_count() == 0, "the arc fades away")
	bot.arsenal.shot_dir = Vector2.LEFT
	bot.arsenal.melee_serial += 1
	_director.scan()
	_check(absf(fx.last_swing_angle() - PI) < EPS, "a swing uses the direction the weapons task stored in shot_dir")
	bot.arsenal.shot_dir = Vector2.ZERO
	bot.arsenal.melee_serial += 1
	_director.scan()
	_check(absf(fx.last_swing_angle() - (-PI / 2.0)) < EPS, "and the aim direction when shot_dir is empty")
	await _clear_bots()

# ---- the picture ----

func _test_picture_hides() -> void:
	var bot: Bot = await _add_bot(2, 1, Vector2(900.0, 300.0))
	_check(bot.visual.visible, "a bot's picture is shown while it is up")
	bot.vitals.knocked_out = true
	await _frame()
	_check(not bot.visual.visible, "the picture is hidden while the bot is knocked out")
	bot.vitals.knocked_out = false
	await _frame()
	_check(bot.visual.visible, "and shown again on respawn")
	await _clear_bots()

# ---- the health bar ----

func _test_health_bar() -> void:
	var hold: float = _cfg.health_bar_hold_seconds
	var bar: HealthBarState = HealthBarState.new()
	bar.observe(100.0, hold, false)
	_check(not bar.showing(), "health bar: hidden at first sight")
	bar.observe(100.0, hold, false)
	bar.tick(0.5)
	bar.observe(100.0, hold, false)
	_check(not bar.showing(), "health bar: an unchanged value never shows it")
	bar.observe(80.0, hold, false)
	_check(bar.showing(), "health bar: shown when the value changes")
	bar.tick(hold - 0.1)
	_check(bar.showing(), "health bar: still shown just before the hold ends")
	bar.tick(0.2)
	_check(not bar.showing(), "health bar: hidden just after the hold ends")
	bar.observe(60.0, hold, false)
	bar.tick(hold - 0.2)
	bar.observe(40.0, hold, false)
	bar.tick(0.5)
	_check(bar.showing(), "health bar: a second change restarts the hold")
	bar.tick(hold)
	_check(not bar.showing(), "health bar: and it ends a full hold after that change")
	bar.observe(20.0, hold, false)
	bar.observe(0.0, hold, true)
	_check(not bar.showing(), "health bar: hidden while knocked out")
	bar.observe(0.0, hold, true)
	bar.observe(100.0, hold, false)
	_check(bar.showing(), "health bar: a respawn back to full shows it")
	bar.reset()
	_check(not bar.showing(), "health bar: a reset hides it")
	bar.observe(50.0, hold, false)
	_check(not bar.showing(), "health bar: and the first value after a reset is a first sight, not a change")
	bar.observe(50.0, hold, false)
	bar.observe(50.0, hold, false)
	bar.observe(50.0, hold, false)
	_check(not bar.showing(), "health bar: nothing changed, nothing shown")
	# A value that moves and comes back between two frames is never seen by the frame comparison.
	_check(is_equal_approx(HealthBarState.fraction(100.0, 100.0), 1.0) and is_equal_approx(HealthBarState.fraction(50.0, 100.0), 0.5) and HealthBarState.fraction(0.0, 100.0) == 0.0 and HealthBarState.fraction(150.0, 100.0) == 1.0 and HealthBarState.fraction(-5.0, 100.0) == 0.0, "health bar: fill fraction at full, half, zero and out of range")
	var low: float = _cfg.low_health_threshold
	_check(not HealthBarState.is_low(low + 0.01, _cfg.low_health_threshold) and HealthBarState.is_low(low, _cfg.low_health_threshold) and HealthBarState.is_low(0.0, _cfg.low_health_threshold) and not HealthBarState.is_low(_cfg.max_health, _cfg.low_health_threshold), "health bar: low-health colour at the threshold and below, not above")

	# Through the director: first sight, change, knocked out, session reset, and every bot alike.
	var bot: Bot = await _add_bot(2, 1, Vector2(900.0, 300.0))
	var dummy: Bot = await _add_bot(Bot.DUMMY_PEER, _cfg.max_players, Vector2(1200.0, 300.0))
	_director.scan()
	_check(not bot.visual.health_bar.showing() and not dummy.visual.health_bar.showing(), "director: a bot seen for the first time has no bar")
	bot.vitals.health = _cfg.max_health - 10.0
	dummy.vitals.health = _cfg.max_health - 10.0
	_director.scan()
	_check(bot.visual.health_bar.showing() and dummy.visual.health_bar.showing(), "director: a health change shows the bar, for the dummy and for a player alike")
	bot.vitals.knocked_out = true
	_director.scan()
	_check(not bot.visual.health_bar.showing() and dummy.visual.health_bar.showing(), "director: a knocked-out bot's bar is hidden, the other stays")
	bot.vitals.knocked_out = false
	bot.vitals.health = _cfg.max_health
	_director.scan()
	_check(bot.visual.health_bar.showing(), "director: the respawn at full health shows the bar again")
	_director.forget_marks()
	_check(not bot.visual.health_bar.showing() and not dummy.visual.health_bar.showing(), "director: a session start or stop hides every bar")
	_director.scan()
	_check(not bot.visual.health_bar.showing(), "director: and the first value after it is a first sight")
	# The hold runs on the frame clock in the Visual.
	bot.vitals.health = 10.0
	_director.scan()
	var frames: int = 0
	while bot.visual.health_bar.showing() and frames < 600:
		await _frame()
		frames += 1
	_check(frames > 0 and frames < 600 and not bot.visual.health_bar.showing(), "director: the bar goes away by itself after the hold (%d frames)" % frames)
	# A re-simulation: inside one rollback tick and its loop the health moves and then comes back,
	# the way netfox's replay leaves a value before the end-of-loop restore puts the display state
	# back. The bar is fed once per frame from the displayed value, so it never sees the dip. (The
	# signals are emitted in the order netfox does: record the tick, end the loop, then restore.)
	_director.scan()
	var shown: float = bot.vitals.health
	bot.vitals.health = shown - 30.0
	NetworkRollback.on_record_tick.emit(NetworkTime.tick)
	NetworkRollback.after_loop.emit()
	bot.vitals.health = shown
	_director.scan()
	_check(not bot.visual.health_bar.showing(), "director: health that dips and comes back inside one rollback tick and loop never shows the bar")
	bot.vitals.health = shown - 30.0
	_director.scan()
	_check(bot.visual.health_bar.showing(), "director: and the same dip that is still there on the frame does show it")
	await _clear_bots()

# ---- the hazard ----

func _test_hazard() -> void:
	var hv: HazardVisual = _director.hazard_visual
	var layout: ArenaLayout = _director.layout
	_check(hv.floor_y == layout.bounds.end.y * _px and hv.arena_width == layout.bounds.size.x * _px and hv.position.x == layout.bounds.position.x * _px, "the hazard visual is set up from the layout (floor, width, left edge)")
	var start: int = 100
	MatchSettings.round_start_tick = start
	var top_y: float = (layout.bounds.position.y + layout.hazard_top) * _px
	var cycle: int = roundi(_cfg.hazard_cycle_time * float(_cfg.tick_rate))
	var offsets: Array[int] = [0, 1, 899, 900, 901, 1000, 1125, 1300, 1349, cycle, cycle + 901, 2 * cycle + 1125]
	var all_match: bool = true
	var rises: bool = false
	for offset: int in offsets:
		var tick: int = start + offset
		_director.update_hazard(tick)
		var expected: float = HazardMath.surface_y(MatchSettings.hazard_ticks(tick), _cfg.tick_rate, _cfg.hazard_start_time, _cfg.hazard_cap_time, hv.floor_y, top_y)
		var top_edge: float = hv.position.y if hv.visible else hv.floor_y
		var bottom_edge: float = hv.position.y + hv.size.y if hv.visible else hv.floor_y
		if absf(top_edge - expected) > EPS or absf(bottom_edge - hv.floor_y) > EPS:
			all_match = false
			print("  mismatch at tick offset %d: top %.3f, HazardMath %.3f" % [offset, top_edge, expected])
		rises = rises or hv.visible
	_check(all_match, "the hazard visual's top edge equals HazardMath.surface_y at %d ticks across the cycle" % offsets.size())
	_check(rises, "the metal is on screen once it has started to rise")
	_director.update_hazard(start + 1125)
	_check(absf(hv.position.y - (hv.floor_y + top_y) * 0.5) < EPS, "halfway through the rise the top edge is halfway up (independent figure)")
	_director.update_hazard(start + 600)
	_check(not hv.visible, "no metal on screen before it starts to rise")
	_director.update_hazard(start - 50)
	_check(not hv.visible, "no metal on screen before the round starts")
	# The top comes from ArenaLayout.hazard_top_px (it counts from the top of the interior), not
	# from hazard_top alone: shift the interior down by two bot heights, keeping the same floor.
	var shifted: ArenaLayout = layout.duplicate() as ArenaLayout
	shifted.bounds = Rect2(layout.bounds.position.x, 2.0, layout.bounds.size.x, layout.bounds.end.y - 2.0)
	_director.layout = shifted
	_director.update_hazard(start + 1349)
	var expected_shifted: float = HazardMath.surface_y(MatchSettings.hazard_ticks(start + 1349), _cfg.tick_rate, _cfg.hazard_start_time, _cfg.hazard_cap_time, shifted.hazard_floor_px(_px), shifted.hazard_top_px(_px))
	_check(absf(hv.position.y - expected_shifted) < EPS and absf(shifted.hazard_top_px(_px) - (2.0 + layout.hazard_top) * _px) < EPS, "the hazard's top comes from the layout's own helper (top edge %.2f, expected %.2f)" % [hv.position.y, expected_shifted])
	_director.layout = layout
	MatchSettings.round_start_tick = -1

# ---- _process drives it ----

func _test_process_drives_scan() -> void:
	var bot: Bot = await _add_bot(2, 1, Vector2(900.0, 300.0))
	_director.scan()
	_director.set_process(true)
	bot.arsenal.melee_serial += 1
	await _frame()
	await _frame()
	_director.set_process(false)
	_check(_count(&"swing", bot) == 1, "the director triggers from its own _process, once")
	await _clear_bots()

# ---- presentation never touches the simulation ----

func _fire_everything(bots: Array[Bot], frame: int) -> void:
	for bot: Bot in bots:
		# The bodies move every frame, as in a match: a freeze that held the body instead of its
		# picture would put the old position back and show up as a difference.
		bot.global_position += Vector2(9.0, -5.0) if frame % 8 < 4 else Vector2(-9.0, 5.0)
		bot.velocity = Vector2(float(frame), -float(frame))
		bot.vitals.last_hit_push = Vector2(0.0, -4.0) if frame % 2 == 0 else Vector2(0.2, 0.0)
		bot.vitals.last_hit_damage = 7.0
		bot.vitals.hits_taken += 1
		bot.vitals.ko_serial += 1
		bot.arsenal.shot_dir = Vector2.from_angle(float(frame) * 0.3)
		bot.arsenal.shots_fired += 1
		bot.arsenal.melee_serial += 1
		bot.aim_dir = Vector2.from_angle(float(frame) * 0.2)
	for slot: WorldObject in _director.objects.slots():
		slot.blasts += 1

func _test_no_simulation_writes() -> void:
	var made: Array[Bot] = []
	for i: int in 4:
		made.append(await _add_bot(_local_peer() + i, i, Vector2(300.0 + 250.0 * float(i), 400.0)))
	_director.scan()
	var frames: int = 120
	var identical: int = 0
	for frame: int in frames:
		_fire_everything(made, frame)
		var before: PackedByteArray = _snapshot()
		_director.scan()
		await _frame()
		var after: PackedByteArray = _snapshot()
		if before == after:
			identical += 1
	_check(identical == frames, "every registered state property of every (moving) bot, slot and spot is identical before and after %d frames of effects (%d identical)" % [frames, identical])
	_check(_count(&"hit") >= frames * 4 and _count(&"knockout") >= frames * 4 and _count(&"shot") >= frames * 4 and _count(&"swing") >= frames * 4, "every effect fired in those frames (hits %d, knockouts %d, shots %d, swings %d)" % [_count(&"hit"), _count(&"knockout"), _count(&"shot"), _count(&"swing")])
	_check(_count(&"blast") >= frames, "and blasts too (%d)" % _count(&"blast"))
	_check(DebrisPiece.live.size() <= _cfg.debris_max, "the parts stay under the debris cap (%d of %d)" % [DebrisPiece.live.size(), _cfg.debris_max])
	await _settle_shake()
	await _clear_bots()
	await get_tree().create_timer(_cfg.debris_lifetime + 0.5).timeout

# ---- no per-frame allocation ----

func _test_no_allocation_growth() -> void:
	var made: Array[Bot] = []
	for i: int in 4:
		made.append(await _add_bot(_local_peer() + i, i, Vector2(300.0 + 250.0 * float(i), 400.0)))
	_director.scan()
	var fx: ShotFx = _director.shot_fx()
	var capacity: int = fx.capacity()
	var started: int = Time.get_ticks_msec()
	var nodes_warm: int = -1
	var objects_warm: int = -1
	var frames: int = 0
	var peak_active: int = 0
	while Time.get_ticks_msec() - started < int((WARM_UP_SECONDS + SUSTAINED_SECONDS) * 1000.0):
		for bot: Bot in made:
			bot.vitals.last_hit_push = Vector2(0.0, -4.0) if frames % 2 == 0 else Vector2(0.2, 0.0)
			bot.vitals.hits_taken += 1
			bot.arsenal.shot_dir = Vector2.from_angle(float(frames) * 0.3)
			bot.arsenal.shots_fired += 1
			bot.arsenal.melee_serial += 1
		_director.scan()
		await _frame()
		frames += 1
		peak_active = maxi(peak_active, fx.active_count())
		if nodes_warm < 0 and Time.get_ticks_msec() - started >= int(WARM_UP_SECONDS * 1000.0):
			nodes_warm = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
			objects_warm = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var nodes_end: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var objects_end: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	_check(frames > 60, "the sustained run covered %d frames" % frames)
	_check(nodes_end == nodes_warm, "node count is flat over %.0f seconds of sustained shots, swings and hits (%d, then %d)" % [SUSTAINED_SECONDS, nodes_warm, nodes_end])
	_check(objects_end == objects_warm, "engine object count is flat over the same run (%d, then %d)" % [objects_warm, objects_end])
	_check(fx.capacity() == capacity and peak_active <= capacity, "the shape rings never grow (capacity %d, most showing %d)" % [fx.capacity(), peak_active])
	await _clear_bots()
