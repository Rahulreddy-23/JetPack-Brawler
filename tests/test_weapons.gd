extends Node
## Headless test of task C: the Arsenal's tick (fire cadence, ammo, swap, recoil, melee),
## WeaponRules.collect (hit tests, pellets, melee arc, rockets, world-object calls) and
## Pickups.resolve. Bots are instanced and given their input directly; the world objects are
## a test double because task D's implementation is not part of this tree. It opens no
## socket. Run:
##   godot --headless --path . res://tests/test_weapons.tscn
## Exits 0 when every check passes, 1 otherwise.

const BOT_SCENE: PackedScene = preload("res://scenes/bot.tscn")
const LAYOUT: ArenaLayout = preload("res://config/smelter.tres")
const TIMEOUT_SECONDS: float = 60.0
const EPS: float = 0.001
## Where the test shooter stands (pixels). Nothing is below it: no physics runs.
const ORIGIN: Vector2 = Vector2(2000.0, 2000.0)
const ARSENAL_STATE: Array[String] = [
	"active_slot", "picked_weapon", "picked_ammo", "fire_ready_tick", "last_shot_tick",
	"shots_fired", "last_shot_weapon", "shot_dir", "melee_ready_tick", "last_melee_tick", "melee_serial",
]

## Records every call the rules make on the world objects and answers with canned data.
class FakeObjects extends WorldObjects:
	var along: Array[ObjectCast] = []
	var near: Array[WorldObject] = []
	var calls: Array[Dictionary] = []
	var segments: Array[Array] = []
	var near_queries: Array[Array] = []

	func launch(kind: int, owner_slot: int, owner_peer: int, pos_px: Vector2, vel_px: Vector2, tick: int, _cfg: TuningConfig) -> WorldObject:
		calls.append({"fn": "launch", "kind": kind, "owner_slot": owner_slot, "owner_peer": owner_peer, "pos": pos_px, "vel": vel_px, "tick": tick})
		return null

	func targets_along(a: Vector2, b: Vector2, _cfg: TuningConfig) -> Array[ObjectCast]:
		segments.append([a, b])
		return along

	func targets_near(center_px: Vector2, radius_px: float, _cfg: TuningConfig) -> Array[WorldObject]:
		near_queries.append([center_px, radius_px])
		return near

	func deflect(slot: WorldObject, new_velocity: Vector2, new_owner_peer: int, tick: int, _cfg: TuningConfig) -> void:
		calls.append({"fn": "deflect", "slot": slot, "vel": new_velocity, "owner_peer": new_owner_peer, "tick": tick})

	func destroy(slot: WorldObject, tick: int) -> void:
		calls.append({"fn": "destroy", "slot": slot, "tick": tick})

## A gadget inventory that accepts or refuses, and records what was offered.
class FakeGadgets extends BotGadgets:
	var accept: bool = true
	var offered: Array[int] = []

	func give(id: int) -> bool:
		offered.append(id)
		return accept

var _cfg: TuningConfig = TuningConfig.get_default()
var _dt: float = 0.0
var _px: float = 0.0
var _failures: int = 0
var _checks: int = 0
var _nodes: Array[Node] = []
var _next_peer: int = 2

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
	_test_cadence()
	_test_ammo_and_fallback()
	_test_swap()
	_test_knocked_out()
	_test_recoil()
	await _test_recoil_motion()
	_test_aim_and_inputs()
	_test_melee_swing_state()
	_test_give_and_reset()
	_test_arsenal_rerun()
	_test_single_shot_hits()
	_test_scene_walls_and_order()
	_test_dashing_bots()
	_test_objects_on_the_line()
	_test_ties()
	_test_scrap_blaster()
	_test_zero_strength_pellet()
	_test_rocket_launch()
	await _test_rocket_at_wall()
	_test_melee_hits()
	_test_melee_objects()
	_test_melee_circle_edges()
	_test_melee_walls()
	_test_collect_rerun()
	_test_pickups()
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

func _clear() -> void:
	for node: Node in _nodes:
		node.free()
	_nodes.clear()

func _bot(at: Vector2 = ORIGIN) -> Bot:
	var bot: Bot = BOT_SCENE.instantiate() as Bot
	bot.peer_id = _next_peer
	bot.slot = _next_peer % _cfg.max_players
	_next_peer += 1
	bot.position = at
	add_child(bot)
	_nodes.append(bot)
	return bot

func _fake() -> FakeObjects:
	var objects: FakeObjects = FakeObjects.new()
	_nodes.append(objects)
	return objects

func _fake_gadgets() -> FakeGadgets:
	var gadgets: FakeGadgets = FakeGadgets.new()
	_nodes.append(gadgets)
	return gadgets

func _stats(id: int) -> WeaponStats:
	return _cfg.weapons[id]

# A duration in ticks, worked out here and not with the rules' own helper.
func _ticks(seconds: float) -> int:
	return int(round(seconds * float(_cfg.tick_rate)))

func _step(bot: Bot, tick: int) -> void:
	bot.arsenal._rollback_tick(_dt, tick, true)

func _snapshot(bot: Bot) -> Dictionary:
	var state: Dictionary = {"velocity": bot.velocity, "push_until": bot.vitals.push_until_tick}
	for prop: String in ARSENAL_STATE:
		state[prop] = bot.arsenal.get(prop)
	return state

func _restore(bot: Bot, state: Dictionary) -> void:
	bot.velocity = state["velocity"] as Vector2
	bot.vitals.push_until_tick = state["push_until"] as int
	for prop: String in ARSENAL_STATE:
		bot.arsenal.set(prop, state[prop])

# Hold the fire input for the given ticks and return the ticks at which the bot fired and
# which weapon it fired.
func _hold_fire(bot: Bot, from_tick: int, ticks: int) -> Array[Array]:
	var fired: Array[Array] = []
	bot.input.fire = true
	for tick: int in range(from_tick, from_tick + ticks):
		var weapon: int = bot.arsenal.active_weapon()
		_step(bot, tick)
		if bot.arsenal.fired_at(tick):
			fired.append([tick, weapon])
	bot.input.fire = false
	return fired

func _ticks_of(fired: Array[Array], weapon: int) -> Array[int]:
	var result: Array[int] = []
	for entry: Array in fired:
		if (entry[1] as int) == weapon:
			result.append(entry[0] as int)
	return result

func _arith(first: int, step: int, count: int) -> Array[int]:
	var result: Array[int] = []
	for i: int in count:
		result.append(first + i * step)
	return result

func _slot_object(kind: int, at: Vector2, velocity: Vector2 = Vector2.ZERO) -> WorldObject:
	var slot: WorldObject = WorldObject.new()
	slot.active = true
	slot.kind = kind
	slot.position = at
	slot.velocity = velocity
	add_child(slot)
	_nodes.append(slot)
	return slot

func _object_cast(slot: WorldObject, t: float) -> ObjectCast:
	var found: ObjectCast = ObjectCast.new()
	found.slot = slot
	found.t = t
	return found

# A bot that has fired at the given tick with the given weapon (state written by hand).
func _shooter(weapon: int, dir: Vector2, tick: int, at: Vector2 = ORIGIN) -> Bot:
	var bot: Bot = _bot(at)
	if weapon != ItemIds.RIVET_GUN:
		bot.arsenal.give_weapon(weapon, _cfg)
	bot.arsenal.last_shot_tick = tick
	bot.arsenal.shot_dir = dir
	return bot

func _collect(tick: int, bots: Array[Bot], objects: WorldObjects, solids: Array[Rect2]) -> Array[Hit]:
	var hits: Array[Hit] = []
	WeaponRules.collect(tick, bots, objects, solids, _cfg, hits)
	return hits

func _hits_text(hits: Array[Hit]) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for hit: Hit in hits:
		parts.append("%d>%d d=%.5f p=%s b=%s s=%s" % [hit.attacker_peer, hit.victim.peer_id, hit.damage, hit.push, hit.bullet, hit.scale_push])
	return "|".join(parts)

func _bots(list: Array) -> Array[Bot]:
	var result: Array[Bot] = []
	for entry: Variant in list:
		result.append(entry as Bot)
	return result

# ---- Arsenal: cadence, ammo, swap ----

func _test_cadence() -> void:
	for id: int in ItemIds.WEAPON_COUNT:
		var stats: WeaponStats = _stats(id)
		var interval: int = _ticks(stats.fire_interval)
		var bot: Bot = _bot()
		if id != ItemIds.RIVET_GUN:
			bot.arsenal.give_weapon(id, _cfg)
		# Ten seconds of held fire.
		var fired: Array[Array] = _hold_fire(bot, 100, 10 * _cfg.tick_rate)
		var own: Array[int] = _ticks_of(fired, id)
		var shots: int = mini(stats.ammo, ceili(float(10 * _cfg.tick_rate) / float(interval))) if id != ItemIds.RIVET_GUN else ceili(float(10 * _cfg.tick_rate) / float(interval))
		_check(own == _arith(100, interval, shots), "weapon %d fires every %d ticks, %d shots in 10 s (got %s)" % [id, interval, shots, own.slice(0, 5)])
		_check(bot.arsenal.shots_fired == fired.size(), "weapon %d: shots_fired counts every shot" % id)
		_check(bot.arsenal.last_shot_tick == (fired.back() as Array)[0] as int, "weapon %d: last_shot_tick is the latest shot" % id)
	_clear()

