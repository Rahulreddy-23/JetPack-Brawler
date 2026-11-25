extends Node
## Headless test of task D: the object pool's launch, targets, deflect and destroy; the slot's
## motion; GadgetRules (gadget use, rocket contact, blasts, plate launches, the cycle reset);
## BotGadgets. It opens no socket. Task B's rules are not involved: it asserts on the Hit list
## and on slot state. Run:
##   godot --headless --path . res://tests/test_world_objects.tscn
## Exits 0 when every check passes, 1 otherwise.

const BOT_SCENE: PackedScene = preload("res://scenes/bot.tscn")
const TIMEOUT_SECONDS: float = 60.0
const SLOT_PROPS: Array[String] = ["active", "kind", "owner_peer", "global_position", "velocity", "spawn_tick", "arm_tick", "fuse_tick", "explode_tick", "landed", "launches", "blasts"]
const GADGET_PROPS: Array[String] = ["gadget_a", "gadget_b", "gadget_ready_tick", "last_gadget_tick", "last_gadget_id", "gadget_dir", "gadget_serial"]
const FAR: Rect2 = Rect2(-100000.0, -100000.0, 200000.0, 200000.0)

var _cfg: TuningConfig = TuningConfig.get_default()
var _dt: float = 0.0
var _px: float = 0.0
var _failures: int = 0
var _checks: int = 0
var _nodes: Array[Node] = []
var _pool: WorldObjects = null
var _bots: Array[Bot] = []

func _ready() -> void:
	get_tree().create_timer(TIMEOUT_SECONDS).timeout.connect(_on_timeout)
	_run()

func _on_timeout() -> void:
	print("FAIL timeout, the test did not finish")
	get_tree().quit(1)

func _run() -> void:
	_dt = 1.0 / float(_cfg.tick_rate)
	_px = _cfg.bot_height_px
	await _test_config()
	await _test_launch_slots()
	await _test_rocket_wall()
	await _test_rocket_range()
	await _test_rocket_sweep()
	await _test_rocket_bot_before_stop()
	await _test_rocket_range_without_speed()
	await _test_launch_inside_solid()
	await _test_narrow_column()
	await _test_push_out_passes()
	await _test_grown_cache()
	await _test_session_reset()
	await _test_teleport_and_colour()
	await _test_bomb_fuse_and_bounce()
	await _test_bounds_and_inactive()
	await _test_sending()
	await _test_blast_numbers()
	await _test_rocket_contact_and_arming()
	await _test_blast_pushes_objects()
	await _test_plates()
	await _test_targets()
	await _test_deflect_and_destroy()
	await _test_gadgets()
	await _test_cycle_reset()
	await _test_rerun_idempotent()
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

func _near(got: float, want: float, tol: float, label: String) -> void:
	_check(absf(got - want) <= tol, "%s (got %.4f, want %.4f +-%.4f)" % [label, got, want, tol])

func _near_v(got: Vector2, want: Vector2, tol: float, label: String) -> void:
	_check(got.distance_to(want) <= tol, "%s (got %s, want %s)" % [label, got, want])

# A fresh pool with the given solids and no bots.
func _begin(solids: Array[Rect2] = []) -> void:
	for node: Node in _nodes:
		node.free()
	_nodes.clear()
	_bots.clear()
	_pool = WorldObjects.new()
	add_child(_pool)
	_nodes.append(_pool)
	_pool.solids = solids
	_pool.bounds_px = FAR
	await get_tree().process_frame

func _add_bot(peer: int, slot: int, pos: Vector2) -> Bot:
	var bot: Bot = BOT_SCENE.instantiate() as Bot
	bot.peer_id = peer
	bot.slot = slot
	bot.position = pos
	add_child(bot)
	_nodes.append(bot)
	_bots.append(bot)
	return bot

func _sorted_bots() -> Array[Bot]:
	var result: Array[Bot] = _bots.duplicate()
	result.sort_custom(func(a: Bot, b: Bot) -> bool: return a.peer_id < b.peer_id)
	return result

# One tick the way the game runs it: slots first (Objects is before Bots in main.tscn), then
# each bot's gadgets, then the resolver's gadget rules.
func _tick(tick: int) -> Array[Hit]:
	for slot: WorldObject in _pool.slots():
		slot._rollback_tick(_dt, tick, true)
	for bot: Bot in _bots:
		bot.gadgets._rollback_tick(_dt, tick, true)
	var hits: Array[Hit] = []
	GadgetRules.collect(tick, _sorted_bots(), _pool, _pool.solids, _cfg, hits)
	return hits

func _slot_of(kind: int, owner_slot: int, index: int) -> WorldObject:
	return _pool.slots()[_pool.slot_range(kind, owner_slot, _cfg).x + index]

func _hit_for(hits: Array[Hit], bot: Bot) -> Hit:
	for hit: Hit in hits:
		if hit.victim == bot:
			return hit
	return null

func _snapshot() -> Dictionary:
	var out: Dictionary = {}
	for slot: WorldObject in _pool.slots():
		for prop: String in SLOT_PROPS:
			out["%s.%s" % [slot.name, prop]] = slot.get(prop)
	for bot: Bot in _bots:
		for prop: String in GADGET_PROPS:
			out["%d.%s" % [bot.peer_id, prop]] = bot.gadgets.get(prop)
		out["%d.velocity" % bot.peer_id] = bot.velocity
	return out

func _restore(snapshot: Dictionary) -> void:
	for slot: WorldObject in _pool.slots():
		for prop: String in SLOT_PROPS:
			slot.set(prop, snapshot["%s.%s" % [slot.name, prop]])
	for bot: Bot in _bots:
		for prop: String in GADGET_PROPS:
			bot.gadgets.set(prop, snapshot["%d.%s" % [bot.peer_id, prop]])
		bot.velocity = snapshot["%d.velocity" % bot.peer_id] as Vector2

func _describe(hits: Array[Hit]) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for hit: Hit in hits:
		parts.append("%d<-%d d=%.5f p=%s b=%s s=%s" % [hit.victim.peer_id, hit.attacker_peer, hit.damage, hit.push, hit.bullet, hit.scale_push])
	return "|".join(parts)

# ---- config ----

func _test_config() -> void:
	await _begin()
	_check(_cfg.rocket_arm_time > 0.0 and _cfg.bomb_rest_speed > 0.0, "the task D config numbers are set")
	_check(WorldObjects.seconds_to_ticks(_cfg.bomb_fuse_time, _cfg) == 90, "the bomb fuse is 90 ticks (3 s at 30 Hz)")

# ---- launch ----

func _test_launch_slots() -> void:
	await _begin()
	var owners: Array[int] = [0, 1, 3]
	for kind: int in ItemIds.OBJECT_KIND_COUNT:
		for owner_slot: int in owners:
			var span: Vector2i = _pool.slot_range(kind, owner_slot, _cfg)
			var tag: String = "kind %d owner %d" % [kind, owner_slot]
			var first: WorldObject = _pool.launch(kind, owner_slot, 100 + owner_slot, Vector2(10, 20), Vector2(3, 4), 10, _cfg)
			_check(first == _pool.slots()[span.x], "%s: the first launch takes the first slot of the range" % tag)
			var second: WorldObject = _pool.launch(kind, owner_slot, 100 + owner_slot, Vector2(10, 20), Vector2.ZERO, 20, _cfg)
			_check(second == _pool.slots()[span.x + 1], "%s: the second launch takes the next free slot" % tag)
			var third: WorldObject = _pool.launch(kind, owner_slot, 100 + owner_slot, Vector2(30, 40), Vector2.ZERO, 30, _cfg)
			_check(third == first and first.spawn_tick == 30 and second.spawn_tick == 20, "%s: a full range replaces the oldest" % tag)
			var fourth: WorldObject = _pool.launch(kind, owner_slot, 100 + owner_slot, Vector2.ZERO, Vector2.ZERO, 40, _cfg)
			_check(fourth == second, "%s: the next replacement is the new oldest" % tag)
			first.active = false
			var fifth: WorldObject = _pool.launch(kind, owner_slot, 100 + owner_slot, Vector2.ZERO, Vector2.ZERO, 50, _cfg)
			_check(fifth == first, "%s: a free slot is used before any replacement, even over an older one" % tag)
			_check(first.launches == 3 and second.launches == 2, "%s: launches counts every launch into a slot" % tag)
	var bomb: WorldObject = _pool.launch(ItemIds.OBJECT_BOMB, 2, 77, Vector2(5, 6), Vector2(7, 8), 100, _cfg)
	_check(bomb.active and bomb.kind == ItemIds.OBJECT_BOMB and bomb.owner_peer == 77 and bomb.global_position == Vector2(5, 6) and bomb.velocity == Vector2(7, 8), "a launched bomb has its owner, position and velocity")
	_check(bomb.spawn_tick == 100 and bomb.fuse_tick == 190 and bomb.explode_tick == -1 and not bomb.landed, "a launched bomb has spawn tick, fuse tick 90 ticks later, no explosion")
	var rocket: WorldObject = _pool.launch(ItemIds.OBJECT_ROCKET, 2, 77, Vector2.ZERO, Vector2.ZERO, 100, _cfg)
	_check(rocket.arm_tick == 106, "a rocket arms 6 ticks (0.2 s) after launch")
	# Slots of different owners and kinds never overlap.
	var other: WorldObject = _pool.launch(ItemIds.OBJECT_BOMB, 1, 5, Vector2.ZERO, Vector2.ZERO, 999, _cfg)
	_check(other != bomb and bomb.spawn_tick == 100, "another owner's launch does not touch this owner's slots")
	var dummy_slot: int = _cfg.max_players
	_check(_pool.launch(ItemIds.OBJECT_BOMB, dummy_slot, Bot.DUMMY_PEER, Vector2.ZERO, Vector2.ZERO, 0, _cfg) == null, "the dummy owner gets no slot")
	_check(_pool.launch(ItemIds.OBJECT_ROCKET, -1, 1, Vector2.ZERO, Vector2.ZERO, 0, _cfg) == null, "a bad owner slot gets no slot")
	_check(_pool.launch(9, 0, 1, Vector2.ZERO, Vector2.ZERO, 0, _cfg) == null, "a bad kind gets no slot")
	_check(_pool.launch(ItemIds.OBJECT_BOMB, 0, 1, Vector2(INF, 0), Vector2.ZERO, 0, _cfg) == null, "a position that is not finite gets no slot")
	_check(_pool.launch(ItemIds.OBJECT_BOMB, 0, 1, Vector2.ZERO, Vector2(0, NAN), 0, _cfg) == null, "a velocity that is not finite gets no slot")
	_pool.reset()
	var any_active: bool = false
	for slot: WorldObject in _pool.slots():
		any_active = any_active or slot.active
	_check(not any_active, "reset makes every slot inactive")
	_check(bomb.launches == 1 and bomb.global_position == Vector2(5, 6), "reset leaves everything but active alone")

