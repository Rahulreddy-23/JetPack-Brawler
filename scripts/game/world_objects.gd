class_name WorldObjects
extends Node2D
## The fixed pool of world-object slots ("Objects" in main.tscn): Obj0 to ObjN-1, created
## in _ready identically on every peer from the config, never freed. The pool holds
## max_players times the per-owner slot counts.
##
## Owner: task D (world objects and gadgets), except launch(), which task C calls for rockets.
##
## Who writes slot state (ruling 4):
## - A rocket is launched by task C (WeaponRules calls launch). From then on everything a
##   world object does is task D's: motion, wall and bot contact, arming, the fuse, the blast
##   and the hits it produces, for rockets as well as bombs and plates (D reads the rocket's
##   blast numbers from cfg.weapons[ItemIds.ROCKET_TUBE]). Bombs and plates are launched by D.
## - Task C never writes slot state directly. To find objects it calls targets_along and
##   targets_near; to knock one away it calls deflect; to shoot a plate it calls destroy.
##   Those three and launch are the only entry points, and all write state only.
## - The resolver order stays: WeaponRules, GadgetRules, pickups, CombatRules.
##
## Slot layout, with the dummy in mind (ruling 6): slots are grouped by owner slot, and inside
## one owner by kind in the order rocket, bomb, plate, with the per-owner counts from the
## config. The owner slot is the bot's slot index 0 to max_players - 1. The dummy bot's slot
## index is max_players: it has no range and never launches anything; slot_range() gives it
## a count of 0 and launch() must return null for it.
##
## Every function here writes state only on the host. Velocities passed in and stored are in
## pixels per second, positions in global pixels, like the rest of the slot state.

const SLOT_SCENE: PackedScene = preload("res://scenes/world_object.tscn")
## Passes of pushed_out before it gives up (a numeric search limit, not a tuning value).
const PUSH_OUT_PASSES: int = 4

## The arena's solid rectangles in pixels, which rockets, bombs and plates collide with.
## Filled from the sibling Arena node; a test may set it by hand.
var solids: Array[Rect2] = []:
	set(value):
		solids = value
		_grown_cache.clear()
## The outer edge of the arena's walls in pixels. An object whose centre leaves it is removed.
var bounds_px: Rect2 = Rect2()

var _slots: Array[WorldObject] = []
# half extents -> the solids grown by them; one array per shape size, rebuilt only when solids change.
# It is cleared only when `solids` is reassigned (the setter); changing the array in place, or the
# bot height in the config, leaves stale rectangles.
var _grown_cache: Dictionary = {}

func _ready() -> void:
	# The pool size is fixed for the life of the process, so it reads the config once.
	var cfg: TuningConfig = MatchSettings.tuning_at(0)
	var per_owner: int = cfg.rocket_slots_per_owner + cfg.bomb_slots_per_owner + cfg.plate_slots_per_owner
	for i: int in cfg.max_players * per_owner:
		var slot: WorldObject = SLOT_SCENE.instantiate() as WorldObject
		slot.name = "Obj%d" % i
		add_child(slot)
		_slots.append(slot)
	var arena: Arena = get_node_or_null("../Arena") as Arena
	if arena != null and arena.layout != null:
		var layout: ArenaLayout = arena.layout
		solids = layout.solid_rects_px(cfg.bot_height_px)
		var outer: Rect2 = layout.bounds.grow(layout.wall_thickness)
		bounds_px = Rect2(outer.position * cfg.bot_height_px, outer.size * cfg.bot_height_px)
	# The slots are created once with the main scene, but netfox decides ownership when a
	# synchronizer registers, and re-registers only when this peer joins a game. Without this,
	# a phone that joined a game, left and then hosted would never send its slots' state.
	NetworkEvents.on_server_start.connect(_on_server_start)
	# The main scene stays loaded between sessions, and a new session starts its tick count
	# again, so objects of the old one must not survive into it, on either role.
	NetworkEvents.on_server_start.connect(reset_session)
	NetworkEvents.on_server_stop.connect(reset_session)
	NetworkEvents.on_client_start.connect(_on_client_start)
	NetworkEvents.on_client_stop.connect(reset_session)

func _on_server_start() -> void:
	for slot: WorldObject in _slots:
		(slot.get_node("RollbackSynchronizer") as RollbackSynchronizer).process_settings()

func _on_client_start(_id: int) -> void:
	reset_session()