func _test_ammo_and_fallback() -> void:
	var bot: Bot = _bot()
	var ammo: int = _stats(ItemIds.SCRAP_BLASTER).ammo
	var interval: int = _ticks(_stats(ItemIds.SCRAP_BLASTER).fire_interval)
	bot.arsenal.give_weapon(ItemIds.SCRAP_BLASTER, _cfg)
	_check(bot.arsenal.picked_ammo == ammo and bot.arsenal.active_weapon() == ItemIds.SCRAP_BLASTER, "a picked weapon comes with a full magazine and is equipped")
	bot.input.fire = true
	var tick: int = 50
	var last: int = 0
	for shot: int in ammo:
		tick = 50 + shot * interval
		_step(bot, tick)
		_check(bot.arsenal.fired_at(tick) and bot.arsenal.picked_ammo == ammo - shot - 1, "shot %d fires and leaves %d" % [shot + 1, ammo - shot - 1])
		last = tick
	_check(bot.arsenal.picked_weapon == ItemIds.SCRAP_BLASTER and bot.arsenal.active_weapon() == ItemIds.SCRAP_BLASTER, "the emptied weapon is still there on the tick of its last shot (the resolver reads it)")
	bot.input.fire = false
	_step(bot, last + 1)
	_check(bot.arsenal.picked_weapon == ItemIds.NONE and bot.arsenal.active_slot == 0 and bot.arsenal.picked_ammo == 0, "the emptied weapon is dropped on the next tick")
	_check(bot.arsenal.active_weapon() == ItemIds.RIVET_GUN, "the bot falls back to the rivet gun")
	bot.input.fire = true
	var fired: Array[Array] = _hold_fire(bot, last + 2, 100)
	var rivet: Array[int] = _ticks_of(fired, ItemIds.RIVET_GUN)
	_check(rivet.size() == fired.size() and rivet[0] == last + interval and rivet[1] - rivet[0] == _ticks(_stats(ItemIds.RIVET_GUN).fire_interval), "the rivet gun takes over once the last shot's wait is over, at its own rate (first at %d)" % rivet[0])
	_check(bot.arsenal.picked_weapon == ItemIds.NONE, "the rivet gun never uses the picked slot")
	_clear()

func _test_swap() -> void:
	var bot: Bot = _bot()
	bot.input.swap = true
	_step(bot, 1)
	_check(bot.arsenal.active_slot == 0 and bot.arsenal.active_weapon() == ItemIds.RIVET_GUN, "swap does nothing while slot 1 is empty")
	bot.arsenal.give_weapon(ItemIds.BOLT_THROWER, _cfg)
	_check(bot.arsenal.active_slot == 1, "a picked-up weapon is equipped")
	_step(bot, 2)
	_check(bot.arsenal.active_slot == 0 and bot.arsenal.active_weapon() == ItemIds.RIVET_GUN and bot.arsenal.picked_weapon == ItemIds.BOLT_THROWER, "swap goes to the rivet gun and keeps the picked weapon")
	bot.input.swap = false
	_step(bot, 3)
	_check(bot.arsenal.active_slot == 0, "no swap input, no change")
	bot.input.swap = true
	_step(bot, 4)
	_check(bot.arsenal.active_slot == 1 and bot.arsenal.active_weapon() == ItemIds.BOLT_THROWER and bot.arsenal.picked_ammo == _stats(ItemIds.BOLT_THROWER).ammo, "swap goes back to the picked weapon with its ammo intact")
	bot.input.swap = "yes"
	_step(bot, 5)
	_check(bot.arsenal.active_slot == 1, "a swap value that is not a bool is ignored")
	# The slot in use decides what fires, and a swap on the same tick counts first.
	bot.input.swap = true
	bot.input.fire = true
	_step(bot, 6)
	_check(bot.arsenal.active_slot == 0 and bot.arsenal.fired_at(6) and bot.arsenal.picked_ammo == _stats(ItemIds.BOLT_THROWER).ammo, "a swap and a shot on one tick fire the weapon swapped to (rivet gun)")
	_clear()

func _test_knocked_out() -> void:
	var bot: Bot = _bot()
	bot.arsenal.give_weapon(ItemIds.SCRAP_BLASTER, _cfg)
	bot.velocity = Vector2(5.0, 6.0)
	bot.vitals.knocked_out = true
	bot.input.fire = true
	bot.input.melee = true
	bot.input.swap = true
	bot.input.aim = Vector2.DOWN
	var before: Dictionary = _snapshot(bot)
	for tick: int in range(10, 40):
		_step(bot, tick)
	_check(_snapshot(bot) == before, "a knocked-out bot neither fires, swings, swaps nor takes recoil (30 ticks, all inputs held)")
	# Even a weapon waiting to be dropped is left alone until the bot is back.
	bot.arsenal.picked_ammo = 0
	var dry: Dictionary = _snapshot(bot)
	_step(bot, 41)
	_check(_snapshot(bot) == dry, "a knocked-out bot does not drop an empty weapon")
	bot.vitals.knocked_out = false
	_step(bot, 42)
	_check(bot.arsenal.picked_weapon == ItemIds.NONE, "back in the game, the empty weapon is dropped")
	_clear()

func _test_recoil() -> void:
	var scrap: WeaponStats = _stats(ItemIds.SCRAP_BLASTER)
	var kick: float = scrap.recoil * _cfg.push_speed_scale * _px
	var cases: Array[Vector2] = [Vector2.DOWN, Vector2.LEFT, Vector2(0.6, 0.8), Vector2.UP]
	for aim: Vector2 in cases:
		var bot: Bot = _bot()
		bot.arsenal.give_weapon(ItemIds.SCRAP_BLASTER, _cfg)
		bot.velocity = Vector2(30.0, -20.0)
		bot.input.aim = aim
		bot.input.fire = true
		_step(bot, 10)
		_near_v(bot.velocity, Vector2(30.0, -20.0) - aim * kick, 0.0001, "scrap blaster aimed %s changes the shooter's velocity by exactly recoil x scale x height, opposite the shot" % aim)
		# Held fire during the wait must not kick again.
		var after: Vector2 = bot.velocity
		_step(bot, 11)
		_check(bot.velocity == after, "no extra recoil while the weapon is waiting")
	var down: Bot = _bot()
	down.arsenal.give_weapon(ItemIds.SCRAP_BLASTER, _cfg)
	down.input.aim = Vector2.DOWN
	down.input.fire = true
	_step(down, 10)
	_check(down.velocity.y < 0.0 and is_zero_approx(down.velocity.x), "firing downward gives a hop (velocity points up)")

	var dasher: Bot = _bot()
	dasher.arsenal.give_weapon(ItemIds.SCRAP_BLASTER, _cfg)
	dasher.input.move = Vector2.RIGHT
	dasher.input.dash = true
	dasher.input.aim = Vector2.DOWN
	dasher.input.fire = true
	dasher._rollback_tick(_dt, 10, true)
	var cooldown: float = dasher.dash_cooldown_left
	_step(dasher, 10)
	_check(dasher.dash_left == 0.0 and dasher.dash_cooldown_left == cooldown, "recoil ends an active dash and preserves its cooldown")
	_near_v(dasher.velocity, Vector2(_cfg.dash_exit_speed * _px, -kick), 0.0001, "recoil adds to normal dash exit velocity")
	dasher.input.dash = false
	var start_y: float = dasher.position.y
	dasher._rollback_tick(_dt, 11, true)
	_check(dasher.position.y < start_y, "a downward shot made while dashing still gives a recoil hop on the next tick")

	for id: int in [ItemIds.RIVET_GUN, ItemIds.BOLT_THROWER, ItemIds.ROCKET_TUBE]:
		var other: Bot = _bot()
		if id != ItemIds.RIVET_GUN:
			other.arsenal.give_weapon(id, _cfg)
		other.velocity = Vector2(1.0, 2.0)
		other.input.aim = Vector2.DOWN
		other.input.fire = true
		_step(other, 10)
		_check(other.arsenal.fired_at(10) and other.velocity == Vector2(1.0, 2.0), "weapon %d has no recoil" % id)
	_clear()

func _test_recoil_window_state() -> void:
	var window: int = _ticks(_cfg.push_window_time)
	var bot: Bot = _bot()
	bot.arsenal.give_weapon(ItemIds.SCRAP_BLASTER, _cfg)
	bot.input.fire = true
	_step(bot, 10)
	_check(bot.vitals.push_until_tick == 10 + 1 + window, "firing the scrap blaster opens the shooter's push window from the next tick for the config's length (until %d)" % bot.vitals.push_until_tick)
	var later: Bot = _bot()
	later.arsenal.give_weapon(ItemIds.SCRAP_BLASTER, _cfg)
	later.vitals.push_until_tick = 5000
	later.input.fire = true
	_step(later, 10)
	_check(later.vitals.push_until_tick == 5000, "a longer push window that is already open is not shortened")
	var rivet: Bot = _bot()
	rivet.input.fire = true
	_step(rivet, 10)
	_check(rivet.arsenal.fired_at(10) and rivet.vitals.push_until_tick == 0, "a weapon without recoil leaves the push window alone")
	_clear()

# A grounded bot is moved by the real movement code, tick by tick, and the Arsenal runs after it
# on every tick, the way netfox orders them. Returns the sideways travel and the highest rise.
func _drive(bot: Bot, ticks: int, keep_window: bool) -> Array[float]:
	var start: Vector2 = bot.position
	var rise: float = 0.0
	for tick: int in ticks:
		bot._rollback_tick(_dt, tick, true)
		bot.arsenal._rollback_tick(_dt, tick, true)
		if not keep_window:
			bot.vitals.push_until_tick = 0
		bot.input.fire = false
		rise = maxf(rise, start.y - bot.position.y)
	return [bot.position.x - start.x, rise]