# ---- motion ----

func _test_rocket_wall() -> void:
	var wall: Array[Rect2] = [Rect2(1000, -500, 200, 2000)]
	await _begin(wall)
	var speed: float = 12.0 * _px
	var radius: float = _cfg.weapon_stats(ItemIds.ROCKET_TUBE).projectile_radius * _px
	var rocket: WorldObject = _pool.launch(ItemIds.OBJECT_ROCKET, 0, 1, Vector2(100, 100), Vector2(speed, 0), 10, _cfg)
	var predicted: int = 10 + ceili((1000.0 - radius - 100.0) / (speed * _dt))
	var seen: int = -1
	for tick: int in range(11, 80):
		_tick(tick)
		if rocket.explode_tick >= 0 and seen < 0:
			seen = tick
			_near(rocket.global_position.x, 1000.0 - radius, 0.001, "the rocket stops at the wall's surface")
	_check(seen == predicted and rocket.explode_tick == predicted, "a rocket reaches the wall on the predicted tick (%d, got %d)" % [predicted, seen])
	_check(rocket.blasts == 1 and not rocket.active, "the rocket blasts once and is gone from the next tick")
	var after: Vector2 = rocket.global_position
	for tick: int in range(seen + 1, seen + 10):
		_tick(tick)
	_check(rocket.global_position == after and rocket.blasts == 1, "an exploded rocket does not move or blast again")

func _test_rocket_range() -> void:
	await _begin()
	var stats: WeaponStats = _cfg.weapon_stats(ItemIds.ROCKET_TUBE)
	var step: float = stats.projectile_speed * _px * _dt
	var rocket: WorldObject = _pool.launch(ItemIds.OBJECT_ROCKET, 0, 1, Vector2(0, 0), Vector2(stats.projectile_speed * _px, 0), 10, _cfg)
	var expected: int = 10 + ceili(stats.range_bh * _px / step)
	_check(rocket.fuse_tick == expected, "a rocket's range limit is the tick it has flown range_bh (%d, got %d)" % [expected, rocket.fuse_tick])
	var seen: int = -1
	var before: Vector2 = Vector2.ZERO
	for tick: int in range(11, 200):
		_tick(tick)
		if rocket.explode_tick >= 0 and seen < 0:
			seen = tick
			before = rocket.global_position
			_check(rocket.blasts == 1 and not rocket.active, "a rocket that has flown its range blasts and is gone")
	_check(seen == expected, "a rocket explodes in the air when it has flown its range (tick %d, got %d)" % [expected, seen])
	_near(before.x, step * float(expected - 10), 0.01, "it explodes where it is, about range_bh from where it was launched")
	_check(rocket.global_position == before, "an exploded rocket stays where it exploded")
	var lifetime: int = ceili(stats.range_bh * _px / step)
	var still: WorldObject = _pool.launch(ItemIds.OBJECT_ROCKET, 1, 1, Vector2(0, 0), Vector2.ZERO, 300, _cfg)
	_check(still.fuse_tick == 300 + lifetime, "a rocket with no speed lives as long as a normal one (fuse %d)" % still.fuse_tick)
	var still_seen: int = -1
	for tick: int in range(301, 500):
		_tick(tick)
		if still.explode_tick >= 0 and still_seen < 0:
			still_seen = tick
	_check(still_seen == 300 + lifetime and still.blasts == 1, "a rocket with no speed explodes where it is when that time is up (tick %d)" % still_seen)
	var slow: WorldObject = _pool.launch(ItemIds.OBJECT_ROCKET, 3, 1, Vector2(0, 0), Vector2(1, 0), 600, _cfg)
	_check(slow.fuse_tick == 600 + lifetime, "a rocket that is far too slow is capped at a normal rocket's lifetime")
	var fast: WorldObject = _pool.launch(ItemIds.OBJECT_ROCKET, 3, 1, Vector2(0, 0), Vector2(2.0 * stats.projectile_speed * _px, 0), 600, _cfg)
	_check(fast.fuse_tick == 600 + ceili(stats.range_bh * _px / (2.0 * step)), "a faster rocket still stops at the tube's range")
	# A deflection starts the range again, from the deflection tick and the new speed.
	var flying: WorldObject = _pool.launch(ItemIds.OBJECT_ROCKET, 2, 1, Vector2(0, 0), Vector2(100, 0), 600, _cfg)
	_pool.deflect(flying, Vector2(0, stats.projectile_speed * _px), 2, 610, _cfg)
	_check(flying.fuse_tick == 610 + lifetime, "a deflection restarts the rocket's range at its new speed")
	_pool.deflect(flying, Vector2.ZERO, 2, 611, _cfg)
	_check(flying.velocity == Vector2.ZERO and flying.fuse_tick == 611 + lifetime, "deflect accepts any finite velocity, zero included, and the rocket still expires")

func _test_rocket_sweep() -> void:
	await _begin()
	var victim: Bot = _add_bot(11, 1, Vector2(50, 500))
	var radius: float = _cfg.weapon_stats(ItemIds.ROCKET_TUBE).projectile_radius * _px
	# 100 px per tick: the rocket ends the tick well past the bot, so a point test would miss it.
	var rocket: WorldObject = _pool.launch(ItemIds.OBJECT_ROCKET, 0, 10, Vector2(0, 500), Vector2(100.0 * float(_cfg.tick_rate), 0), 10, _cfg)
	var hits: Array[Hit] = _tick(11)
	_check(rocket.explode_tick == 11 and _hit_for(hits, victim) != null, "a rocket that passes through a bot in one tick explodes on it")
	var contact: float = victim.body_rect().position.x - radius
	_near(rocket.global_position.x, contact, 0.001, "and explodes at the contact point on its path")
	# The first bot along the path is the one it hits, not the lowest peer id.
	await _begin()
	var near_bot: Bot = _add_bot(12, 1, Vector2(40, 500))
	var far_bot: Bot = _add_bot(11, 2, Vector2(80, 500))
	var second: WorldObject = _pool.launch(ItemIds.OBJECT_ROCKET, 0, 10, Vector2(0, 500), Vector2(100.0 * float(_cfg.tick_rate), 0), 10, _cfg)
	_tick(11)
	_check(second.explode_tick == 11 and second.global_position.x < far_bot.body_rect().position.x - radius and near_bot.global_position.x == 40.0, "it explodes on the nearest bot along the path")
	# A rocket does explode on a dashing bot (it is not a bullet), found by the sweep alone: the
	# rocket ends its tick at x = 100, outside the dasher's grown rectangle (14.8 to 85.2).
	await _begin()
	var dasher: Bot = _add_bot(11, 1, Vector2(50, 500))
	dasher.dash_left = 0.1
	var third: WorldObject = _pool.launch(ItemIds.OBJECT_ROCKET, 0, 10, Vector2(0, 500), Vector2(100.0 * float(_cfg.tick_rate), 0), 10, _cfg)
	var dash_hits: Array[Hit] = _tick(11)
	_check(third.explode_tick == 11 and _hit_for(dash_hits, dasher) != null, "a rocket that crosses a dashing bot in one tick explodes on it")
	_near(third.global_position.x, dasher.body_rect().position.x - radius, 0.001, "at the dasher's edge, not at its end point")
	# A rocket launched this tick has not moved: bots behind the muzzle are not swept.
	await _begin()
	var behind: Bot = _add_bot(11, 1, Vector2(20, 500))
	# As in the game: the slots have ticked, then the rules launch the rocket and look for contact.
	var fresh: WorldObject = _pool.launch(ItemIds.OBJECT_ROCKET, 0, 10, Vector2(60, 500), Vector2(100.0 * float(_cfg.tick_rate), 0), 10, _cfg)
	var fresh_hits: Array[Hit] = []
	GadgetRules.collect(10, _sorted_bots(), _pool, _pool.solids, _cfg, fresh_hits)
	_check(fresh.explode_tick == -1 and fresh_hits.is_empty(), "a rocket launched this tick does not hit a bot behind its muzzle")

	# Deflection happens after the rocket has moved. Only the actual path can hit a bot.
	for on_path: bool in [false, true]:
		await _begin()
		var target: Bot = _add_bot(11, 1, Vector2(40, 500) if on_path else Vector2(100, 560))
		var flying: WorldObject = _pool.launch(ItemIds.OBJECT_ROCKET, 0, 10, Vector2(0, 500), Vector2(100, 0) / _dt, 10, _cfg)
		flying._rollback_tick(_dt, 11, true)
		_pool.deflect(flying, Vector2(0, -100) / _dt, 12, 11, _cfg)
		var deflected_hits: Array[Hit] = []
		GadgetRules.collect(11, _sorted_bots(), _pool, _pool.solids, _cfg, deflected_hits)
		_check((flying.explode_tick == 11) == on_path and (_hit_for(deflected_hits, target) != null) == on_path, "deflected rocket contact uses the traveled path (bot on path %s)" % on_path)