## Make every slot inactive and forget which slots were being sent (a session started or
## stopped). Not part of the simulation: the host's reset is a state write like reset().
func reset_session() -> void:
	reset()
	for slot: WorldObject in _slots:
		slot.reset_sending()

## All slots in index order.
func slots() -> Array[WorldObject]:
	return _slots

## Whole seconds from the config as a number of ticks.
static func seconds_to_ticks(seconds: float, cfg: TuningConfig) -> int:
	return roundi(seconds * float(cfg.tick_rate))

## The slots of one owner and kind as (first index, count) in slots(). Count is 0 for an owner
## slot outside 0 to max_players - 1 (the dummy's, or a bad value) and for a bad kind.
func slot_range(kind: int, owner_slot: int, cfg: TuningConfig) -> Vector2i:
	if owner_slot < 0 or owner_slot >= cfg.max_players or kind < 0 or kind >= ItemIds.OBJECT_KIND_COUNT:
		return Vector2i(0, 0)
	var counts: Array[int] = [cfg.rocket_slots_per_owner, cfg.bomb_slots_per_owner, cfg.plate_slots_per_owner]
	var per_owner: int = counts[0] + counts[1] + counts[2]
	var first: int = owner_slot * per_owner
	for earlier: int in kind:
		first += counts[earlier]
	return Vector2i(first, counts[kind])

## The solid rectangles grown by half_extents on every side: the space a moving shape of that
## half size cannot have its centre in. A segment cast along the centre then handles the shape.
## One array is kept per half size; do not change the result.
func grown_solids(half_extents: Vector2) -> Array[Rect2]:
	if _grown_cache.has(half_extents):
		return _grown_cache[half_extents] as Array[Rect2]
	var result: Array[Rect2] = []
	for rect: Rect2 in solids:
		result.append(rect.grow_individual(half_extents.x, half_extents.y, half_extents.x, half_extents.y))
	_grown_cache[half_extents] = result
	return result

## pos moved out of the solids along the nearest face of each one it is inside (a shape of
## half_extents centred on pos), repeated until the shape is clear. When no clear position is
## found within a few passes (a gap narrower than the shape), pos itself is returned, so the
## object is placed where it was launched rather than lost.
func pushed_out(pos: Vector2, half_extents: Vector2) -> Vector2:
	var result: Vector2 = pos
	for _pass: int in PUSH_OUT_PASSES:
		var moved: bool = false
		for rect: Rect2 in grown_solids(half_extents):
			var end: Vector2 = rect.end
			if result.x <= rect.position.x or result.x >= end.x or result.y <= rect.position.y or result.y >= end.y:
				continue
			moved = true
			var distances: Array[float] = [result.y - rect.position.y, result.x - rect.position.x, end.x - result.x, end.y - result.y]
			var nearest: int = 0
			for i: int in range(1, 4):
				if distances[i] < distances[nearest]:
					nearest = i
			match nearest:
				0:
					result.y = rect.position.y - WorldObject.SURFACE_GAP_PX
				1:
					result.x = rect.position.x - WorldObject.SURFACE_GAP_PX
				2:
					result.x = end.x + WorldObject.SURFACE_GAP_PX
				_:
					result.y = end.y + WorldObject.SURFACE_GAP_PX
		if not moved:
			return result
	# The last pass may have moved it; it is clear only if a further pass would not move it.
	for rect: Rect2 in grown_solids(half_extents):
		var end: Vector2 = rect.end
		if result.x > rect.position.x and result.x < end.x and result.y > rect.position.y and result.y < end.y:
			return pos
	return result

## The rectangle of an active plate in global pixels.
static func plate_rect(slot: WorldObject, cfg: TuningConfig) -> Rect2:
	var size: Vector2 = cfg.plate_size * cfg.bot_height_px
	return Rect2(slot.global_position - size / 2.0, size)

## Radius in pixels of a bomb or rocket slot.
static func round_radius(slot: WorldObject, cfg: TuningConfig) -> float:
	if slot.kind == ItemIds.OBJECT_BOMB:
		return cfg.bomb_radius * cfg.bot_height_px
	return cfg.weapon_stats(ItemIds.ROCKET_TUBE).projectile_radius * cfg.bot_height_px