func _test_recoil_motion() -> void:
	_test_recoil_window_state()
	var results: Dictionary = {}
	for variant: Array in [["right", Vector2.RIGHT, true], ["right", Vector2.RIGHT, false], ["down", Vector2.DOWN, true], ["down", Vector2.DOWN, false]]:
		var floor_body: StaticBody2D = StaticBody2D.new()
		floor_body.position = Vector2(0.0, 50.0)
		floor_body.collision_layer = Bot.LAYER_SOLID
		floor_body.collision_mask = 0
		var shape_node: CollisionShape2D = CollisionShape2D.new()
		var shape: RectangleShape2D = RectangleShape2D.new()
		shape.size = Vector2(200000.0, 100.0)
		shape_node.shape = shape
		floor_body.add_child(shape_node)
		add_child(floor_body)
		_nodes.append(floor_body)
		var bot: Bot = BOT_SCENE.instantiate() as Bot
		bot.position = Vector2(0.0, -_px / 2.0 - 0.5)
		add_child(bot)
		_nodes.append(bot)
		await get_tree().physics_frame
		await get_tree().physics_frame
		bot.arsenal.give_weapon(ItemIds.SCRAP_BLASTER, _cfg)
		_drive(bot, 5, true)
		bot.input.aim = variant[1] as Vector2
		bot.input.fire = true
		results["%s %s" % [variant[0], variant[2]]] = _drive(bot, 40, variant[2] as bool)
		_clear()
		await get_tree().physics_frame
		await get_tree().physics_frame
	var with_window: float = absf((results["right true"] as Array)[0] as float)
	var without_window: float = absf((results["right false"] as Array)[0] as float)
	var hop: float = (results["down true"] as Array)[1] as float
	var hop_plain: float = (results["down false"] as Array)[1] as float
	print("INFO scrap blaster recoil on the ground: %.1f px sideways with the push window, %.1f px without it; straight down the hop is %.1f px (%.1f px without the window)" % [with_window, without_window, hop, hop_plain])
	_check(with_window > without_window + 3.0, "a grounded bot firing the scrap blaster sideways slides measurably further with the push window than without it")
	_check(hop > 1.0 and absf(hop - hop_plain) < 0.01, "firing straight down gives a hop that the push window does not change")

func _test_aim_and_inputs() -> void:
	var bot: Bot = _bot()
	bot.facing = -1
	bot.input.fire = true
	bot.input.aim = Vector2.ZERO
	_step(bot, 0)
	_check(bot.arsenal.shot_dir == Vector2(-1.0, 0.0), "a neutral aim fires the way the bot faces")
	bot.facing = 1
	bot.input.aim = Vector2(_cfg.stick_deadzone * 0.5, 0.0)
	_step(bot, 100)
	_check(bot.arsenal.shot_dir == Vector2(1.0, 0.0), "an aim inside the dead zone counts as neutral")
	bot.input.aim = Vector2(0.0, 7.0)
	_step(bot, 200)
	_check(bot.arsenal.shot_dir == Vector2(0.0, 1.0), "an aim longer than 1 is cleaned and normalised")
	bot.input.aim = Vector2(0.3, 0.4)
	_step(bot, 300)
	_near_v(bot.arsenal.shot_dir, Vector2(0.6, 0.8), 0.00001, "a small aim past the dead zone is normalised to length 1")
	bot.input.aim = "up"
	_step(bot, 400)
	_check(bot.arsenal.shot_dir == Vector2(1.0, 0.0), "an aim that is not a vector is neutral")
	bot.input.aim = Vector2(NAN, 1.0)
	_step(bot, 500)
	_check(bot.arsenal.shot_dir == Vector2(1.0, 0.0), "an aim that is not finite is neutral")
	var shots: int = bot.arsenal.shots_fired
	bot.input.fire = 1
	_step(bot, 600)
	bot.input.fire = "true"
	_step(bot, 700)
	bot.input.fire = null
	_step(bot, 800)
	_check(bot.arsenal.shots_fired == shots, "a fire value that is not a bool is not pressed")
	_clear()

# ---- Arsenal: melee state ----

func _test_melee_swing_state() -> void:
	var bot: Bot = _bot()
	var cooldown: int = _ticks(_cfg.melee_cooldown)
	bot.input.aim = Vector2.UP
	bot.input.melee = true
	_step(bot, 10)
	_check(bot.arsenal.meleed_at(10) and bot.arsenal.last_melee_tick == 10 and bot.arsenal.melee_serial == 1, "a melee pulse swings at once")
	_check(bot.arsenal.melee_ready_tick == 10 + cooldown, "the next swing is one cooldown (%d ticks) later" % cooldown)
	_check(bot.arsenal.shot_dir == Vector2.UP, "the swing direction is the aim direction")
	_check(bot.arsenal.shots_fired == 0 and bot.arsenal.last_shot_tick == -1, "a swing is not a shot")
	var swings: Array[int] = []
	for tick: int in range(11, 11 + 4 * cooldown):
		_step(bot, tick)
		if bot.arsenal.meleed_at(tick):
			swings.append(tick)
	_check(swings == [10 + cooldown, 10 + 2 * cooldown, 10 + 3 * cooldown, 10 + 4 * cooldown], "held melee swings once per cooldown, no faster (got %s)" % [swings])
	_check(bot.arsenal.melee_serial == 5, "melee_serial counts every swing")
	bot.input.melee = false
	var serial: int = bot.arsenal.melee_serial
	_step(bot, 1000)
	_check(bot.arsenal.melee_serial == serial, "no melee input, no swing")
	bot.input.melee = "x"
	_step(bot, 1001)
	_check(bot.arsenal.melee_serial == serial, "a melee value that is not a bool is ignored")
	var out: Bot = _bot()
	out.vitals.knocked_out = true
	out.input.melee = true
	_step(out, 5)
	_check(out.arsenal.melee_serial == 0 and out.arsenal.last_melee_tick == -1, "a knocked-out bot does not swing")
	_clear()

func _test_give_and_reset() -> void:
	var bot: Bot = _bot()
	bot.arsenal.give_weapon(ItemIds.ROCKET_TUBE, _cfg)
	bot.arsenal.give_weapon(ItemIds.BOLT_THROWER, _cfg)
	_check(bot.arsenal.picked_weapon == ItemIds.BOLT_THROWER and bot.arsenal.picked_ammo == _stats(ItemIds.BOLT_THROWER).ammo, "a new weapon replaces the picked one with a full magazine")
	for bad: int in [ItemIds.RIVET_GUN, ItemIds.NONE, ItemIds.COOKER_BOMB, ItemIds.SPRING_PLATE, 99, -7]:
		bot.arsenal.give_weapon(bad, _cfg)
	_check(bot.arsenal.picked_weapon == ItemIds.BOLT_THROWER, "the rivet gun, gadgets and bad ids are not picked up")
	bot.arsenal.fire_ready_tick = 999
	bot.arsenal.melee_ready_tick = 999
	bot.arsenal.last_shot_tick = 5
	bot.arsenal.last_melee_tick = 6
	bot.arsenal.shots_fired = 4
	bot.arsenal.melee_serial = 3
	bot.arsenal.reset_for_spawn(_cfg)
	var a: BotArsenal = bot.arsenal
	_check(a.active_slot == 0 and a.picked_weapon == ItemIds.NONE and a.picked_ammo == 0 and a.fire_ready_tick == 0 and a.melee_ready_tick == 0 and a.last_shot_tick == -1 and a.last_melee_tick == -1, "reset_for_spawn leaves the rivet gun only, everything ready")
	_check(a.shots_fired == 4 and a.melee_serial == 3, "reset_for_spawn keeps the counters")
	bot.input.fire = true
	_step(bot, 0)
	_check(bot.arsenal.fired_at(0), "a reset bot can fire on tick 0")
	_clear()

func _test_arsenal_rerun() -> void:
	var bot: Bot = _bot()
	bot.arsenal.give_weapon(ItemIds.SCRAP_BLASTER, _cfg)
	bot.velocity = Vector2(3.0, 4.0)
	bot.input.aim = Vector2(0.6, 0.8)
	bot.input.fire = true
	bot.input.melee = true
	var before: Dictionary = _snapshot(bot)
	_step(bot, 77)
	var first: Dictionary = _snapshot(bot)
	_restore(bot, before)
	_step(bot, 77)
	_check(_snapshot(bot) == first and first != before, "running a tick again from its restored state gives the same Arsenal state and velocity")
	_clear()

# ---- WeaponRules: single shots ----

func _test_single_shot_hits() -> void:
	for id: int in [ItemIds.RIVET_GUN, ItemIds.BOLT_THROWER]:
		var stats: WeaponStats = _stats(id)
		var shooter: Bot = _shooter(id, Vector2.RIGHT, 40)
		var near: Bot = _bot(ORIGIN + Vector2(3.0 * _px, 0.0))
		var far: Bot = _bot(ORIGIN + Vector2(6.0 * _px, 0.0))
		var hits: Array[Hit] = _collect(40, _bots([shooter, near, far]), _fake(), [])
		_check(hits.size() == 1 and hits[0].victim == near, "weapon %d: only the nearest bot is hit" % id)
		var hit: Hit = hits[0]
		_check(hit.attacker_peer == shooter.peer_id and hit.damage == stats.damage and hit.push == Vector2.RIGHT * stats.push and hit.bullet and hit.scale_push, "weapon %d: the hit has the weapon's damage, push along the shot, bullet true and the shooter as attacker" % id)
		_clear()
	# The push follows the shot direction, whatever it is.
	var shooter: Bot = _shooter(ItemIds.BOLT_THROWER, Vector2(0.0, -1.0), 7)
	var above: Bot = _bot(ORIGIN + Vector2(0.0, -3.0 * _px))
	var hits: Array[Hit] = _collect(7, _bots([shooter, above]), _fake(), [])
	_check(hits.size() == 1 and hits[0].push == Vector2(0.0, -1.0) * _stats(ItemIds.BOLT_THROWER).push, "a shot straight up pushes straight up")
	_clear()
	# Range: the line ends at the weapon's range from the shooter's centre.
	var reach: float = _stats(ItemIds.RIVET_GUN).range_bh * _px
	var half_width: float = _cfg.bot_width_bh * _px / 2.0
	for spec: Array in [[-0.5, true], [0.5, false]]:
		var s: Bot = _shooter(ItemIds.RIVET_GUN, Vector2.RIGHT, 5)
		var target: Bot = _bot(ORIGIN + Vector2(reach + half_width + (spec[0] as float), 0.0))
		var result: Array[Hit] = _collect(5, _bots([s, target]), _fake(), [])
		_check((result.size() == 1) == (spec[1] as bool), "a bot %.1f px past the range edge of its near face is %s" % [spec[0] as float, ("hit" if (spec[1] as bool) else "missed")])
		_clear()
	# Nobody else around: the shooter is never hit, and a stale or foreign tick fires nothing.
	var lone: Bot = _shooter(ItemIds.RIVET_GUN, Vector2.RIGHT, 5)
	_check(_collect(5, _bots([lone]), _fake(), []).is_empty(), "the shooter is never hit by its own shot")
	var other: Bot = _bot(ORIGIN + Vector2(2.0 * _px, 0.0))
	_check(_collect(6, _bots([lone, other]), _fake(), []).is_empty(), "a bot that fired on another tick fires nothing now")
	# A shooter standing inside another bot's body still never hits itself, and hits the other.
	var inside: Bot = _bot(ORIGIN)
	var both: Array[Hit] = _collect(5, _bots([lone, inside]), _fake(), [])
	_check(both.size() == 1 and both[0].victim == inside, "a bot overlapping the shooter is hit, the shooter is not")
	# Dead shooters do not shoot.
	lone.vitals.knocked_out = true
	_check(_collect(5, _bots([lone, other]), _fake(), []).is_empty(), "a knocked-out shooter shoots nothing")
	_clear()