# A bot in front of a wall (or of the end of the range) wins over the wall: the rocket's own stop on
# this tick must not hide it.
func _test_rocket_bot_before_stop() -> void:
	var wall: Array[Rect2] = [Rect2(1000, -500, 200, 2000)]
	await _begin(wall)
	var radius: float = _cfg.weapon_stats(ItemIds.ROCKET_TUBE).projectile_radius * _px
	# A bot flush against the wall; the rocket reaches the wall in the same tick (60 px, about 0.9 bh, in one tick).
	var flush: Bot = _add_bot(11, 1, Vector2(1000.0 - _cfg.bot_width_bh * _px / 2.0, 500))
	var rocket: WorldObject = _pool.launch(ItemIds.OBJECT_ROCKET, 0, 10, Vector2(930, 500), Vector2(60.0 * float(_cfg.tick_rate), 0), 10, _cfg)
	var hits: Array[Hit] = _tick(11)
	_check(rocket.explode_tick == 11 and rocket.blasts == 1 and not rocket.active, "a rocket that reaches a wall in a tick explodes once, on that tick")
	_near(rocket.global_position.x, flush.body_rect().position.x - radius, 0.001, "at the bot flush against the wall, not at the wall")
	_check(_hit_for(hits, flush) != null, "and the bot is hit")
	# Nothing in the way: the wall stays the contact.
	await _begin(wall)
	var clear: WorldObject = _pool.launch(ItemIds.OBJECT_ROCKET, 0, 10, Vector2(930, 500), Vector2(60.0 * float(_cfg.tick_rate), 0), 10, _cfg)
	_tick(11)
	_near(clear.global_position.x, 1000.0 - radius, 0.001, "a rocket with no bot in front of the wall still stops at the wall")
	# The tick the range ends.
	await _begin()
	var bot: Bot = _add_bot(11, 1, Vector2(50, 500))
	var ending: WorldObject = _pool.launch(ItemIds.OBJECT_ROCKET, 0, 10, Vector2(0, 500), Vector2(100.0 * float(_cfg.tick_rate), 0), 10, _cfg)
	ending.fuse_tick = 11
	var range_hits: Array[Hit] = _tick(11)
	_check(ending.explode_tick == 11 and _hit_for(range_hits, bot) != null, "a rocket whose range ends this tick explodes once")
	_near(ending.global_position.x, bot.body_rect().position.x - radius, 0.001, "and on a bot in its path, not at the end of its range")
	var again: Array[Hit] = []
	GadgetRules.collect(11, _sorted_bots(), _pool, _pool.solids, _cfg, again)
	_check(ending.blasts == 1 and ending.explode_tick == 11, "running the rules again for the tick explodes nothing twice")
	# Already exploded on an earlier tick: left alone.
	await _begin()
	var old: WorldObject = _pool.launch(ItemIds.OBJECT_ROCKET, 0, 10, Vector2(0, 500), Vector2(100.0 * float(_cfg.tick_rate), 0), 10, _cfg)
	_add_bot(11, 1, Vector2(50, 500))
	old.explode_tick = 5
	var old_position: Vector2 = old.global_position
	_tick(11)
	_check(old.global_position == old_position and old.explode_tick == 5, "a rocket that exploded on an earlier tick is not touched")

func _test_rocket_range_without_speed() -> void:
	await _begin()
	var saved: TuningConfig = _cfg
	var cfg: TuningConfig = _cfg.duplicate() as TuningConfig
	var stats: WeaponStats = (_cfg.weapons[ItemIds.ROCKET_TUBE] as WeaponStats).duplicate() as WeaponStats
	stats.projectile_speed = 0.0
	cfg.weapons = _cfg.weapons.duplicate()
	cfg.weapons[ItemIds.ROCKET_TUBE] = stats
	var rocket: WorldObject = _pool.launch(ItemIds.OBJECT_ROCKET, 0, 1, Vector2(0, 0), Vector2.ZERO, 10, cfg)
	var fuse: int = WorldObjects.seconds_to_ticks(cfg.bomb_fuse_time, cfg)
	_check(rocket.fuse_tick == 10 + fuse, "a tube speed of 0 gives the rocket a bomb-fuse lifetime, not a division by zero (fuse %d)" % rocket.fuse_tick)
	_pool.deflect(rocket, Vector2(0, 640), 2, 20, cfg)
	_check(rocket.fuse_tick > 20 and rocket.fuse_tick <= 20 + fuse, "and a deflected one is still finite (fuse %d)" % rocket.fuse_tick)
	_check(saved == _cfg, "the real config was not touched")

func _test_launch_inside_solid() -> void:
	var wall: Array[Rect2] = [Rect2(1000, -500, 200, 2000), Rect2(-5000, 2000, 10000, 500)]
	await _begin(wall)
	var victim: Bot = _add_bot(11, 1, Vector2(960, 500))
	var radius: float = _cfg.weapon_stats(ItemIds.ROCKET_TUBE).projectile_radius * _px
	# A rocket whose muzzle is inside the wall explodes on the launch tick, where it was launched.
	var rocket: WorldObject = _pool.launch(ItemIds.OBJECT_ROCKET, 0, 10, Vector2(1010, 500), Vector2(12.0 * _px, 0), 10, _cfg)
	_check(rocket.explode_tick == 10 and rocket.global_position == Vector2(1010, 500), "a rocket launched inside a wall explodes on the launch tick at the launch position")
	var hits: Array[Hit] = _tick(10)
	_check(rocket.blasts == 1 and not rocket.active and _hit_for(hits, victim) != null, "its blast is applied on that same tick")
	_check(rocket.global_position == Vector2(1010, 500), "and it stays where it exploded")
	var touching: WorldObject = _pool.launch(ItemIds.OBJECT_ROCKET, 0, 10, Vector2(1000.0 - radius, 100), Vector2(12.0 * _px, 0), 20, _cfg)
	_check(touching.explode_tick == 20, "a rocket launched touching a wall explodes at once")
	var clear: WorldObject = _pool.launch(ItemIds.OBJECT_ROCKET, 0, 10, Vector2(1000.0 - radius - 1.0, 300), Vector2(12.0 * _px, 0), 30, _cfg)
	_check(clear.explode_tick == -1, "a rocket launched just clear of the wall does not")
	# A bomb is moved out along the nearest face.
	var bomb_radius: float = _cfg.bomb_radius * _px
	var bomb: WorldObject = _pool.launch(ItemIds.OBJECT_BOMB, 0, 10, Vector2(1005, 700), Vector2(10.0 * _px, 0), 40, _cfg)
	_near(bomb.global_position.x, 1000.0 - bomb_radius - WorldObject.SURFACE_GAP_PX, 0.001, "a bomb launched inside a wall is moved out to its near face")
	_check(bomb.global_position.y == 700.0 and bomb.explode_tick == -1 and bomb.active, "and keeps its height and stays live")
	var in_floor: WorldObject = _pool.launch(ItemIds.OBJECT_BOMB, 0, 10, Vector2(300, 2005), Vector2.ZERO, 40, _cfg)
	_near(in_floor.global_position.y, 2000.0 - bomb_radius - WorldObject.SURFACE_GAP_PX, 0.001, "a bomb launched inside the floor is moved up out of it")
	# The moved bomb then bounces off the wall like any other (it is not stuck).
	for tick: int in range(41, 60):
		_tick(tick)
		if bomb.velocity.x < 0.0:
			break
	_check(bomb.velocity.x < 0.0, "a bomb that was moved out bounces off the wall")
	var plate: WorldObject = _pool.launch(ItemIds.OBJECT_PLATE, 0, 10, Vector2(300, 2000), Vector2.ZERO, 50, _cfg)
	_near(plate.global_position.y, 2000.0 - _cfg.plate_size.y * _px / 2.0 - WorldObject.SURFACE_GAP_PX, 0.001, "a plate launched inside the floor is moved up out of it")
	var free_plate: WorldObject = _pool.launch(ItemIds.OBJECT_PLATE, 0, 10, Vector2(300, 1000), Vector2.ZERO, 50, _cfg)
	_check(free_plate.global_position == Vector2(300, 1000), "an object that overlaps nothing is not moved")