## Launch an object (ItemIds.OBJECT_*) into the lowest free slot of the owner's range for this
## kind, or replace the slot with the oldest spawn_tick when the range is full. Returns the
## slot, or null if it could not be launched (including for the dummy's owner slot, a bad kind
## or a position or velocity that is not finite). Called by task C for rockets and by task D
## for bombs and plates. Writes state only. The object is first moved on the next tick.
func launch(kind: int, owner_slot: int, owner_peer: int, pos_px: Vector2, vel_px: Vector2, tick: int, cfg: TuningConfig) -> WorldObject:
	var span: Vector2i = slot_range(kind, owner_slot, cfg)
	if span.y <= 0 or not pos_px.is_finite() or not vel_px.is_finite():
		return null
	var chosen: WorldObject = null
	for i: int in span.y:
		var candidate: WorldObject = _slots[span.x + i]
		if not candidate.active:
			chosen = candidate
			break
		if chosen == null or candidate.spawn_tick < chosen.spawn_tick:
			chosen = candidate
	chosen.active = true
	chosen.kind = kind
	chosen.owner_peer = owner_peer
	chosen.global_position = pos_px
	chosen.velocity = vel_px
	chosen.spawn_tick = tick
	chosen.arm_tick = tick
	chosen.fuse_tick = 0
	chosen.explode_tick = -1
	chosen.landed = false
	chosen.launches += 1
	if kind == ItemIds.OBJECT_BOMB:
		chosen.fuse_tick = tick + seconds_to_ticks(cfg.bomb_fuse_time, cfg)
	elif kind == ItemIds.OBJECT_ROCKET:
		chosen.rocket_step_start = pos_px
		chosen.arm_tick = tick + seconds_to_ticks(cfg.rocket_arm_time, cfg)
		chosen.fuse_tick = _rocket_range_tick(vel_px, tick, cfg)
	# A launch can start overlapping a solid (a shooter hugging a wall): a rocket explodes at once
	# where it is; a bomb or plate is moved out along the nearest face, so nothing is stuck inside.
	var px: float = cfg.bot_height_px
	if kind == ItemIds.OBJECT_ROCKET:
		var radius: float = round_radius(chosen, cfg)
		for rect: Rect2 in solids:
			if CombatGeometry.circle_rect(pos_px, radius, rect):
				chosen.explode_tick = tick
				break
	elif kind == ItemIds.OBJECT_BOMB:
		chosen.global_position = pushed_out(pos_px, Vector2(cfg.bomb_radius, cfg.bomb_radius) * px)
	else:
		chosen.global_position = pushed_out(pos_px, cfg.plate_size * px / 2.0)
	chosen.refresh_sending(tick, cfg)
	return chosen

## Every active bomb, rocket and plate whose shape the segment from a to b (global pixels)
## enters, nearest first (smallest t, ties to the lowest slot index). Used by task C's bullet
## cast, which orders the result against bots and walls by t. Round objects are circles of the
## config radius, the plate is a rectangle of the config size. Reads state only.
func targets_along(a: Vector2, b: Vector2, cfg: TuningConfig) -> Array[ObjectCast]:
	var result: Array[ObjectCast] = []
	for slot: WorldObject in _slots:
		# An object already set to explode this tick is as good as gone: a bullet goes on past it.
		if not slot.active or slot.explode_tick >= 0:
			continue
		var found: ObjectCast = ObjectCast.new()
		found.slot = slot
		if slot.kind == ItemIds.OBJECT_PLATE:
			var rect: Rect2 = plate_rect(slot, cfg)
			var rects: Array[Rect2] = [rect]
			var hit: CastResult = CombatGeometry.cast(a, b, rects)
			if hit.index < 0:
				continue
			found.t = hit.t
			found.normal = hit.normal
			found.rect = rect
		else:
			var radius: float = round_radius(slot, cfg)
			var t: float = _segment_circle(a, b, slot.global_position, radius)
			if t < 0.0:
				continue
			found.t = t
			found.radius = radius
			found.rect = Rect2(slot.global_position - Vector2(radius, radius), Vector2(radius, radius) * 2.0)
			var entry: Vector2 = a + (b - a) * t - slot.global_position
			found.normal = entry.normalized() if t > 0.0 else Vector2.ZERO
		# Insert after every result that is nearer or equal, so ties keep slot order.
		var at: int = result.size()
		while at > 0 and result[at - 1].t > found.t:
			at -= 1
		result.insert(at, found)
	return result