func _test_scene_walls_and_order() -> void:
	var shooter: Bot = _shooter(ItemIds.RIVET_GUN, Vector2.RIGHT, 9)
	var target: Bot = _bot(ORIGIN + Vector2(5.0 * _px, 0.0))
	var near_face: float = ORIGIN.x + 5.0 * _px - _cfg.bot_width_bh * _px / 2.0
	var wall_between: Rect2 = Rect2(ORIGIN.x + 2.0 * _px, ORIGIN.y - 300.0, 20.0, 600.0)
	var solids: Array[Rect2] = [wall_between]
	_check(_collect(9, _bots([shooter, target]), _fake(), solids).is_empty(), "a wall between the shooter and the bot blocks the shot")
	var wall_behind: Array[Rect2] = [Rect2(ORIGIN.x + 8.0 * _px, ORIGIN.y - 300.0, 20.0, 600.0)]
	_check(_collect(9, _bots([shooter, target]), _fake(), wall_behind).size() == 1, "a wall behind the bot does not block the shot")
	var wall_flush: Array[Rect2] = [Rect2(near_face, ORIGIN.y - 300.0, 20.0, 600.0)]
	_check(_collect(9, _bots([shooter, target]), _fake(), wall_flush).is_empty(), "when a wall and a bot are at the same distance the wall wins")
	var wall_above: Array[Rect2] = [Rect2(ORIGIN.x + 2.0 * _px, ORIGIN.y - 600.0, 20.0, 400.0)]
	_check(_collect(9, _bots([shooter, target]), _fake(), wall_above).size() == 1, "a wall off the line does not block the shot")
	# A knocked-out bot is skipped: the live one behind it is hit.
	var dead: Bot = _bot(ORIGIN + Vector2(2.0 * _px, 0.0))
	dead.vitals.knocked_out = true
	var hits: Array[Hit] = _collect(9, _bots([shooter, dead, target]), _fake(), [])
	_check(hits.size() == 1 and hits[0].victim == target, "a knocked-out bot is skipped and does not shield the bot behind it")
	# The dummy is an ordinary victim.
	var dummy: Bot = _bot(ORIGIN + Vector2(2.5 * _px, 0.0))
	dummy.peer_id = Bot.DUMMY_PEER
	var dummy_hits: Array[Hit] = _collect(9, _bots([shooter, dummy, target]), _fake(), [])
	_check(dummy_hits.size() == 1 and dummy_hits[0].victim == dummy, "the dummy takes a hit like any bot")
	# Two bots at the same distance (overlapping): the earlier one in the list is hit.
	var twin: Bot = _bot(target.global_position)
	var twin_hits: Array[Hit] = _collect(9, _bots([shooter, target, twin]), _fake(), [])
	_check(twin_hits.size() == 1 and twin_hits[0].victim == target, "a tie between bots goes to the first in the sorted list")
	_clear()

func _test_dashing_bots() -> void:
	var shooter: Bot = _shooter(ItemIds.RIVET_GUN, Vector2.RIGHT, 14)
	var dasher: Bot = _bot(ORIGIN + Vector2(2.0 * _px, 0.0))
	dasher.dash_left = 0.1
	var target: Bot = _bot(ORIGIN + Vector2(5.0 * _px, 0.0))
	var hits: Array[Hit] = _collect(14, _bots([shooter, dasher, target]), _fake(), [])
	_check(hits.size() == 1 and hits[0].victim == target, "a bullet flies through a dashing bot and hits the bot behind it")
	_check(_collect(14, _bots([shooter, dasher]), _fake(), []).is_empty(), "a dashing bot alone in the line gets no hit")
	dasher.dash_left = 0.0
	var plain: Array[Hit] = _collect(14, _bots([shooter, dasher, target]), _fake(), [])
	_check(plain.size() == 1 and plain[0].victim == dasher, "a bot whose dash has ended shields the bot behind it again")
	var blaster: Bot = _shooter(ItemIds.SCRAP_BLASTER, Vector2.RIGHT, 15)
	dasher.dash_left = 0.1
	_check(_collect(15, _bots([blaster, dasher]), _fake(), []).is_empty(), "scrap blaster pellets miss a dashing bot too")
	_clear()

func _test_objects_on_the_line() -> void:
	var speed_floor: float = _cfg.melee_deflect_speed * _px
	var target_offset: Vector2 = Vector2(5.0 * _px, 0.0)
	# A bomb nearer than the bot is shot away along the shot; the bot is not hit.
	var shooter: Bot = _shooter(ItemIds.RIVET_GUN, Vector2.RIGHT, 12)
	var target: Bot = _bot(ORIGIN + target_offset)
	var bomb: WorldObject = _slot_object(ItemIds.OBJECT_BOMB, ORIGIN + Vector2(2.0 * _px, 0.0))
	var objects: FakeObjects = _fake()
	objects.along = [_object_cast(bomb, 0.1)]
	var hits: Array[Hit] = _collect(12, _bots([shooter, target]), objects, [])
	var call: Dictionary = objects.calls[0] if objects.calls.size() == 1 else {}
	_check(hits.is_empty() and call.get("fn") == "deflect" and call["slot"] == bomb and (call["vel"] as Vector2).is_equal_approx(Vector2.RIGHT * speed_floor) and call["owner_peer"] == shooter.peer_id and call["tick"] == 12, "a bomb on the line is deflected along the shot at the deflect speed, owned by the shooter, and shields the bot behind")
	_check((objects.segments[0][0] as Vector2) == ORIGIN and (objects.segments[0][1] as Vector2).is_equal_approx(ORIGIN + Vector2.RIGHT * _stats(ItemIds.RIVET_GUN).range_bh * _px), "the bullet cast asks for the segment from the centre to the weapon's range")
	# A fast rocket keeps its own speed.
	var rocket: WorldObject = _slot_object(ItemIds.OBJECT_ROCKET, ORIGIN + Vector2(2.0 * _px, 0.0), Vector2(-2.0 * speed_floor, 0.0))
	var fast: FakeObjects = _fake()
	fast.along = [_object_cast(rocket, 0.1)]
	_collect(12, _bots([shooter, target]), fast, [])
	_check(fast.calls.size() == 1 and (fast.calls[0]["vel"] as Vector2).is_equal_approx(Vector2.RIGHT * 2.0 * speed_floor), "a rocket faster than the deflect speed keeps its speed and takes the shot's direction")
	# A plate is destroyed, not deflected.
	var plate: WorldObject = _slot_object(ItemIds.OBJECT_PLATE, ORIGIN + Vector2(2.0 * _px, 0.0))
	var plates: FakeObjects = _fake()
	plates.along = [_object_cast(plate, 0.1)]
	var plate_hits: Array[Hit] = _collect(12, _bots([shooter, target]), plates, [])
	_check(plate_hits.is_empty() and plates.calls.size() == 1 and plates.calls[0]["fn"] == "destroy" and plates.calls[0]["slot"] == plate and plates.calls[0]["tick"] == 12, "a plate on the line is destroyed")
	# A bot nearer than the object is hit and the object is left alone.
	var bot_first: FakeObjects = _fake()
	var behind: WorldObject = _slot_object(ItemIds.OBJECT_BOMB, ORIGIN + Vector2(7.0 * _px, 0.0))
	bot_first.along = [_object_cast(behind, 0.6)]
	var bot_hits: Array[Hit] = _collect(12, _bots([shooter, target]), bot_first, [])
	_check(bot_hits.size() == 1 and bot_first.calls.is_empty(), "a bot nearer than an object takes the hit and the object is untouched")
	# A wall nearer than the object protects it.
	var walled: FakeObjects = _fake()
	walled.along = [_object_cast(behind, 0.6)]
	var wall: Array[Rect2] = [Rect2(ORIGIN.x + 1.0 * _px, ORIGIN.y - 300.0, 20.0, 600.0)]
	_collect(12, _bots([shooter]), walled, wall)
	_check(walled.calls.is_empty(), "a wall nearer than an object stops the shot before it")
	# An object that is neither a bomb, rocket nor plate is ignored.
	var junk: WorldObject = _slot_object(ItemIds.NONE, ORIGIN + Vector2(2.0 * _px, 0.0))
	var ignored: FakeObjects = _fake()
	ignored.along = [_object_cast(junk, 0.1)]
	_collect(12, _bots([shooter]), ignored, [])
	_check(ignored.calls.is_empty(), "an object of an unknown kind is ignored")
	_clear()