# A plate thrown into a gap narrower than the plate is not lost: it is placed where it was thrown
# and falls to the floor of the gap.
func _test_narrow_column() -> void:
	var plate_width: float = _cfg.plate_size.x * _px
	var column: float = _px
	_check(column < plate_width, "the test column (one bot wide) is narrower than a plate")
	var solids: Array[Rect2] = [Rect2(-200, -500, 200, 3000), Rect2(column, -500, 300, 3000), Rect2(-200, 1500, 800, 500)]
	await _begin(solids)
	var thrower: Bot = _add_bot(10, 0, Vector2(column / 2.0, 1000))
	var plate: WorldObject = _pool.launch(ItemIds.OBJECT_PLATE, 0, 10, thrower.center(), Vector2.ZERO, 5, _cfg)
	_check(plate != null and plate.global_position == thrower.center(), "a plate that cannot be pushed clear is placed at the thrower's position")
	var landed_at: int = -1
	for tick: int in range(6, 120):
		_tick(tick)
		if plate.landed and landed_at < 0:
			landed_at = tick
	_check(plate.active and landed_at > 0, "and it is not lost: it falls and lands (tick %d)" % landed_at)
	_near(plate.global_position.y, 1500.0 - _cfg.plate_size.y * _px / 2.0, 0.05, "on the floor of the gap")
	_near(plate.global_position.x, column / 2.0, 0.001, "at the thrower's x")
	# A bomb (narrower than the column) is simply pushed clear when it overlaps one wall.
	var bomb: WorldObject = _pool.launch(ItemIds.OBJECT_BOMB, 0, 10, Vector2(3, 1000), Vector2.ZERO, 200, _cfg)
	var radius: float = _cfg.bomb_radius * _px
	_check(bomb.global_position.x >= radius and bomb.global_position.x <= column - radius, "a bomb thrown in the column is pushed clear of both walls")
	# The same plate through the gadget rules, from a bot that threw it.
	await _begin(solids)
	var bot: Bot = _add_bot(10, 0, Vector2(column / 2.0, 1000))
	bot.gadgets.gadget_a = ItemIds.SPRING_PLATE
	bot.input.gadget = true
	bot.input.aim = Vector2(0, 1)
	_tick(300)
	var thrown: WorldObject = _slot_of(ItemIds.OBJECT_PLATE, 0, 0)
	_check(thrown.active and bot.gadgets.gadget_a == ItemIds.NONE, "a plate thrown by a bot in the column is live")
	_tick(301)
	_check(thrown.active, "and survives its first tick")

# Two blocks whose grown rectangles overlap: leaving the first face lands inside the second, so
# a single pass is not enough (found by searching; the numbers assume bomb_radius 0.25 bh at 64 px).
func _test_push_out_passes() -> void:
	var r: float = _cfg.bomb_radius * _px
	var solids: Array[Rect2] = [Rect2(r, r, 100.0 - 2.0 * r, 100.0 - 2.0 * r), Rect2(50.0 + r, 60.0 + r, 100.0 - 2.0 * r, 100.0 - 2.0 * r)]
	await _begin(solids)
	var bomb: WorldObject = _pool.launch(ItemIds.OBJECT_BOMB, 0, 1, Vector2(91, 98), Vector2.ZERO, 5, _cfg)
	var clear: bool = true
	for rect: Rect2 in _pool.grown_solids(Vector2(r, r)):
		clear = clear and not (bomb.global_position.x > rect.position.x and bomb.global_position.x < rect.end.x and bomb.global_position.y > rect.position.y and bomb.global_position.y < rect.end.y)
	_check(clear and bomb.global_position != Vector2(91, 98), "push-out keeps going until the shape is clear of every solid (ended at %s)" % bomb.global_position)

func _test_grown_cache() -> void:
	var solids: Array[Rect2] = [Rect2(0, 0, 10, 10)]
	await _begin(solids)
	var a: Array[Rect2] = _pool.grown_solids(Vector2(2, 3))
	var b: Array[Rect2] = _pool.grown_solids(Vector2(2, 3))
	var expected: Array[Rect2] = [Rect2(-2, -3, 14, 16)]
	_check(a == expected, "grown_solids grows every side by the half extents")
	_check(is_same(a, b), "grown_solids keeps one array per half size")
	_check(not is_same(a, _pool.grown_solids(Vector2(1, 1))), "a different half size gets its own array")
	var other: Array[Rect2] = [Rect2(5, 5, 10, 10)]
	_pool.solids = other
	var rebuilt: Array[Rect2] = [Rect2(3, 2, 14, 16)]
	_check(_pool.grown_solids(Vector2(2, 3)) == rebuilt, "changing the solids rebuilds the arrays")

func _test_session_reset() -> void:
	await _begin()
	# The pool listens to all four session signals (emitting netfox's own would start its clock).
	var wired: bool = NetworkEvents.on_server_start.is_connected(_pool.reset_session) and NetworkEvents.on_server_stop.is_connected(_pool.reset_session) and NetworkEvents.on_client_stop.is_connected(_pool.reset_session) and NetworkEvents.on_client_start.is_connected(_pool._on_client_start)
	_check(wired, "the pool resets on server start, server stop, client start and client stop")
	for round_name: String in ["a stop", "a start"]:
		_pool.launch(ItemIds.OBJECT_BOMB, 0, 1, Vector2(5, 5), Vector2.ZERO, 5000, _cfg)
		_pool.launch(ItemIds.OBJECT_PLATE, 1, 2, Vector2(5, 5), Vector2.ZERO, 5000, _cfg)
		_pool.launch(ItemIds.OBJECT_ROCKET, 2, 3, Vector2(5, 5), Vector2.ZERO, 5000, _cfg)
		var bomb: WorldObject = _slot_of(ItemIds.OBJECT_BOMB, 0, 0)
		_check(bomb.active and bomb._sending, "an object is live and being sent before %s" % round_name)
		if round_name == "a stop":
			_pool.reset_session()
		else:
			_pool._on_client_start(7)
		var live: int = 0
		var sending: int = 0
		for slot: WorldObject in _pool.slots():
			live += int(slot.active)
			sending += int(slot._sending or slot._send_until_tick >= 0)
		_check(live == 0 and sending == 0, "after %s no object is live and nothing is being sent (%d live, %d sending)" % [round_name, live, sending])
	# A plate left from before a stop cannot launch anyone after the next start.
	var floor_solids: Array[Rect2] = [Rect2(-5000, 1000, 10000, 500)]
	await _begin(floor_solids)
	var bot: Bot = _add_bot(11, 1, Vector2(600, 968))
	var old_plate: WorldObject = _pool.launch(ItemIds.OBJECT_PLATE, 0, 10, Vector2(600, 990), Vector2.ZERO, 9000, _cfg)
	old_plate.landed = true
	old_plate.arm_tick = 9001
	_pool.reset_session()
	_check(_hit_for(_tick(9100), bot) == null, "a plate from before a stop launches nobody after the next start")

func _test_teleport_and_colour() -> void:
	# Interpolation is off in a headless run, so switch it on for this test to see the call.
	InterpolationServer.set_server_enabled(true)
	await _begin()
	var slot: WorldObject = _pool.launch(ItemIds.OBJECT_BOMB, 0, 1, Vector2(5, 5), Vector2.ZERO, 5, _cfg)
	await get_tree().process_frame
	await get_tree().process_frame
	slot._seen_launches = slot.launches
	InterpolationServer._clear_teleports()
	slot.active = false
	_pool.launch(ItemIds.OBJECT_BOMB, 0, 1, Vector2(400, 5), Vector2.ZERO, 6, _cfg)
	_check(slot.launches == 2, "the slot was reused")
	slot._process(0.0)
	_check(not InterpolationServer.is_teleporting(slot), "the frame's _process does not teleport (it runs after netfox has interpolated)")
	NetworkTime.after_tick_loop.emit()
	_check(InterpolationServer.is_teleporting(slot), "the slot is teleported from netfox's after_tick_loop, before the interpolation of that frame")
	InterpolationServer._clear_teleports()
	NetworkTime.after_tick_loop.emit()
	_check(not InterpolationServer.is_teleporting(slot), "a launch is teleported once")
	InterpolationServer.set_server_enabled(false)
	# Plates take their owner's body colour.
	for owner_slot: int in _cfg.max_players:
		var plate: WorldObject = _slot_of(ItemIds.OBJECT_PLATE, owner_slot, 0)
		_check(plate.owner_color(_cfg) == BotVisual.PALETTE[owner_slot % BotVisual.PALETTE.size()], "a plate of owner slot %d has that bot's colour" % owner_slot)