## Every active bomb and rocket whose circle overlaps the circle (global pixels), in slot index
## order. Plates are not returned: a melee swing only moves bombs and rockets. Objects that are
## already set to explode this tick are skipped. Used by task C's
## melee arc, which then filters by angle. Reads state only.
func targets_near(center_px: Vector2, radius_px: float, cfg: TuningConfig) -> Array[WorldObject]:
	var result: Array[WorldObject] = []
	for slot: WorldObject in _slots:
		if not slot.active or slot.explode_tick >= 0 or slot.kind == ItemIds.OBJECT_PLATE:
			continue
		var reach: float = radius_px + round_radius(slot, cfg)
		if slot.global_position.distance_squared_to(center_px) <= reach * reach:
			result.append(slot)
	return result

## A melee swing or a bullet knocks a bomb or rocket away: set its velocity (pixels per second)
## and make new_owner_peer (the deflector) its owner for credit and arming. The deflector's own
## body does not set a rocket off until its arming time has passed again. Idempotent for the
## same tick. Ignores a slot that is not an active bomb or rocket that has not yet exploded,
## and a velocity that is not finite. Writes state only.
func deflect(slot: WorldObject, new_velocity: Vector2, new_owner_peer: int, tick: int, cfg: TuningConfig) -> void:
	if slot == null or not slot.active or slot.kind == ItemIds.OBJECT_PLATE or slot.explode_tick >= 0 or not new_velocity.is_finite():
		return
	slot.velocity = new_velocity
	slot.owner_peer = new_owner_peer
	slot.landed = false
	slot.arm_tick = tick
	if slot.kind == ItemIds.OBJECT_ROCKET:
		slot.arm_tick = tick + seconds_to_ticks(cfg.rocket_arm_time, cfg)
		slot.fuse_tick = _rocket_range_tick(new_velocity, tick, cfg)

## A bullet destroys a plate: make the slot inactive. Ignores a slot that is not an active
## plate. Writes state only.
func destroy(slot: WorldObject, _tick: int) -> void:
	if slot != null and slot.active and slot.kind == ItemIds.OBJECT_PLATE:
		slot.active = false

## Make every slot inactive (round reset).
func reset() -> void:
	for slot: WorldObject in _slots:
		if slot.active:
			slot.active = false

# The tick at which a rocket launched or deflected at this tick with this velocity has flown the
# rocket tube's range, never later than a rocket at the tube's own speed would. Every rocket has
# a finite lifetime: one that does not move, or is too slow, lives as long as a rocket at the
# tube's own speed (see below for a tube with no speed).
# A deflection starts the range again from where the rocket is.
static func _rocket_range_tick(velocity_px: Vector2, tick: int, cfg: TuningConfig) -> int:
	var stats: WeaponStats = cfg.weapon_stats(ItemIds.ROCKET_TUBE)
	var range_px: float = stats.range_bh * cfg.bot_height_px
	var normal_step: float = stats.projectile_speed * cfg.bot_height_px / float(cfg.tick_rate)
	# The lifetime of a rocket at the tube's own speed. When that speed is 0 (a card could set it) there
	# is no flight time to take it from, so the fallback is a bomb's fuse time (an existing config
	# number of the same size, about 3 s) instead of a division by zero.
	var lifetime: int = seconds_to_ticks(cfg.bomb_fuse_time, cfg)
	if normal_step > 0.0 and is_finite(normal_step):
		lifetime = maxi(ceili(range_px / normal_step), 1)
	var step: float = velocity_px.length() / float(cfg.tick_rate)
	if step > 0.0 and is_finite(step):
		lifetime = mini(lifetime, maxi(ceili(range_px / step), 1))
	return tick + lifetime

# Fraction (0 to 1) along a to b at which the segment first enters the circle, 0.0 when it
# starts inside or on it, or -1.0 for no hit.
static func _segment_circle(a: Vector2, b: Vector2, center: Vector2, radius: float) -> float:
	var travel: Vector2 = b - a
	var offset: Vector2 = a - center
	var c: float = offset.dot(offset) - radius * radius
	if c <= 0.0:
		return 0.0
	var qa: float = travel.dot(travel)
	if qa == 0.0:
		return -1.0
	var qb: float = offset.dot(travel)
	var discriminant: float = qb * qb - qa * c
	if discriminant < 0.0:
		return -1.0
	var t: float = (-qb - sqrt(discriminant)) / qa
	if t < 0.0 or t > 1.0:
		return -1.0
	return t