func _test_ties() -> void:
	var reach: float = _stats(ItemIds.RIVET_GUN).range_bh * _px
	var a: Vector2 = ORIGIN
	var b: Vector2 = ORIGIN + Vector2.RIGHT * reach
	var shooter: Bot = _shooter(ItemIds.RIVET_GUN, Vector2.RIGHT, 16)
	var bomb: WorldObject = _slot_object(ItemIds.OBJECT_BOMB, ORIGIN + Vector2(2.0 * _px, 0.0))
	# A wall and an object at exactly the same distance: the wall stops the shot first.
	var wall: Rect2 = Rect2(ORIGIN.x + 2.0 * _px, ORIGIN.y - 300.0, 20.0, 600.0)
	var at_wall: FakeObjects = _fake()
	at_wall.along = [_object_cast(bomb, CombatGeometry.segment_rect(a, b, wall))]
	var solids: Array[Rect2] = [wall]
	_collect(16, _bots([shooter]), at_wall, solids)
	_check(at_wall.calls.is_empty(), "a wall and an object at the same distance: the wall wins and the object is left alone")
	# A bot and an object at exactly the same distance: the bot takes the hit.
	var target: Bot = _bot(ORIGIN + Vector2(5.0 * _px, 0.0))
	var at_bot: FakeObjects = _fake()
	at_bot.along = [_object_cast(bomb, CombatGeometry.segment_rect(a, b, target.body_rect()))]
	var hits: Array[Hit] = _collect(16, _bots([shooter, target]), at_bot, [])
	_check(hits.size() == 1 and hits[0].victim == target and at_bot.calls.is_empty(), "a bot and an object at the same distance: the bot wins and the object is left alone")
	_clear()

# ---- WeaponRules: scrap blaster ----

func _expected_angle(stats: WeaponStats, index: int) -> float:
	var spread: float = deg_to_rad(stats.spread_degrees)
	return -spread / 2.0 + spread * float(index) / float(stats.pellets - 1)

func _test_scrap_blaster() -> void:
	var stats: WeaponStats = _stats(ItemIds.SCRAP_BLASTER)
	var reach: float = stats.range_bh * _px
	for dir: Vector2 in [Vector2.RIGHT, Vector2(0.6, -0.8)]:
		var shooter: Bot = _shooter(ItemIds.SCRAP_BLASTER, dir, 20)
		var objects: FakeObjects = _fake()
		_collect(20, _bots([shooter]), objects, [])
		var ok: bool = objects.segments.size() == stats.pellets
		var worst: float = 0.0
		for i: int in mini(objects.segments.size(), stats.pellets):
			var segment: Array = objects.segments[i]
			var line: Vector2 = (segment[1] as Vector2) - (segment[0] as Vector2)
			worst = maxf(worst, line.distance_to(dir.rotated(_expected_angle(stats, i)) * reach))
			ok = ok and (segment[0] as Vector2) == ORIGIN
		_check(ok and worst < 0.001, "scrap blaster %s: %d pellet lines from the centre at fixed even angles across %.0f degrees, each as long as the range (worst error %.5f px)" % [dir, stats.pellets, stats.spread_degrees, worst])
		_clear()
	# The first and last pellet are the cone's edges, the middle ones sit between.
	_near(_expected_angle(stats, 0), -deg_to_rad(stats.spread_degrees) / 2.0, 0.0000001, "the first pellet is at minus half the spread")
	_near(_expected_angle(stats, stats.pellets - 1), deg_to_rad(stats.spread_degrees) / 2.0, 0.0000001, "the last pellet is at plus half the spread")

	# Falloff: a bot 3 bot heights away takes the four middle pellets, each at the strength
	# its own entry distance gives.
	var shooter: Bot = _shooter(ItemIds.SCRAP_BLASTER, Vector2.RIGHT, 21)
	var half_width: float = _cfg.bot_width_bh * _px / 2.0
	var half_height: float = _px / 2.0
	for gap: float in [3.0 * _px, 0.9 * reach + half_width]:
		var target: Bot = _bot(ORIGIN + Vector2(gap, 0.0))
		var face: float = gap - half_width
		var hits: Array[Hit] = _collect(21, _bots([shooter, target]), _fake(), [])
		var want: Array[String] = []
		for i: int in stats.pellets:
			var angle: float = _expected_angle(stats, i)
			if absf(face * tan(angle)) <= half_height:
				var strength: float = 1.0 - (face / cos(angle)) / reach
				want.append("%.4f|%.4f|%.4f" % [stats.damage * strength, Vector2.RIGHT.rotated(angle).x * stats.push * strength, Vector2.RIGHT.rotated(angle).y * stats.push * strength])
		var got: Array[String] = []
		for hit: Hit in hits:
			got.append("%.4f|%.4f|%.4f" % [hit.damage, hit.push.x, hit.push.y])
		_check(not want.is_empty() and got == want, "scrap blaster at %.0f px: %d pellet hits with damage and push falling off linearly with distance (got %s)" % [gap, want.size(), got])
		var all_bullets: bool = true
		for hit: Hit in hits:
			all_bullets = all_bullets and hit.bullet and hit.victim == target and hit.attacker_peer == shooter.peer_id
		_check(all_bullets, "every pellet hit is a bullet from the shooter on the victim")
		_clear()
		shooter = _shooter(ItemIds.SCRAP_BLASTER, Vector2.RIGHT, 21)
	# Right on the muzzle the pellets do full damage; at the range edge they do nothing.
	var close: Bot = _bot(ORIGIN)
	var point_blank: Array[Hit] = _collect(21, _bots([shooter, close]), _fake(), [])
	_check(point_blank.size() == stats.pellets and point_blank[0].damage == stats.damage and point_blank[0].push.is_equal_approx(Vector2.RIGHT.rotated(_expected_angle(stats, 0)) * stats.push), "pellets at point blank do full damage and full push")
	var edge_face: float = reach * cos(absf(_expected_angle(stats, 2))) - 0.01
	var edge: Bot = _bot(ORIGIN + Vector2(edge_face + half_width, 0.0))
	var edge_hits: Array[Hit] = _collect(21, _bots([shooter, edge]), _fake(), [])
	_check(edge_hits.size() >= 1 and edge_hits[0].damage < 0.001 * stats.damage and edge_hits[0].damage >= 0.0, "a pellet entering at the very end of the range does almost nothing")
	var beyond: Bot = _bot(ORIGIN + Vector2(2.0 * reach, 0.0))
	_check(_collect(21, _bots([shooter, beyond]), _fake(), []).is_empty(), "no pellet reaches a bot beyond the range")
	_clear()
	# Bolt thrower and rivet gun do not lose strength with distance.
	var bolt: Bot = _shooter(ItemIds.BOLT_THROWER, Vector2.RIGHT, 22)
	var far: Bot = _bot(ORIGIN + Vector2(0.9 * _stats(ItemIds.BOLT_THROWER).range_bh * _px, 0.0))
	var bolt_hits: Array[Hit] = _collect(22, _bots([bolt, far]), _fake(), [])
	_check(bolt_hits.size() == 1 and bolt_hits[0].damage == _stats(ItemIds.BOLT_THROWER).damage, "the bolt thrower does full damage near the end of its range")
	_clear()

func _test_zero_strength_pellet() -> void:
	# One pellet, no spread, so a bot whose near face is exactly at the range is touched at t = 1.
	var stats: WeaponStats = _stats(ItemIds.SCRAP_BLASTER)
	var pellets: int = stats.pellets
	var spread: float = stats.spread_degrees
	stats.pellets = 1
	stats.spread_degrees = 0.0
	var reach: float = stats.range_bh * _px
	for gap: float in [0.0, -0.1]:
		var shooter: Bot = _shooter(ItemIds.SCRAP_BLASTER, Vector2.RIGHT, 18)
		var target: Bot = _bot(ORIGIN + Vector2(reach + 16.0 + gap, 0.0))
		(target._shape.shape as RectangleShape2D).size = Vector2(32.0, _px)
		var hits: Array[Hit] = _collect(18, _bots([shooter, target]), _fake(), [])
		if gap == 0.0:
			_check(hits.is_empty(), "a pellet that only just reaches the end of its range makes no hit (no zero-damage, zero-push hit, so no knockout credit)")
		else:
			_check(hits.size() == 1 and hits[0].damage > 0.0 and hits[0].damage < 0.001 * stats.damage, "a pellet 0.1 px inside its range still hits, with almost no damage")
		_clear()
	stats.pellets = pellets
	stats.spread_degrees = spread

# ---- WeaponRules: rocket ----

func _test_rocket_launch() -> void:
	var stats: WeaponStats = _stats(ItemIds.ROCKET_TUBE)
	var half: Vector2 = Vector2(_cfg.bot_width_bh * _px, _px) / 2.0
	var cases: Array[Vector2] = [Vector2.RIGHT, Vector2.DOWN, Vector2(0.6, 0.8), Vector2(-0.8, -0.6)]
	for dir: Vector2 in cases:
		var shooter: Bot = _shooter(ItemIds.ROCKET_TUBE, dir, 33)
		var victim: Bot = _bot(ORIGIN + dir * 2.0 * _px)
		var objects: FakeObjects = _fake()
		var hits: Array[Hit] = _collect(33, _bots([shooter, victim]), objects, [])
		var leave: float = minf(half.x / absf(dir.x) if dir.x != 0.0 else INF, half.y / absf(dir.y) if dir.y != 0.0 else INF)
		var launched: bool = objects.calls.size() == 1 and objects.calls[0]["fn"] == "launch"
		_check(launched and hits.is_empty() and objects.segments.is_empty(), "rocket tube %s: one launch, no hit test, no hit" % dir)
		if launched:
			var call: Dictionary = objects.calls[0]
			_check(call["kind"] == ItemIds.OBJECT_ROCKET and call["owner_slot"] == shooter.slot and call["owner_peer"] == shooter.peer_id and call["tick"] == 33, "rocket tube %s: launched as a rocket for the shooter's slot and peer on the fire tick" % dir)
			_near_v(call["vel"] as Vector2, dir * stats.projectile_speed * _px, 0.0001, "rocket tube %s: velocity is the projectile speed along the shot" % dir)
			_near_v(call["pos"] as Vector2, ORIGIN + dir * (leave + stats.projectile_radius * _px), 0.0001, "rocket tube %s: starts just outside the body, where the aim line leaves it" % dir)
		_clear()
	# Other weapons never launch anything.
	var rivet: Bot = _shooter(ItemIds.RIVET_GUN, Vector2.RIGHT, 5)
	var objects: FakeObjects = _fake()
	_collect(5, _bots([rivet]), objects, [])
	_check(objects.calls.is_empty(), "the rivet gun launches nothing")
	_clear()