func _test_bomb_fuse_and_bounce() -> void:
	# The fuse: exactly 90 ticks, in open space.
	await _begin()
	var bomb: WorldObject = _pool.launch(ItemIds.OBJECT_BOMB, 0, 1, Vector2(0, 0), Vector2.ZERO, 100, _cfg)
	var explode_seen: int = -1
	var blast_position: Vector2 = Vector2.ZERO
	for tick: int in range(101, 200):
		_tick(tick)
		if bomb.explode_tick >= 0 and explode_seen < 0:
			explode_seen = tick
			blast_position = bomb.global_position
		if tick == 189:
			_check(bomb.explode_tick == -1 and bomb.active, "the bomb has not exploded after 89 ticks")
	_check(explode_seen == 190 and bomb.explode_tick == 190, "the bomb explodes after exactly 90 ticks (got %d)" % explode_seen)
	_check(bomb.blasts == 1 and not bomb.active, "the bomb blasts once and is inactive from the next tick")
	_check(bomb.global_position == blast_position, "a bomb stays where it exploded")

	# Floor bounce and rest.
	var floor_rect: Array[Rect2] = [Rect2(-5000, 1000, 10000, 500)]
	await _begin(floor_rect)
	bomb = _pool.launch(ItemIds.OBJECT_BOMB, 0, 1, Vector2(0, 800), Vector2.ZERO, 0, _cfg)
	var gravity_step: float = _cfg.object_gravity * _px * _dt
	var radius: float = _cfg.bomb_radius * _px
	var bounced: bool = false
	var landed_at: int = -1
	for tick: int in range(1, 60):
		var before: Vector2 = bomb.velocity
		_tick(tick)
		if not bounced and bomb.velocity.y < 0.0:
			bounced = true
			_near(bomb.velocity.y, -(before.y + gravity_step) * _cfg.bomb_bounce, 0.01, "the first bounce keeps bomb_bounce of the speed, reversed")
			_check(bomb.global_position.y <= 1000.0 - radius, "the bomb is at or above the surface after a bounce")
		if bomb.landed and landed_at < 0:
			landed_at = tick
	_check(bounced and landed_at > 0 and landed_at < 50, "the bomb bounces and comes to rest (landed at tick %d)" % landed_at)
	_check(bomb.landed and bomb.velocity == Vector2.ZERO, "a resting bomb has no velocity")
	_near(bomb.global_position.y, 1000.0 - radius, 0.1, "a resting bomb sits on the surface")
	var rest_pos: Vector2 = bomb.global_position
	for tick: int in range(60, 70):
		_tick(tick)
	_check(bomb.global_position == rest_pos and bomb.explode_tick == -1, "a resting bomb stays put until its fuse ends")

	# Wall bounce: the speed is scaled and the normal component reversed.
	var wall: Array[Rect2] = [Rect2(1000, -5000, 200, 10000)]
	await _begin(wall)
	bomb = _pool.launch(ItemIds.OBJECT_BOMB, 0, 1, Vector2(900, 100), Vector2(10.0 * _px, 0), 0, _cfg)
	for tick: int in range(1, 20):
		var before_wall: Vector2 = bomb.velocity
		_tick(tick)
		if bomb.velocity.x < 0.0:
			var expected: Vector2 = Vector2(-before_wall.x, before_wall.y + gravity_step) * _cfg.bomb_bounce
			_near_v(bomb.velocity, expected, 0.01, "a wall bounce reverses x and keeps bomb_bounce of the speed")
			_check(bomb.global_position.x < 1000.0 - radius + 0.5 and not bomb.landed, "a bomb that bounces off a wall in the air does not rest")
			break

func _test_bounds_and_inactive() -> void:
	await _begin()
	_pool.bounds_px = Rect2(0, 0, 500, 500)
	var bomb: WorldObject = _pool.launch(ItemIds.OBJECT_BOMB, 0, 1, Vector2(490, 100), Vector2(10.0 * _px, 0), 0, _cfg)
	for tick: int in range(1, 6):
		_tick(tick)
	_check(not bomb.active and bomb.blasts == 0 and bomb.explode_tick == -1, "an object that leaves the arena is removed without a blast")

	# An inactive slot is left completely unchanged by a tick, on every peer.
	await _begin()
	var slot: WorldObject = _pool.slots()[3]
	slot.kind = ItemIds.OBJECT_BOMB
	slot.velocity = Vector2(5, 6)
	slot.global_position = Vector2(7, 8)
	slot.fuse_tick = 2
	slot.explode_tick = 7
	slot.arm_tick = 9
	slot.owner_peer = 4
	slot.launches = 5
	slot.blasts = 4
	var removed: WorldObject = _pool.slots()[4]
	removed.kind = ItemIds.OBJECT_BOMB
	removed.velocity = Vector2(500, 0)
	removed.global_position = Vector2(9, 9)
	removed.fuse_tick = 3
	removed.owner_peer = 2
	var snapshot: Dictionary = _snapshot()
	for tick: int in range(0, 12):
		_tick(tick)
	_check(_snapshot() == snapshot, "inactive slots are unchanged by ticks, whatever their old values")
	var live: WorldObject = _pool.launch(ItemIds.OBJECT_BOMB, 1, 1, Vector2(50, 50), Vector2(100, 0), 0, _cfg)
	live.set_multiplayer_authority(2, false)
	var live_state: Array = [live.global_position, live.velocity, live.explode_tick, live.active]
	for tick: int in range(1, 10):
		_tick(tick)
	_check([live.global_position, live.velocity, live.explode_tick, live.active] == live_state, "a slot that this peer is not the authority of does not move")
	live.set_multiplayer_authority(1, false)

# ---- sending to peers ----

func _test_sending() -> void:
	await _begin()
	var interval: int = WorldObjects.seconds_to_ticks(_cfg.object_idle_send_interval, _cfg)
	var idle: WorldObject = _pool.slots()[10]
	var idle_sent: int = 0
	for tick: int in range(100, 100 + 2 * interval):
		_tick(tick)
		idle_sent += int(idle._sending)
	_check(idle_sent == 2, "an idle slot is sent once per interval, not every tick (%d in two intervals)" % idle_sent)
	var bomb: WorldObject = _pool.launch(ItemIds.OBJECT_BOMB, 0, 1, Vector2(0, 0), Vector2.ZERO, 205, _cfg)
	_check(bomb._sending, "a launch makes the slot sent at once, before the next tick")
	var sent: Dictionary = {}
	var exploded: int = -1
	for tick: int in range(206, 206 + 90 + 2 * interval + 5):
		_tick(tick)
		sent[tick] = bomb._sending
		if bomb.explode_tick >= 0 and exploded < 0:
			exploded = tick
	_check(exploded == 205 + 90, "the bomb in the sending test exploded at tick 295 (got %d)" % exploded)
	var every_tick: bool = true
	for tick: int in range(206, exploded + interval + 1):
		every_tick = every_tick and sent[tick] as bool
	_check(every_tick, "a slot is sent every tick while its object lives and for one interval after it ends")
	var later: int = 0
	for tick: int in range(exploded + interval + 1, exploded + 2 * interval + 1):
		later += int(sent[tick] as bool)
	_check(later == 1, "after that an idle slot is sent once per interval again (%d in one interval)" % later)
	var again: WorldObject = _pool.launch(ItemIds.OBJECT_BOMB, 0, 1, Vector2(0, 0), Vector2.ZERO, 600, _cfg)
	_check(again == bomb and bomb._sending, "a slot that was idle is sent again when it is reused")

# ---- blasts ----

func _test_blast_numbers() -> void:
	await _begin()
	var centre: Vector2 = Vector2(500, 500)
	var owner_bot: Bot = _add_bot(10, 0, centre + Vector2(0, _px))
	var at_centre: Bot = _add_bot(11, 1, centre)
	var half: Bot = _add_bot(12, 2, centre + Vector2(1.5 * _px, 0))
	var at_radius: Bot = _add_bot(13, 3, centre + Vector2(-3.0 * _px, 0))
	var beyond: Bot = _add_bot(14, 1, centre + Vector2(0, 4.0 * _px))
	var knocked_out: Bot = _add_bot(15, 2, centre + Vector2(0.5 * _px, 0))
	knocked_out.vitals.knocked_out = true
	var bomb: WorldObject = _pool.launch(ItemIds.OBJECT_BOMB, 0, 10, centre, Vector2.ZERO, 0, _cfg)
	bomb.landed = true
	var all_hits: Array[Hit] = []
	var hits_before: int = 0
	for tick: int in range(1, 91):
		var hits: Array[Hit] = _tick(tick)
		if tick < 90:
			hits_before += hits.size()
		else:
			all_hits = hits
	_check(hits_before == 0, "no hit before the fuse ends")
	_check(bomb.blasts == 1 and not bomb.active and bomb.explode_tick == 90, "the blast happens at tick 90 and removes the bomb")
	var radius: float = _cfg.bomb_blast_radius
	var hit: Hit = _hit_for(all_hits, at_centre)
	_check(hit != null, "a bot at the centre is hit")
	if hit != null:
		_near(hit.damage, _cfg.bomb_blast_damage, 0.0001, "full damage at the centre")
		_near_v(hit.push, Vector2(0, -_cfg.bomb_blast_push), 0.0001, "push 5 straight up at the exact centre")
		_check(hit.attacker_peer == 10 and not hit.bullet and hit.scale_push, "the hit is the owner's, not a bullet, and scaled")
	hit = _hit_for(all_hits, half)
	_check(hit != null, "a bot at half the radius is hit")
	if hit != null:
		_near(hit.damage, _cfg.bomb_blast_damage * 0.5, 0.0001, "half damage at half the radius")
		_near_v(hit.push, Vector2(_cfg.bomb_blast_push * 0.5, 0), 0.0001, "half the push, away from the centre, at half the radius")
	hit = _hit_for(all_hits, owner_bot)
	_check(hit != null and hit.attacker_peer == 10, "the owner is hit by its own blast")
	if hit != null:
		_near(hit.damage, _cfg.bomb_blast_damage * (1.0 - 1.0 / radius), 0.0001, "the owner takes full unscaled damage here (task B scales it)")
		_near_v(hit.push, Vector2(0, _cfg.bomb_blast_push * (1.0 - 1.0 / radius)), 0.0001, "the owner is pushed down, away from the centre")
	_check(_hit_for(all_hits, at_radius) == null, "no hit exactly at the blast radius")
	_check(_hit_for(all_hits, beyond) == null, "no hit beyond the blast radius")
	_check(_hit_for(all_hits, knocked_out) == null, "a knocked-out bot is not hit")
	_check(all_hits.size() == 3, "exactly three bots are hit (got %d)" % all_hits.size())
	# Left of the centre pushes left.
	var left_bot: Bot = _bots[3]
	_check(left_bot == at_radius and at_radius.global_position.x < centre.x, "the bot at the radius is on the left")
	await _begin()
	var west: Bot = _add_bot(21, 1, Vector2(400, 500))
	var rocket: WorldObject = _pool.launch(ItemIds.OBJECT_ROCKET, 0, 20, Vector2(500, 500), Vector2.ZERO, 0, _cfg)
	var stats: WeaponStats = _cfg.weapon_stats(ItemIds.ROCKET_TUBE)
	rocket.explode_tick = 3
	var rocket_hits: Array[Hit] = _tick(3)
	var west_hit: Hit = _hit_for(rocket_hits, west)
	var west_strength: float = 1.0 - (100.0 / _px) / stats.blast_radius
	_check(west_hit != null and west_hit.push.x < 0.0 and absf(west_hit.push.y) < 0.0001, "a bot to the west is pushed west")
	if west_hit != null:
		_near(west_hit.push.length(), stats.blast_push * west_strength, 0.0001, "a rocket blast uses the rocket's own push number")
		_near(west_hit.damage, stats.blast_damage * west_strength, 0.0001, "a rocket blast uses the rocket's own damage number")