# A shooter flush against a wall fires into it with the real object pool and gadget rules: the
# rocket must start at the wall face (not 16 px inside), explode there on the launch tick, and
# hurt the shooter for the distance from its centre to the face.
func _test_rocket_at_wall() -> void:
	var stats: WeaponStats = _stats(ItemIds.ROCKET_TUBE)
	var shooter: Bot = _shooter(ItemIds.ROCKET_TUBE, Vector2.RIGHT, 33)
	var face: float = shooter.body_rect().end.x
	var wall: Rect2 = Rect2(face, ORIGIN.y - 500.0, 400.0, 1000.0)
	var solids: Array[Rect2] = [wall]
	var pool: WorldObjects = WorldObjects.new()
	pool.solids = solids
	pool.bounds_px = Rect2(-100000.0, -100000.0, 200000.0, 200000.0)
	add_child(pool)
	_nodes.append(pool)
	await get_tree().process_frame
	var hits: Array[Hit] = []
	WeaponRules.collect(33, _bots([shooter]), pool, solids, _cfg, hits)
	GadgetRules.collect(33, _bots([shooter]), pool, solids, _cfg, hits)
	var rocket: WorldObject = null
	for slot: WorldObject in pool.slots():
		if slot.kind == ItemIds.OBJECT_ROCKET and slot.launches > 0:
			rocket = slot
	_check(rocket != null and rocket.blasts == 1 and rocket.explode_tick == 33, "a rocket fired flush against a wall explodes on the launch tick")
	if rocket == null:
		return
	_near(rocket.global_position.x, face, 0.01, "its blast centre is at the wall face, not inside the wall")
	var want: float = stats.blast_damage * (1.0 - (shooter.body_rect().size.x / 2.0 / _px) / stats.blast_radius)
	var own: Hit = null
	for hit: Hit in hits:
		if hit.victim == shooter:
			own = hit
	_check(own != null, "the shooter is in its own blast")
	if own != null:
		_near(own.damage, want, 0.001, "the blast damage is the one for the half body width from the centre")
		shooter.vitals.health = _cfg.max_health
		# The test shooter stands far below the Smelter's floor, so the metal would take it: use a
		# taller arena for this step.
		var tall: ArenaLayout = LAYOUT.duplicate() as ArenaLayout
		tall.bounds = Rect2(0.0, 0.0, 1000.0, 1000.0)
		CombatRules.apply(33, _bots([shooter]), hits, tall, _cfg)
		_near(_cfg.max_health - shooter.vitals.health, want * _cfg.self_damage_scale, 0.001, "the shooter loses the blast damage times the self damage scale from its health")

# ---- WeaponRules: melee ----

func _swinger(dir: Vector2, tick: int) -> Bot:
	var bot: Bot = _bot()
	bot.arsenal.last_melee_tick = tick
	bot.arsenal.shot_dir = dir
	return bot

# A bot whose rectangle has the given point as its top-right corner.
func _bot_top_right_at(corner: Vector2) -> Bot:
	return _bot(corner + Vector2(-_cfg.bot_width_bh * _px / 2.0, _px / 2.0))

# A bot whose rectangle has the given point as its bottom-right corner.
func _bot_bottom_right_at(corner: Vector2) -> Bot:
	return _bot(corner + Vector2(-_cfg.bot_width_bh * _px / 2.0, -_px / 2.0))

func _test_melee_hits() -> void:
	var reach: float = _cfg.melee_range * _px
	var half_arc: float = deg_to_rad(_cfg.melee_arc_degrees) / 2.0
	var half_width: float = _cfg.bot_width_bh * _px / 2.0
	var swinger: Bot = _swinger(Vector2.RIGHT, 50)
	# Range edge: a bot straight ahead whose near face is just inside or outside the reach.
	for spec: Array in [[-0.5, true], [0.5, false]]:
		var target: Bot = _bot(ORIGIN + Vector2(reach + half_width + (spec[0] as float), 0.0))
		var hits: Array[Hit] = _collect(50, _bots([swinger, target]), _fake(), [])
		_check((hits.size() == 1) == (spec[1] as bool), "melee: a bot whose near face is %.1f px from the range edge is %s" % [spec[0] as float, ("hit" if (spec[1] as bool) else "missed")])
		_clear()
		swinger = _swinger(Vector2.RIGHT, 50)
	# Angle edge, both sides: a bot's near corner just inside or just outside the arc edge.
	for side: float in [1.0, -1.0]:
		for spec: Array in [[-0.5, true], [0.5, false]]:
			var angle: float = side * (half_arc + deg_to_rad(spec[0] as float))
			var corner: Vector2 = ORIGIN + Vector2.RIGHT.rotated(angle) * reach * 0.6
			var target: Bot = _bot_top_right_at(corner) if side > 0.0 else _bot_bottom_right_at(corner)
			var hits: Array[Hit] = _collect(50, _bots([swinger, target]), _fake(), [])
			_check((hits.size() == 1) == (spec[1] as bool), "melee: a corner %.1f degrees %s the %s arc edge is %s" % [absf(spec[0] as float), ("inside" if (spec[0] as float) < 0.0 else "outside"), ("lower" if side > 0.0 else "upper"), ("hit" if (spec[1] as bool) else "missed")])
			_clear()
			swinger = _swinger(Vector2.RIGHT, 50)
	# A bot that crosses the arc without a corner in it (a wide face seen edge-on) is hit.
	var broad: Bot = _bot(ORIGIN + Vector2(reach * 0.6 + half_width, 0.0))
	_check(_collect(50, _bots([swinger, broad]), _fake(), []).size() == 1, "melee: a bot straight ahead is hit")
	_clear()
	swinger = _swinger(Vector2.RIGHT, 50)
	# Behind, and the swinger itself.
	var behind: Bot = _bot(ORIGIN + Vector2(-0.6 * _px, 0.0))
	_check(_collect(50, _bots([swinger, behind]), _fake(), []).is_empty(), "melee: a bot behind the swinger is not hit, and neither is the swinger")
	_clear()
	swinger = _swinger(Vector2.RIGHT, 50)
	# A body that contains the swinger's centre is in the arc.
	var overlap: Bot = _bot(ORIGIN + Vector2(2.0, 0.0))
	var overlap_hits: Array[Hit] = _collect(50, _bots([swinger, overlap]), _fake(), [])
	_check(overlap_hits.size() == 1 and overlap_hits[0].victim == overlap, "melee: a bot overlapping the swinger is hit")
	_clear()
	swinger = _swinger(Vector2.RIGHT, 50)
	# Hit fields and push direction: away from the swinger, not along the swing.
	var up_right: Bot = _bot(ORIGIN + Vector2(0.9 * _px, -0.4 * _px))
	var fields: Array[Hit] = _collect(50, _bots([swinger, up_right]), _fake(), [])
	var away: Vector2 = (up_right.global_position - ORIGIN).normalized()
	_check(fields.size() == 1 and fields[0].victim == up_right and fields[0].attacker_peer == swinger.peer_id and fields[0].damage == _cfg.melee_damage and fields[0].push.is_equal_approx(away * _cfg.melee_push) and not fields[0].bullet and fields[0].scale_push, "melee hit: melee damage, push away from the swinger x melee push, not a bullet, the swinger as attacker")
	_clear()
	swinger = _swinger(Vector2.RIGHT, 50)
	# Several bots, a knocked-out one and the swing direction.
	var one: Bot = _bot(ORIGIN + Vector2(0.9 * _px, 0.0))
	var two: Bot = _bot(ORIGIN + Vector2(0.9 * _px, 0.2 * _px))
	var dead: Bot = _bot(ORIGIN + Vector2(0.8 * _px, -0.2 * _px))
	dead.vitals.knocked_out = true
	var many: Array[Hit] = _collect(50, _bots([swinger, one, two, dead]), _fake(), [])
	_check(many.size() == 2 and many[0].victim == one and many[1].victim == two, "melee hits every live bot in the arc, in order, and skips a knocked-out one")
	_clear()
	var up: Bot = _swinger(Vector2.UP, 50)
	var over: Bot = _bot(ORIGIN + Vector2(0.0, -0.9 * _px))
	var beside: Bot = _bot(ORIGIN + Vector2(1.2 * _px, 0.3 * _px))
	var up_hits: Array[Hit] = _collect(50, _bots([up, over, beside]), _fake(), [])
	_check(up_hits.size() == 1 and up_hits[0].victim == over, "melee follows the swing direction (up hits the bot above, not the one beside)")
	_clear()
	# A swing on another tick does nothing; a knocked-out swinger does nothing.
	var late: Bot = _swinger(Vector2.RIGHT, 49)
	var close: Bot = _bot(ORIGIN + Vector2(0.9 * _px, 0.0))
	_check(_collect(50, _bots([late, close]), _fake(), []).is_empty(), "a swing from another tick does nothing")
	late.arsenal.last_melee_tick = 50
	late.vitals.knocked_out = true
	_check(_collect(50, _bots([late, close]), _fake(), []).is_empty(), "a knocked-out bot's swing does nothing")
	_clear()