func _test_rocket_contact_and_arming() -> void:
	await _begin()
	var shooter: Bot = _add_bot(10, 0, Vector2(500, 500))
	var rocket: WorldObject = _pool.launch(ItemIds.OBJECT_ROCKET, 0, 10, shooter.center(), Vector2.ZERO, 0, _cfg)
	var exploded: int = -1
	for tick: int in range(0, 12):
		_tick(tick)
		if rocket.explode_tick >= 0 and exploded < 0:
			exploded = tick
	_check(exploded == 6, "a rocket does not hit its owner before arm_tick, and does at arm_tick (got %d)" % exploded)

	await _begin()
	var owner_bot: Bot = _add_bot(10, 0, Vector2(900, 500))
	var target: Bot = _add_bot(11, 1, Vector2(500, 500))
	rocket = _pool.launch(ItemIds.OBJECT_ROCKET, 0, 10, Vector2(500 + 0.5 * _px, 500), Vector2.ZERO, 0, _cfg)
	var hits: Array[Hit] = _tick(0)
	_check(rocket.explode_tick == 0 and rocket.blasts == 1 and not rocket.active, "a rocket touching another bot blasts on that tick")
	_check(_hit_for(hits, target) != null and _hit_for(hits, owner_bot) == null, "only the bot in the blast is hit")

	# A knocked-out bot is not touched, and a near miss does not trigger.
	await _begin()
	var dead: Bot = _add_bot(12, 1, Vector2(500, 500))
	dead.vitals.knocked_out = true
	var near_miss: Bot = _add_bot(13, 2, Vector2(500 + 0.3 * _px + _cfg.weapon_stats(ItemIds.ROCKET_TUBE).projectile_radius * _px + 1.0, 500 - 3.0 * _px))
	rocket = _pool.launch(ItemIds.OBJECT_ROCKET, 0, 10, Vector2(500, 500), Vector2.ZERO, 0, _cfg)
	_tick(1)
	_check(rocket.explode_tick == -1 and near_miss.global_position.y < 500.0, "a rocket does not touch a knocked-out bot or one that is far away")

func _test_blast_pushes_objects() -> void:
	await _begin()
	var bomb: WorldObject = _pool.launch(ItemIds.OBJECT_BOMB, 0, 10, Vector2(500, 500), Vector2.ZERO, 0, _cfg)
	bomb.landed = true
	var other_bomb: WorldObject = _pool.launch(ItemIds.OBJECT_BOMB, 1, 11, Vector2(500 + 1.5 * _px, 500), Vector2.ZERO, 50, _cfg)
	other_bomb.landed = true
	var plate: WorldObject = _pool.launch(ItemIds.OBJECT_PLATE, 1, 11, Vector2(500, 500 + _px), Vector2.ZERO, 50, _cfg)
	plate.landed = true
	plate.arm_tick = 10000
	for tick: int in range(1, 91):
		_tick(tick)
		if tick == 89:
			other_bomb.landed = true
			other_bomb.velocity = Vector2.ZERO
			other_bomb.global_position = Vector2(500 + 1.5 * _px, 500)
	_check(bomb.blasts == 1 and other_bomb.active and other_bomb.owner_peer == 11, "a blast does not change the owner of a bomb it pushes")
	var expected: float = _cfg.bomb_blast_push * 0.5 * _cfg.push_speed_scale * _px
	_near(other_bomb.velocity.x, expected, 0.001, "a bomb in the blast is pushed away with the blast's push")
	_check(not other_bomb.landed, "a pushed bomb is no longer at rest")
	_check(plate.active and plate.velocity == Vector2.ZERO, "a plate is not pushed")

func _test_plates() -> void:
	var floor_rect: Array[Rect2] = [Rect2(-5000, 1000, 10000, 500)]
	await _begin(floor_rect)
	var owner_bot: Bot = _add_bot(10, 0, Vector2(610, 968))
	var stander: Bot = _add_bot(11, 1, Vector2(600, 968))
	var riser: Bot = _add_bot(12, 2, Vector2(590, 968))
	riser.velocity = Vector2(0, -100)
	var aside: Bot = _add_bot(13, 3, Vector2(900, 968))
	var above: Bot = _add_bot(14, 1, Vector2(600, 900))
	var dead: Bot = _add_bot(15, 2, Vector2(605, 968))
	dead.vitals.knocked_out = true
	var plate: WorldObject = _pool.launch(ItemIds.OBJECT_PLATE, 0, 10, Vector2(600, 900), Vector2.ZERO, 0, _cfg)
	var landed_at: int = -1
	var launch_hits: Array[Hit] = []
	var early_hits: int = 0
	var armed_at: int = -1
	for tick: int in range(1, 80):
		var hits: Array[Hit] = _tick(tick)
		if plate.landed and landed_at < 0:
			landed_at = tick
			armed_at = plate.arm_tick
		if landed_at >= 0 and tick < armed_at:
			early_hits += hits.size()
		if landed_at >= 0 and tick == armed_at:
			launch_hits = hits
	_check(landed_at > 0 and plate.velocity == Vector2.ZERO, "a plate falls and lands (tick %d)" % landed_at)
	_near(plate.global_position.y, 1000.0 - _cfg.plate_size.y * _px / 2.0, 0.05, "a landed plate sits on the surface")
	_check(armed_at == landed_at + 15, "a plate arms plate_arm_time (15 ticks) after landing")
	_check(early_hits == 0, "a plate launches nobody before it is armed")
	var hit: Hit = _hit_for(launch_hits, stander)
	_check(hit != null, "a bot standing on an armed plate is launched")
	if hit != null:
		_check(hit.push == Vector2(0.0, -_cfg.plate_launch_speed), "the launch is exactly plate_launch_speed straight up")
		_check(hit.damage == 0.0 and not hit.scale_push and not hit.bullet and hit.attacker_peer == 10, "the launch does no damage, is not scaled, and is credited to the plate's owner")
	if hit != null:
		_check(hit.launch == true, "the plate's hit has launch set")
	_check(_hit_for(launch_hits, owner_bot) != null, "the plate's owner is launched too")
	_check(_hit_for(launch_hits, riser) == null, "a bot moving upward through the plate is not launched")
	_check(_hit_for(launch_hits, aside) == null, "a bot beside the plate is not launched")
	_check(_hit_for(launch_hits, above) == null, "a bot above the plate is not launched")
	_check(_hit_for(launch_hits, dead) == null, "a knocked-out bot is not launched")
	_check(plate.active, "a plate stays after launching")
	var again: Array[Hit] = _tick(armed_at + 1)
	_check(_hit_for(again, stander) != null, "a bot that is still on the plate is launched again next tick (task B's push lifts it off)")

	# A third plate removes the oldest.
	await _begin(floor_rect)
	var first: WorldObject = _pool.launch(ItemIds.OBJECT_PLATE, 0, 10, Vector2(100, 900), Vector2.ZERO, 0, _cfg)
	var second: WorldObject = _pool.launch(ItemIds.OBJECT_PLATE, 0, 10, Vector2(200, 900), Vector2.ZERO, 5, _cfg)
	var third: WorldObject = _pool.launch(ItemIds.OBJECT_PLATE, 0, 10, Vector2(300, 900), Vector2.ZERO, 10, _cfg)
	_check(third == first and second.global_position.x == 200.0 and first.global_position.x == 300.0, "placing a third plate replaces the oldest, the second stays")
	_check(_pool.launch(ItemIds.OBJECT_PLATE, 1, 11, Vector2.ZERO, Vector2.ZERO, 11, _cfg) != first, "another owner's plates are separate")

# ---- queries ----

func _test_targets() -> void:
	await _begin()
	var bomb: WorldObject = _pool.launch(ItemIds.OBJECT_BOMB, 0, 1, Vector2(200, 100), Vector2.ZERO, 0, _cfg)
	var rocket: WorldObject = _pool.launch(ItemIds.OBJECT_ROCKET, 0, 1, Vector2(300, 100), Vector2.ZERO, 0, _cfg)
	var plate: WorldObject = _pool.launch(ItemIds.OBJECT_PLATE, 0, 1, Vector2(400, 100), Vector2.ZERO, 0, _cfg)
	var twin: WorldObject = _pool.launch(ItemIds.OBJECT_BOMB, 0, 1, Vector2(200, 100), Vector2.ZERO, 0, _cfg)
	var gone: WorldObject = _pool.launch(ItemIds.OBJECT_ROCKET, 1, 1, Vector2(250, 100), Vector2.ZERO, 0, _cfg)
	gone.active = false
	var bomb_radius: float = _cfg.bomb_radius * _px
	var found: Array[ObjectCast] = _pool.targets_along(Vector2(0, 100), Vector2(500, 100), _cfg)
	_check(found.size() == 4, "a segment through four objects finds four (inactive ignored), got %d" % found.size())
	if found.size() == 4:
		_check(found[0].slot == bomb and found[1].slot == twin and found[2].slot == rocket and found[3].slot == plate, "nearest first, a tie goes to the lowest slot")
		_near(found[0].t, (200.0 - bomb_radius) / 500.0, 0.0001, "a bomb is entered at its circle edge")
		_near_v(found[0].normal, Vector2(-1, 0), 0.0001, "a circle's normal points back along the segment")
		_near(found[0].radius, bomb_radius, 0.0001, "a round object reports its radius")
		var plate_width: float = _cfg.plate_size.x * _px
		_near(found[3].t, (400.0 - plate_width / 2.0) / 500.0, 0.0001, "a plate is entered at its rectangle edge")
		_check(found[3].radius == 0.0 and found[3].rect == WorldObjects.plate_rect(plate, _cfg), "a plate reports its rectangle and no radius")
	_check(_pool.targets_along(Vector2(0, 300), Vector2(500, 300), _cfg).is_empty(), "a segment that misses finds nothing")
	_check(_pool.targets_along(Vector2(0, 100), Vector2(150, 100), _cfg).is_empty(), "a segment that stops short finds nothing")
	var inside: Array[ObjectCast] = _pool.targets_along(Vector2(200, 100), Vector2(500, 100), _cfg)
	_check(inside.size() >= 1 and inside[0].t == 0.0 and inside[0].normal == Vector2.ZERO, "a segment that starts inside an object reports t 0 and no normal")
	var graze: Array[ObjectCast] = _pool.targets_along(Vector2(0, 100 - bomb_radius + 1.0), Vector2(500, 100 - bomb_radius + 1.0), _cfg)
	_check(graze.size() >= 1 and graze[0].slot == bomb, "a segment that clips the edge of a circle hits it")
	var miss_just: Array[ObjectCast] = _pool.targets_along(Vector2(0, 100 - bomb_radius - 1.0), Vector2(150, 100 - bomb_radius - 1.0), _cfg)
	_check(miss_just.is_empty(), "a segment just outside the circle misses")

	var dying: WorldObject = _pool.launch(ItemIds.OBJECT_ROCKET, 2, 1, Vector2(260, 100), Vector2.ZERO, 0, _cfg)
	dying.explode_tick = 3
	var dying_found: Array[ObjectCast] = _pool.targets_along(Vector2(0, 100), Vector2(500, 100), _cfg)
	var dying_seen: bool = false
	for entry: ObjectCast in dying_found:
		dying_seen = dying_seen or entry.slot == dying
	_check(not dying_seen and dying_found.size() == 4, "targets_along skips an object that is set to explode this tick")
	_check(not _pool.targets_near(Vector2(260, 100), 30.0, _cfg).has(dying), "targets_near skips it too")
	dying.active = false
	var near_list: Array[WorldObject] = _pool.targets_near(Vector2(250, 100), 60.0, _cfg)
	var expected_near: Array[WorldObject] = [rocket, bomb, twin]
	_check(near_list == expected_near, "targets_near returns bombs and rockets in slot order, never plates")
	_check(_pool.targets_near(Vector2(250, 100), 20.0, _cfg).is_empty(), "targets_near respects the radius")
	_check(_pool.targets_near(Vector2(400, 100), 30.0, _cfg).is_empty() and plate.active, "targets_near does not return a plate even when it is in range")
	_check(_pool.targets_near(Vector2(200.0 + bomb_radius + 10.0, 100), 10.0, _cfg).size() == 2, "targets_near counts the object's own radius (the bomb and its twin, not the rocket)")

func _test_deflect_and_destroy() -> void:
	await _begin()
	var bomb: WorldObject = _pool.launch(ItemIds.OBJECT_BOMB, 0, 10, Vector2(100, 100), Vector2(5, 5), 0, _cfg)
	bomb.landed = true
	var fuse: int = bomb.fuse_tick
	_pool.deflect(bomb, Vector2(300, -200), 11, 7, _cfg)
	_check(bomb.owner_peer == 11 and bomb.velocity == Vector2(300, -200) and not bomb.landed and bomb.fuse_tick == fuse and bomb.arm_tick == 7, "deflect sets velocity and owner, wakes a resting bomb and keeps the fuse")
	var rocket: WorldObject = _pool.launch(ItemIds.OBJECT_ROCKET, 0, 10, Vector2(100, 100), Vector2(100, 0), 0, _cfg)
	_pool.deflect(rocket, Vector2(-100, 0), 11, 20, _cfg)
	_check(rocket.owner_peer == 11 and rocket.velocity == Vector2(-100, 0) and rocket.arm_tick == 26, "deflect re-arms a rocket 6 ticks after the deflection")
	var snapshot: Dictionary = _snapshot()
	_pool.deflect(rocket, Vector2(-100, 0), 11, 20, _cfg)
	_check(_snapshot() == snapshot, "deflecting twice on the same tick gives the same state")
	# The new owner's body does not set the rocket off at once, and the old owner's does.
	var new_owner: Bot = _add_bot(11, 1, Vector2(100, 100))
	_tick(20)
	_check(rocket.explode_tick == -1, "the deflector is safe from the rocket until it is armed")
	_tick(26)
	_check(rocket.explode_tick == 26 and new_owner.global_position == Vector2(100, 100), "the deflector is hit once the rocket is armed")
	var plate: WorldObject = _pool.launch(ItemIds.OBJECT_PLATE, 0, 10, Vector2(100, 100), Vector2.ZERO, 0, _cfg)
	_pool.deflect(plate, Vector2(50, 50), 11, 5, _cfg)
	_check(plate.owner_peer == 10 and plate.velocity == Vector2.ZERO, "deflect ignores a plate")
	var exploding: WorldObject = _pool.launch(ItemIds.OBJECT_BOMB, 1, 10, Vector2(100, 100), Vector2.ZERO, 0, _cfg)
	exploding.explode_tick = 5
	_pool.deflect(exploding, Vector2(50, 50), 11, 5, _cfg)
	_check(exploding.owner_peer == 10 and exploding.velocity == Vector2.ZERO, "deflect ignores an object that has already exploded")
	var idle: WorldObject = _pool.slots()[20]
	_pool.deflect(idle, Vector2(50, 50), 11, 5, _cfg)
	_pool.deflect(null, Vector2(50, 50), 11, 5, _cfg)
	_pool.deflect(bomb, Vector2(INF, 0), 12, 5, _cfg)
	_check(not idle.active and idle.velocity == Vector2.ZERO and bomb.owner_peer == 11, "deflect ignores an inactive slot, null and a velocity that is not finite")

	_pool.destroy(bomb, 5)
	_check(bomb.active, "destroy ignores a bomb")
	_pool.destroy(plate, 5)
	_check(not plate.active, "destroy deactivates a plate")
	_pool.destroy(plate, 5)
	_pool.destroy(null, 5)
	_check(true, "destroy on an inactive slot and on null does nothing")

# ---- gadgets ----