func _test_melee_objects() -> void:
	var reach: float = _cfg.melee_range * _px
	var half_arc: float = deg_to_rad(_cfg.melee_arc_degrees) / 2.0
	var floor_speed: float = _cfg.melee_deflect_speed * _px
	var swinger: Bot = _swinger(Vector2.RIGHT, 60)
	var slow: WorldObject = _slot_object(ItemIds.OBJECT_BOMB, ORIGIN + Vector2(0.5 * reach, 0.0), Vector2(100.0, 0.0))
	var fast: WorldObject = _slot_object(ItemIds.OBJECT_ROCKET, ORIGIN + Vector2(0.5 * reach, 10.0), Vector2(0.0, 3.0 * floor_speed))
	var inside_edge: WorldObject = _slot_object(ItemIds.OBJECT_BOMB, ORIGIN + Vector2.RIGHT.rotated(half_arc - deg_to_rad(0.5)) * 0.5 * reach)
	var outside_edge: WorldObject = _slot_object(ItemIds.OBJECT_BOMB, ORIGIN + Vector2.RIGHT.rotated(half_arc + deg_to_rad(30.0)) * 0.5 * reach)
	var outside_edge_up: WorldObject = _slot_object(ItemIds.OBJECT_BOMB, ORIGIN + Vector2.RIGHT.rotated(-half_arc - deg_to_rad(30.0)) * 0.5 * reach)
	var behind: WorldObject = _slot_object(ItemIds.OBJECT_BOMB, ORIGIN + Vector2(-0.5 * reach, 0.0))
	var plate: WorldObject = _slot_object(ItemIds.OBJECT_PLATE, ORIGIN + Vector2(0.5 * reach, 0.0))
	var on_apex: WorldObject = _slot_object(ItemIds.OBJECT_BOMB, ORIGIN)
	var objects: FakeObjects = _fake()
	objects.near = [slow, fast, inside_edge, outside_edge, outside_edge_up, behind, plate, on_apex]
	var hits: Array[Hit] = _collect(60, _bots([swinger]), objects, [])
	_check(hits.is_empty(), "a swing at objects alone makes no hit")
	_check(objects.near_queries.size() == 1 and (objects.near_queries[0][0] as Vector2) == ORIGIN and is_equal_approx(objects.near_queries[0][1] as float, reach), "the arc asks for objects within the melee range of the swinger's centre")
	var by_slot: Dictionary = {}
	for call: Dictionary in objects.calls:
		by_slot[call["slot"]] = call
	var expected: Array[WorldObject] = [slow, fast, inside_edge, on_apex]
	var unexpected: Array[WorldObject] = [outside_edge, outside_edge_up, behind, plate]
	var as_expected: bool = objects.calls.size() == expected.size()
	for slot: WorldObject in expected:
		as_expected = as_expected and by_slot.has(slot)
	var untouched: bool = true
	for slot: WorldObject in unexpected:
		untouched = untouched and not by_slot.has(slot)
	_check(as_expected and untouched, "bombs and rockets in the arc (edge just inside included) are deflected; ones outside the angle, behind, and plates are not (%d calls)" % objects.calls.size())
	if by_slot.has(slow):
		var call: Dictionary = by_slot[slow]
		_check(call["fn"] == "deflect" and (call["vel"] as Vector2).is_equal_approx(Vector2.RIGHT * floor_speed) and call["owner_peer"] == swinger.peer_id and call["tick"] == 60, "a slow bomb leaves at the deflect speed along the swing, owned by the swinger")
	if by_slot.has(fast):
		_check((by_slot[fast]["vel"] as Vector2).is_equal_approx(Vector2.RIGHT * 3.0 * floor_speed), "a faster rocket keeps its speed but takes the swing's direction")
	_clear()

func _test_melee_circle_edges() -> void:
	var reach: float = _cfg.melee_range * _px
	var half_arc: float = deg_to_rad(_cfg.melee_arc_degrees) / 2.0
	var radius: float = _cfg.bomb_radius * _px
	var swinger: Bot = _swinger(Vector2.RIGHT, 80)
	var edge: Vector2 = Vector2.RIGHT.rotated(half_arc)
	var away: Vector2 = edge.rotated(PI / 2.0)
	var inside: WorldObject = _slot_object(ItemIds.OBJECT_BOMB, ORIGIN + edge * 0.5 * reach + away * (radius - 1.0))
	var outside: WorldObject = _slot_object(ItemIds.OBJECT_BOMB, ORIGIN + edge * 0.5 * reach + away * (radius + 1.0))
	var rocket_edge: WorldObject = _slot_object(ItemIds.OBJECT_ROCKET, ORIGIN + Vector2(reach + 1.0, 0.0))
	var past_rocket: WorldObject = _slot_object(ItemIds.OBJECT_ROCKET, ORIGIN + Vector2(reach + _cfg.weapons[ItemIds.ROCKET_TUBE].projectile_radius * _px + 1.0, 0.0))
	var objects: FakeObjects = _fake()
	objects.near = [inside, outside, rocket_edge, past_rocket]
	_collect(80, _bots([swinger]), objects, [])
	var hit_slots: Array[WorldObject] = []
	for call: Dictionary in objects.calls:
		hit_slots.append(call["slot"] as WorldObject)
	_check(hit_slots == [inside, rocket_edge], "a bomb or rocket whose edge is inside the arc is deflected, one whose edge is just outside the angle or the range is not (deflected: %d)" % hit_slots.size())
	_clear()

func _test_melee_walls() -> void:
	var solids: Array[Rect2] = LAYOUT.solid_rects_px(_px)
	# The Smelter's pillar (11, 9, 1 x 7 bot heights): one bot on each side, a bot height apart.
	var pillar: Rect2 = Rect2(LAYOUT.solids[5].position * _px, LAYOUT.solids[5].size * _px)
	var half_width: float = _cfg.bot_width_bh * _px / 2.0
	var y: float = 12.0 * _px
	var left: Bot = _bot(Vector2(pillar.position.x - half_width, y))
	left.arsenal.last_melee_tick = 90
	left.arsenal.shot_dir = Vector2.RIGHT
	var right: Bot = _bot(Vector2(pillar.end.x + half_width, y))
	var hits: Array[Hit] = _collect(90, _bots([left, right]), _fake(), solids)
	_check(hits.is_empty(), "a swing does not reach a bot on the other side of a pillar, though it is within the melee range")
	var open: Array[Hit] = _collect(90, _bots([left, right]), _fake(), [])
	_check(open.size() == 1 and open[0].victim == right, "the same two bots without the pillar: the swing hits")
	# A wall behind the target does not matter.
	var wall_behind: Array[Rect2] = [Rect2(pillar.end.x + 2.0 * half_width + 1.0, y - 300.0, 40.0, 600.0)]
	var reached: Array[Hit] = _collect(90, _bots([left, right]), _fake(), wall_behind)
	_check(reached.size() == 1, "a wall behind the target does not stop the swing")
	# A bomb on the far side of the pillar is not deflected, and the same bomb without it is.
	var bomb: WorldObject = _slot_object(ItemIds.OBJECT_BOMB, Vector2(pillar.end.x + 0.3 * _px, y))
	var blocked: FakeObjects = _fake()
	blocked.near = [bomb]
	_collect(90, _bots([left]), blocked, solids)
	_check(blocked.calls.is_empty(), "a swing does not deflect a bomb on the other side of a pillar")
	var free: FakeObjects = _fake()
	free.near = [bomb]
	_collect(90, _bots([left]), free, [])
	_check(free.calls.size() == 1, "the same bomb without the pillar is deflected")
	_clear()

func _test_collect_rerun() -> void:
	# The same tick twice over the same state gives the same hits and the same calls.
	var shooter: Bot = _shooter(ItemIds.SCRAP_BLASTER, Vector2.RIGHT, 70)
	shooter.arsenal.last_melee_tick = 70
	var target: Bot = _bot(ORIGIN + Vector2(0.9 * _px, 0.0))
	var bomb: WorldObject = _slot_object(ItemIds.OBJECT_BOMB, ORIGIN + Vector2(0.5 * _px, 0.0))
	var objects: FakeObjects = _fake()
	objects.near = [bomb]
	var first: String = _hits_text(_collect(70, _bots([shooter, target]), objects, []))
	var first_calls: int = objects.calls.size()
	var second: String = _hits_text(_collect(70, _bots([shooter, target]), objects, []))
	_check(first == second and not first.is_empty(), "running collect again for the same tick gives the same hits")
	_check(objects.calls.size() == 2 * first_calls and first_calls > 0 and objects.calls[0]["vel"] == objects.calls[first_calls]["vel"], "and the same world-object calls")
	_clear()

# ---- Pickups ----

func _spot_node(pickups: Pickups, index: int) -> PickupSpot:
	return pickups.spots()[index]

func _on_spot(spot: PickupSpot, offset: Vector2 = Vector2.ZERO) -> Bot:
	return _bot(spot.global_position + offset)