func _test_gadgets() -> void:
	await _begin()
	var bot: Bot = _add_bot(10, 0, Vector2(300, 300))
	var gadgets: BotGadgets = bot.gadgets
	_check(gadgets.gadget_a == ItemIds.COOKER_BOMB and gadgets.gadget_b == ItemIds.NONE, "a bot starts with one Cooker Bomb")
	_check(gadgets.give(ItemIds.SPRING_PLATE) and gadgets.gadget_b == ItemIds.SPRING_PLATE, "give fills the free slot")
	_check(not gadgets.give(ItemIds.COOKER_BOMB), "give refuses when both slots are full")
	_check(gadgets.gadget_a == ItemIds.COOKER_BOMB and gadgets.gadget_b == ItemIds.SPRING_PLATE, "a refused give changes nothing")
	_check(not gadgets.give(ItemIds.RIVET_GUN) and not gadgets.give(ItemIds.NONE), "give refuses an id that is not a gadget")

	# No input: nothing happens.
	gadgets._rollback_tick(_dt, 100, true)
	_check(gadgets.gadget_serial == 0 and gadgets.last_gadget_tick == -1 and gadgets.gadget_a == ItemIds.COOKER_BOMB, "without the gadget input nothing is used")
	bot.input.gadget = "yes"
	gadgets._rollback_tick(_dt, 100, true)
	_check(gadgets.gadget_serial == 0, "a gadget input that is not a bool is not a press")

	# Use: the bomb goes first, is consumed, the cooldown starts, the direction is the aim.
	bot.input.gadget = true
	bot.input.aim = Vector2(3, 4)
	gadgets._rollback_tick(_dt, 100, true)
	_check(gadgets.used_at(100) and not gadgets.used_at(101) and gadgets.used_id() == ItemIds.COOKER_BOMB, "the first gadget is used and used_id says which")
	_check(gadgets.gadget_a == ItemIds.SPRING_PLATE and gadgets.gadget_b == ItemIds.NONE, "using a gadget consumes it and moves the other up")
	_check(gadgets.gadget_serial == 1 and gadgets.gadget_ready_tick == 115, "the serial rises and the next use is 15 ticks (0.5 s) later")
	_near_v(gadgets.gadget_dir, Vector2(0.6, 0.8), 0.0001, "the throw direction is the aim direction")
	gadgets._rollback_tick(_dt, 101, true)
	gadgets._rollback_tick(_dt, 114, true)
	_check(gadgets.gadget_serial == 1 and gadgets.gadget_a == ItemIds.SPRING_PLATE, "no second use during the cooldown")
	bot.input.aim = Vector2.ZERO
	bot.facing = -1
	gadgets._rollback_tick(_dt, 115, true)
	_check(gadgets.gadget_serial == 2 and gadgets.used_id() == ItemIds.SPRING_PLATE and gadgets.gadget_dir == Vector2(-1, 0), "after the cooldown the next gadget is used, thrown along the facing when the aim is neutral")
	var serial: int = gadgets.gadget_serial
	var state: Array = [gadgets.last_gadget_tick, gadgets.gadget_ready_tick]
	gadgets._rollback_tick(_dt, 200, true)
	_check(gadgets.gadget_serial == serial and [gadgets.last_gadget_tick, gadgets.gadget_ready_tick] == state, "with nothing held the button does nothing")

	# A knocked-out bot does nothing.
	gadgets.reset_for_spawn(_cfg)
	_check(gadgets.gadget_a == ItemIds.COOKER_BOMB and gadgets.gadget_b == ItemIds.NONE and gadgets.gadget_ready_tick == 0, "reset_for_spawn gives one Cooker Bomb, ready")
	bot.vitals.knocked_out = true
	var before: Dictionary = _snapshot()
	gadgets._rollback_tick(_dt, 300, true)
	_check(_snapshot() == before, "a knocked-out bot cannot use a gadget")
	bot.vitals.knocked_out = false

	# The rules launch what was used: a bomb along the direction at the throw speed.
	bot.input.aim = Vector2(1, 0)
	bot.input.gadget = true
	_tick(300)
	var thrown: WorldObject = _slot_of(ItemIds.OBJECT_BOMB, 0, 0)
	_check(thrown.active and thrown.owner_peer == 10 and thrown.global_position == bot.center(), "a used Cooker Bomb appears at the bot, owned by it")
	_near_v(thrown.velocity, Vector2(_cfg.bomb_throw_speed * _px, 0), 0.0001, "the bomb is thrown at the config's throw speed along the aim")
	_check(thrown.spawn_tick == 300 and thrown.fuse_tick == 390 and thrown.launches == 1, "the bomb's ticks are set from the use tick")
	# The same use seen on a later tick launches nothing.
	bot.input.gadget = false
	_tick(301)
	_check(thrown.launches == 1, "a gadget use launches once, on its own tick only")
	# A plate is tossed at the plate throw speed.
	gadgets.give(ItemIds.SPRING_PLATE)
	bot.input.gadget = true
	bot.input.aim = Vector2(0, 1)
	_tick(400)
	var tossed: WorldObject = _slot_of(ItemIds.OBJECT_PLATE, 0, 0)
	_check(tossed.active and tossed.kind == ItemIds.OBJECT_PLATE, "a used Spring Plate appears as a plate")
	_near_v(tossed.velocity, Vector2(0, _cfg.plate_throw_speed * _px), 0.0001, "the plate is tossed at the config's plate throw speed")

	# The dummy never launches anything, and nothing breaks.
	await _begin()
	var dummy: Bot = _add_bot(Bot.DUMMY_PEER, _cfg.max_players, Vector2(300, 300))
	dummy.gadgets.last_gadget_tick = 5
	dummy.gadgets.last_gadget_id = ItemIds.COOKER_BOMB
	_tick(5)
	var any_active: bool = false
	for slot: WorldObject in _pool.slots():
		any_active = any_active or slot.active
	_check(not any_active, "a gadget use by the dummy launches nothing")

func _test_cycle_reset() -> void:
	await _begin()
	var bomb: WorldObject = _pool.launch(ItemIds.OBJECT_BOMB, 0, 1, Vector2.ZERO, Vector2.ZERO, 0, _cfg)
	bomb.fuse_tick = 100000
	var cycle: int = roundi(_cfg.hazard_cycle_time * float(_cfg.tick_rate))
	var start: int = 100
	var saved: int = MatchSettings.round_start_tick
	MatchSettings.round_start_tick = start
	bomb.spawn_tick = start + 5
	_tick(start)
	_check(bomb.active, "nothing is reset at the first start of the cycle")
	_tick(start + cycle - 1)
	_check(bomb.active, "nothing is reset just before the cycle ends")
	_tick(start + cycle)
	_check(not bomb.active, "an object of the old cycle is gone when the cycle restarts")
	bomb = _pool.launch(ItemIds.OBJECT_BOMB, 0, 1, Vector2.ZERO, Vector2.ZERO, start + cycle + 1, _cfg)
	bomb.fuse_tick = 100000
	_tick(start + cycle + 1)
	_check(bomb.active, "a new object survives the ticks after the reset")
	MatchSettings.round_start_tick = -1
	_tick(start + 2 * cycle)
	_check(bomb.active, "nothing is reset when no round has started")

	# (a) Objects of the old cycle do nothing on the boundary tick: a plate left on a spawn point
	# does not launch the bot that has just respawned on it.
	var floor_solids: Array[Rect2] = [Rect2(-5000, 1000, 10000, 500)]
	await _begin(floor_solids)
	MatchSettings.round_start_tick = start
	var fresh: Bot = _add_bot(11, 1, Vector2(600, 968))
	var plate: WorldObject = _pool.launch(ItemIds.OBJECT_PLATE, 0, 10, Vector2(600, 990), Vector2.ZERO, start + 50, _cfg)
	plate.landed = true
	plate.arm_tick = start + 60
	_check(_hit_for(_tick(start + cycle - 1), fresh) != null, "the old plate does launch a bot standing on it during its own cycle")
	var boundary_hits: Array[Hit] = _tick(start + cycle)
	_check(_hit_for(boundary_hits, fresh) == null and not plate.active, "on the boundary tick the old plate is gone before it can launch the bot that respawned there")

	# (b) A gadget thrown on the boundary tick itself survives it.
	await _begin()
	MatchSettings.round_start_tick = start
	var thrower: Bot = _add_bot(10, 0, Vector2(300, 300))
	thrower.input.gadget = true
	thrower.input.aim = Vector2(1, 0)
	_tick(start + cycle)
	var thrown: WorldObject = _slot_of(ItemIds.OBJECT_BOMB, 0, 0)
	_check(thrown.active and thrown.spawn_tick == start + cycle, "a bomb thrown on the boundary tick is not wiped by the reset")
	thrower.input.gadget = false
	_tick(start + cycle + 1)
	_check(thrown.active, "and it is still there on the next tick")

	# (c) A stall that skips the boundary tick still clears old objects, a plate included.
	await _begin(floor_solids)
	MatchSettings.round_start_tick = start
	var old_plate: WorldObject = _pool.launch(ItemIds.OBJECT_PLATE, 0, 10, Vector2(600, 990), Vector2.ZERO, start + 50, _cfg)
	old_plate.landed = true
	old_plate.arm_tick = start + 60
	var survivor: WorldObject = _pool.launch(ItemIds.OBJECT_PLATE, 1, 11, Vector2(900, 990), Vector2.ZERO, start + cycle + 2, _cfg)
	_tick(start + cycle - 1)
	_check(old_plate.active, "the old plate is live before the boundary")
	_tick(start + cycle + 5)
	_check(not old_plate.active, "a plate of the old cycle is cleared by the first tick after a skipped boundary")
	_check(survivor.active, "an object launched after the boundary is kept")
	# Idempotent: running the tick again gives the same.
	var snapshot: Dictionary = _snapshot()
	_tick(start + cycle + 5)
	_check(_snapshot() == snapshot, "running that tick again changes nothing")
	MatchSettings.round_start_tick = saved

# ---- idempotence ----

func _test_rerun_idempotent() -> void:
	var floor_rect: Array[Rect2] = [Rect2(-5000, 1000, 10000, 500), Rect2(1400, 0, 200, 1000)]
	await _begin(floor_rect)
	var thrower: Bot = _add_bot(10, 0, Vector2(300, 968))
	var target: Bot = _add_bot(11, 1, Vector2(700, 968))
	var standing: Bot = _add_bot(12, 2, Vector2(900, 968))
	thrower.facing = 1
	thrower.gadgets.give(ItemIds.SPRING_PLATE)
	var differing: int = 0
	var blasts_seen: int = 0
	var hits_seen: int = 0
	for tick: int in range(1, 160):
		thrower.input.gadget = tick == 5 or tick == 30
		thrower.input.aim = Vector2(0.8, -0.6) if tick == 5 else Vector2(1, 1)
		if tick == 8:
			_pool.launch(ItemIds.OBJECT_ROCKET, 0, 10, Vector2(400, 700), Vector2(12.0 * _px, 0), tick - 1, _cfg)
		if tick == 20:
			_pool.launch(ItemIds.OBJECT_PLATE, 2, 12, Vector2(900, 900), Vector2.ZERO, tick - 1, _cfg)
		var before: Dictionary = _snapshot()
		var first_hits: Array[Hit] = _tick(tick)
		var after_first: Dictionary = _snapshot()
		_restore(before)
		var second_hits: Array[Hit] = _tick(tick)
		if _snapshot() != after_first or _describe(first_hits) != _describe(second_hits):
			differing += 1
		hits_seen += first_hits.size()
	for slot: WorldObject in _pool.slots():
		blasts_seen += slot.blasts
	_check(blasts_seen >= 2 and hits_seen >= 3, "the idempotence scenario exercises blasts (%d) and hits (%d)" % [blasts_seen, hits_seen])
	_check(differing == 0, "running a tick again from the restored state gives the same state and hits on every tick (%d differed)" % differing)
	_check(target.vitals.health == target.vitals.health and standing.vitals.health == standing.vitals.health, "the scenario ran to the end")