func _test_pickups() -> void:
	var pickups: Pickups = Pickups.new()
	pickups.layout = LAYOUT
	add_child(pickups)
	_nodes.append(pickups)
	var respawn: int = _ticks(_cfg.pickup_respawn_time)
	var bolt_spot: PickupSpot = _spot_node(pickups, 0)
	var plate_spot: PickupSpot = _spot_node(pickups, 3)
	_check(bolt_spot.item == ItemIds.BOLT_THROWER and plate_spot.item == ItemIds.SPRING_PLATE, "the Smelter's spots offer the expected items")

	var taker: Bot = _on_spot(bolt_spot)
	pickups.resolve(100, _bots([taker]), _cfg)
	_check(taker.arsenal.picked_weapon == ItemIds.BOLT_THROWER and taker.arsenal.picked_ammo == _stats(ItemIds.BOLT_THROWER).ammo and taker.arsenal.active_slot == 1, "a bot on a ready weapon spot takes the weapon with a full magazine")
	_check(bolt_spot.ready_tick == 100 + respawn, "the spot is empty for the respawn time (%d ticks)" % respawn)
	var other: Bot = _on_spot(bolt_spot)
	pickups.resolve(101, _bots([taker, other]), _cfg)
	_check(other.arsenal.picked_weapon == ItemIds.NONE, "nobody can take a spot that is not ready")
	pickups.resolve(100 + respawn - 1, _bots([other]), _cfg)
	_check(other.arsenal.picked_weapon == ItemIds.NONE, "the last tick before the respawn is still empty")
	pickups.resolve(100 + respawn, _bots([other]), _cfg)
	_check(other.arsenal.picked_weapon == ItemIds.BOLT_THROWER and bolt_spot.ready_tick == 100 + 2 * respawn, "the spot is on offer again from its ready tick, inclusive")
	_clear()
	pickups = Pickups.new()
	pickups.layout = LAYOUT
	add_child(pickups)
	_nodes.append(pickups)
	bolt_spot = _spot_node(pickups, 0)
	plate_spot = _spot_node(pickups, 3)

	# Reach: the body must overlap the pickup circle.
	var radius: float = _cfg.pickup_radius * _px
	var half_width: float = _cfg.bot_width_bh * _px / 2.0
	var just_in: Bot = _on_spot(bolt_spot, Vector2(half_width + radius - 0.5, 0.0))
	pickups.resolve(5, _bots([just_in]), _cfg)
	_check(just_in.arsenal.picked_weapon == ItemIds.BOLT_THROWER, "a body just inside the pickup radius takes the item")
	bolt_spot.ready_tick = 0
	var just_out: Bot = _on_spot(bolt_spot, Vector2(half_width + radius + 0.5, 0.0))
	pickups.resolve(5, _bots([just_out]), _cfg)
	_check(just_out.arsenal.picked_weapon == ItemIds.NONE and bolt_spot.ready_tick == 0, "a body just outside it does not")

	# A knocked-out bot and the dummy take nothing; the item stays on the spot.
	var dead: Bot = _on_spot(bolt_spot)
	dead.vitals.knocked_out = true
	var dummy: Bot = _on_spot(bolt_spot)
	dummy.peer_id = Bot.DUMMY_PEER
	pickups.resolve(5, _bots([dead, dummy]), _cfg)
	_check(dead.arsenal.picked_weapon == ItemIds.NONE and dummy.arsenal.picked_weapon == ItemIds.NONE and bolt_spot.ready_tick == 0, "a knocked-out bot and the dummy do not pick anything up")

	# Several bots on one spot: the lowest peer id wins, whatever the list order.
	var high: Bot = _on_spot(bolt_spot)
	high.peer_id = 9
	var low: Bot = _on_spot(bolt_spot, Vector2(3.0, 0.0))
	low.peer_id = 3
	var mid: Bot = _on_spot(bolt_spot, Vector2(-3.0, 0.0))
	mid.peer_id = 6
	pickups.resolve(5, _bots([high, mid, low]), _cfg)
	_check(low.arsenal.picked_weapon == ItemIds.BOLT_THROWER and high.arsenal.picked_weapon == ItemIds.NONE and mid.arsenal.picked_weapon == ItemIds.NONE, "with several bots on a spot the lowest peer id gets it")
	bolt_spot.ready_tick = 0

	# A new weapon replaces the picked one.
	var holder: Bot = _on_spot(bolt_spot)
	holder.arsenal.give_weapon(ItemIds.SCRAP_BLASTER, _cfg)
	holder.arsenal.picked_ammo = 2
	pickups.resolve(6, _bots([holder]), _cfg)
	_check(holder.arsenal.picked_weapon == ItemIds.BOLT_THROWER and holder.arsenal.picked_ammo == _stats(ItemIds.BOLT_THROWER).ammo, "picking up a weapon replaces the one in slot 1")

	# The Spring Plate is taken only when the gadget slots have room.
	var full: Bot = _on_spot(plate_spot)
	var refusing: FakeGadgets = _fake_gadgets()
	refusing.accept = false
	full.gadgets = refusing
	pickups.resolve(7, _bots([full]), _cfg)
	_check(refusing.offered == [ItemIds.SPRING_PLATE] and plate_spot.ready_tick == 0, "a Spring Plate is offered to the gadgets and, when refused, stays on the spot")
	var roomy: Bot = _on_spot(plate_spot)
	var accepting: FakeGadgets = _fake_gadgets()
	roomy.gadgets = accepting
	pickups.resolve(8, _bots([roomy]), _cfg)
	_check(accepting.offered == [ItemIds.SPRING_PLATE] and plate_spot.ready_tick == 8 + respawn and roomy.arsenal.picked_weapon == ItemIds.NONE, "a Spring Plate that is accepted empties the spot for the respawn time and gives no weapon")
	# A bot with full gadget slots does not block the spot for the others.
	plate_spot.ready_tick = 0
	var stuck: Bot = _on_spot(plate_spot)
	stuck.peer_id = 2
	var stuck_gadgets: FakeGadgets = _fake_gadgets()
	stuck_gadgets.accept = false
	stuck.gadgets = stuck_gadgets
	var free: Bot = _on_spot(plate_spot)
	free.peer_id = 3
	var free_gadgets: FakeGadgets = _fake_gadgets()
	free.gadgets = free_gadgets
	pickups.resolve(9, _bots([free, stuck]), _cfg)
	_check(stuck_gadgets.offered == [ItemIds.SPRING_PLATE] and free_gadgets.offered == [ItemIds.SPRING_PLATE] and plate_spot.ready_tick == 9 + respawn, "peer 2 with full gadget slots is offered the Spring Plate first and refuses, then peer 3 takes it")
	plate_spot.ready_tick = 0
	var first: FakeGadgets = _fake_gadgets()
	stuck.gadgets = first
	free_gadgets.offered.clear()
	pickups.resolve(10, _bots([free, stuck]), _cfg)
	_check(first.offered == [ItemIds.SPRING_PLATE] and free_gadgets.offered.is_empty(), "when the lowest peer id can take it, the others are not offered it")
	_clear()

	_test_pickup_cycle_and_rerun()
	_test_pickup_session_reset()

func _test_pickup_cycle_and_rerun() -> void:
	var pickups: Pickups = Pickups.new()
	pickups.layout = LAYOUT
	add_child(pickups)
	_nodes.append(pickups)
	var cycle: int = _ticks(_cfg.hazard_cycle_time)
	var start: int = 100
	MatchSettings.round_start_tick = start
	for spot: PickupSpot in pickups.spots():
		spot.ready_tick = 999999
	pickups.resolve(start, [], _cfg)
	var untouched: bool = true
	for spot: PickupSpot in pickups.spots():
		untouched = untouched and spot.ready_tick == 999999
	_check(untouched, "the first start of the cycle does not reset the spots")
	pickups.resolve(start + cycle - 1, [], _cfg)
	for spot: PickupSpot in pickups.spots():
		untouched = untouched and spot.ready_tick == 999999
	_check(untouched, "a tick inside the cycle does not reset the spots")
	pickups.resolve(start + cycle, [], _cfg)
	var all_ready: bool = true
	for spot: PickupSpot in pickups.spots():
		all_ready = all_ready and spot.ready_tick == start + cycle
	_check(all_ready, "when the cycle restarts every spot is ready again")
	for spot: PickupSpot in pickups.spots():
		spot.ready_tick = 5
	pickups.resolve(start + 2 * cycle, [], _cfg)
	var kept: bool = true
	for spot: PickupSpot in pickups.spots():
		kept = kept and spot.ready_tick == 5
	_check(kept, "a spot that was already ready is not pushed later by the reset")
	# A stall skips the boundary tick: the first tick run in the next cycle resets a spot taken in
	# the cycle before (the respawn time reaches past the boundary), not one taken in this cycle.
	var respawn: int = _ticks(_cfg.pickup_respawn_time)
	var late: PickupSpot = pickups.spots()[0]
	var early: PickupSpot = pickups.spots()[1]
	var next_start: int = start + 3 * cycle
	late.ready_tick = next_start - 10 + respawn
	early.ready_tick = next_start + 2 + respawn
	pickups.resolve(next_start + 5, [], _cfg)
	_check(late.ready_tick == next_start, "a spot taken late in a cycle is ready from the start of the next, even when its boundary tick was skipped")
	_check(early.ready_tick == next_start + 2 + respawn, "a spot taken early in the new cycle keeps its cooldown")
	late.ready_tick = next_start - 10 + respawn
	pickups.resolve(next_start + 5, [], _cfg)
	_check(late.ready_tick == next_start, "running the same tick again from the restored state gives the same reset")
	MatchSettings.round_start_tick = -1

	# A tick run twice from the same restored state ends the same.
	var spot: PickupSpot = pickups.spots()[1]
	spot.ready_tick = 0
	var bot: Bot = _bot(spot.global_position)
	var before_spot: int = spot.ready_tick
	var before_bot: Dictionary = _snapshot(bot)
	pickups.resolve(300, _bots([bot]), _cfg)
	var after_spot: int = spot.ready_tick
	var after_bot: Dictionary = _snapshot(bot)
	spot.ready_tick = before_spot
	_restore(bot, before_bot)
	pickups.resolve(300, _bots([bot]), _cfg)
	_check(after_spot != before_spot and spot.ready_tick == after_spot and _snapshot(bot) == after_bot, "running a pickup tick again from its restored state gives the same result")
	_clear()

# Calls the handlers the signal has on this node and no others: emitting the signal itself would
# also start netfox's own session handling in this test process.
func _deliver(event: Signal, target: Node, args: Array) -> void:
	for connection: Dictionary in event.get_connections():
		var handler: Callable = connection["callable"] as Callable
		if handler.get_object() == target:
			handler.callv(args)

# A spot on cooldown when a session starts or stops is ready in the next session, on both roles:
# the new session's tick count starts again, so the old cooldown would hold the spot for good.
func _test_pickup_session_reset() -> void:
	var events: Array[Signal] = [NetworkEvents.on_server_start, NetworkEvents.on_server_stop, NetworkEvents.on_client_stop]
	var names: Array[String] = ["host start", "host stop", "client stop"]
	for i: int in events.size() + 1:
		var pickups: Pickups = Pickups.new()
		pickups.layout = LAYOUT
		add_child(pickups)
		_nodes.append(pickups)
		var spot: PickupSpot = _spot_node(pickups, 0)
		var label: String = names[i] if i < events.size() else "client start"
		var taker: Bot = _on_spot(spot)
		pickups.resolve(100, _bots([taker]), _cfg)
		spot.ready_tick = 5450
		if i < events.size():
			_deliver(events[i], pickups, [])
		else:
			_deliver(NetworkEvents.on_client_start, pickups, [7])
		var next_taker: Bot = _on_spot(spot)
		pickups.resolve(5, _bots([next_taker]), _cfg)
		_check(spot.ready_tick != 5450 and next_taker.arsenal.picked_weapon == spot.item, "a spot on cooldown before a session event (%s) is ready after it" % label)
		_clear()
