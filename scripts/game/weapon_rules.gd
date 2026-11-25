class_name WeaponRules
extends RefCounted
## Host-side weapon rules, called by the CombatResolver once per tick (step 1).
## Pure functions of state: they read bots, objects and solids and append Hits and send no
## RPC. Rockets are launched through WorldObjects.launch and task C never writes slot state
## itself: bombs, rockets and plates are found with WorldObjects.targets_along (bullet casts)
## and targets_near (melee arc), bombs and rockets are knocked away with WorldObjects.deflect,
## and plates are shot with WorldObjects.destroy. Everything a rocket does after launch
## (flight, contact, blast, hits) is task D's, in GadgetRules. The dummy never fires.
##
## Owner: task C (weapons, melee, pickups).

## What one shot line meets first. t above 1 means nothing in reach.
class Impact:
	var t: float = 2.0
	var bot: Bot = null
	var object: ObjectCast = null

## A duration in seconds as whole ticks, never below one.
static func seconds_to_ticks(seconds: float, cfg: TuningConfig) -> int:
	return maxi(roundi(seconds * float(cfg.tick_rate)), 1)

## Collect this tick's hits from shots and melee (not rocket contacts: those are task D's).
## bots are sorted by peer id. solids are the arena's solid rectangles in pixels.
static func collect(tick: int, bots: Array[Bot], objects: WorldObjects, solids: Array[Rect2], cfg: TuningConfig, hits: Array[Hit]) -> void:
	for shooter: Bot in bots:
		# Pushes and knockouts of this tick are applied after this pass, so a bot that is
		# about to be knocked out still shoots on its last tick.
		if shooter.vitals.knocked_out:
			continue
		if shooter.arsenal.fired_at(tick):
			_collect_shot(tick, shooter, bots, objects, solids, cfg, hits)
		if shooter.arsenal.meleed_at(tick):
			_collect_melee(tick, shooter, bots, objects, solids, cfg, hits)

# One shot: a rocket is launched, anything else is one line per pellet.
static func _collect_shot(tick: int, shooter: Bot, bots: Array[Bot], objects: WorldObjects, solids: Array[Rect2], cfg: TuningConfig, hits: Array[Hit]) -> void:
	var dir: Vector2 = shooter.arsenal.shot_dir.normalized()
	var id: int = shooter.arsenal.active_weapon()
	var stats: WeaponStats = cfg.weapon_stats(id)
	if stats == null or dir == Vector2.ZERO:
		return
	var px: float = cfg.bot_height_px
	var origin: Vector2 = shooter.center()
	if id == ItemIds.ROCKET_TUBE:
		# The rocket starts just outside the body, where the aim line leaves it.
		var half: Vector2 = shooter.body_rect().size / 2.0
		var leave: float = minf(half.x / absf(dir.x) if dir.x != 0.0 else INF, half.y / absf(dir.y) if dir.y != 0.0 else INF)
		var muzzle: Vector2 = origin + dir * (leave + stats.projectile_radius * px)
		# A wall closer than the muzzle: start at its face, so the blast it causes is centred there.
		var wall: CastResult = CombatGeometry.cast(origin, muzzle, solids)
		if wall.index >= 0 and wall.t < 1.0:
			muzzle = origin.lerp(muzzle, wall.t)
		objects.launch(ItemIds.OBJECT_ROCKET, shooter.slot, shooter.peer_id, muzzle, dir * stats.projectile_speed * px, tick, cfg)
		return
	var count: int = maxi(stats.pellets, 1)
	var spread: float = deg_to_rad(stats.spread_degrees)
	for i: int in count:
		# Pellets sit at fixed angles, evenly across the cone, so a shot never uses randomness.
		var angle: float = 0.0 if count == 1 else -spread / 2.0 + spread * float(i) / float(count - 1)
		var line: Vector2 = dir.rotated(angle)
		var impact: Impact = _cast(shooter, origin, origin + line * stats.range_bh * px, bots, objects, solids, cfg)
		if impact.bot != null:
			# Only the scrap blaster loses strength with distance, down to zero at its range.
			var strength: float = 1.0 - impact.t if id == ItemIds.SCRAP_BLASTER else 1.0
			var hit: Hit = Hit.new()
			hit.victim = impact.bot
			hit.attacker_peer = shooter.peer_id
			hit.damage = stats.damage * strength
			hit.push = line * stats.push * strength
			hit.bullet = true
			# A pellet at the very end of its range does nothing: no hit, so no credit.
			if hit.damage > 0.0 or hit.push != Vector2.ZERO:
				hits.append(hit)
		elif impact.object != null:
			_shoot_object(tick, shooter, impact.object.slot, line, objects, cfg)

# A bullet on a bomb or rocket sends it away along the shot; on a plate it destroys it.
static func _shoot_object(tick: int, shooter: Bot, slot: WorldObject, line: Vector2, objects: WorldObjects, cfg: TuningConfig) -> void:
	match slot.kind:
		ItemIds.OBJECT_PLATE:
			objects.destroy(slot, tick)
		ItemIds.OBJECT_BOMB, ItemIds.OBJECT_ROCKET:
			_knock_away(tick, shooter, slot, line, objects, cfg)

# Speed is the larger of the object's own and the config's deflect speed; the deflector owns it.
static func _knock_away(tick: int, shooter: Bot, slot: WorldObject, dir: Vector2, objects: WorldObjects, cfg: TuningConfig) -> void:
	var speed: float = maxf(slot.velocity.length(), cfg.melee_deflect_speed * cfg.bot_height_px)
	objects.deflect(slot, dir * speed, shooter.peer_id, tick, cfg)

# The nearest thing the segment a to b meets: a wall, another live bot that is not dashing, or
# a world object.
# Ties go to the wall, then to the lowest-ordered bot, then to the object.
static func _cast(shooter: Bot, a: Vector2, b: Vector2, bots: Array[Bot], objects: WorldObjects, solids: Array[Rect2], cfg: TuningConfig) -> Impact:
	var impact: Impact = Impact.new()
	var wall: CastResult = CombatGeometry.cast(a, b, solids)
	if wall.index >= 0:
		impact.t = wall.t
	for bot: Bot in bots:
		# A dashing bot is missed: the bullet flies on to whatever is behind it.
		if bot == shooter or bot.vitals.knocked_out or bot.dash_left > 0.0:
			continue
		var t: float = CombatGeometry.segment_rect(a, b, bot.body_rect())
		if t >= 0.0 and t < impact.t:
			impact.t = t
			impact.bot = bot
	for found: ObjectCast in objects.targets_along(a, b, cfg):
		if found.t >= 0.0 and found.t < impact.t:
			impact.t = found.t
			impact.bot = null
			impact.object = found
	return impact

# A swing: bots in the arc get a hit pushed away from the swinger; bombs and rockets in it
# are sent back along the swing. Walls stop a swing: a target behind one is not reached.
static func _collect_melee(tick: int, shooter: Bot, bots: Array[Bot], objects: WorldObjects, solids: Array[Rect2], cfg: TuningConfig, hits: Array[Hit]) -> void:
	var dir: Vector2 = shooter.arsenal.shot_dir.normalized()
	if dir == Vector2.ZERO:
		return
	var apex: Vector2 = shooter.center()
	var reach: float = cfg.melee_range * cfg.bot_height_px
	# The arc is a pie slice, which stays convex up to a half-turn: wider is treated as that.
	var half: float = minf(deg_to_rad(cfg.melee_arc_degrees) / 2.0, PI / 2.0)
	for bot: Bot in bots:
		if bot == shooter or bot.vitals.knocked_out:
			continue
		var rect: Rect2 = bot.body_rect()
		if not _sector_overlaps_rect(apex, dir, half, reach, rect):
			continue
		# Nothing solid may lie between the swinger's centre and the nearest point of the body.
		var nearest: Vector2 = Vector2(clampf(apex.x, rect.position.x, rect.end.x), clampf(apex.y, rect.position.y, rect.end.y))
		if _blocked(apex, nearest, solids):
			continue
		var away: Vector2 = (bot.center() - apex).normalized()
		var hit: Hit = Hit.new()
		hit.victim = bot
		hit.attacker_peer = shooter.peer_id
		hit.damage = cfg.melee_damage
		hit.push = (away if away != Vector2.ZERO else dir) * cfg.melee_push
		hit.bullet = false
		hits.append(hit)
	for slot: WorldObject in objects.targets_near(apex, reach, cfg):
		if slot.kind != ItemIds.OBJECT_BOMB and slot.kind != ItemIds.OBJECT_ROCKET:
			continue
		var radius: float = cfg.bomb_radius if slot.kind == ItemIds.OBJECT_BOMB else cfg.weapons[ItemIds.ROCKET_TUBE].projectile_radius
		if _sector_overlaps_circle(apex, dir, half, reach, slot.global_position, radius * cfg.bot_height_px) and not _blocked(apex, slot.global_position, solids):
			_knock_away(tick, shooter, slot, dir, objects, cfg)

# True when a wall is crossed before b on the way from a (touching b does not count).
static func _blocked(a: Vector2, b: Vector2, solids: Array[Rect2]) -> bool:
	var wall: CastResult = CombatGeometry.cast(a, b, solids)
	return wall.index >= 0 and wall.t < 1.0

# True when the circle shares a point with the pie slice (same shape as for the rectangle).
static func _sector_overlaps_circle(apex: Vector2, dir: Vector2, half: float, radius: float, center: Vector2, circle_radius: float) -> bool:
	var edge_a: Vector2 = dir.rotated(-half)
	var edge_b: Vector2 = dir.rotated(half)
	var offset: Vector2 = center - apex
	if _in_wedge(offset, edge_a, edge_b) and offset.length() <= radius + circle_radius:
		return true
	for edge: Vector2 in [edge_a, edge_b]:
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(center, apex, apex + edge * radius)
		if closest.distance_to(center) <= circle_radius:
			return true
	return false

# True when v lies between the wedge edges (edge_a to edge_b, turning the positive way).
static func _in_wedge(v: Vector2, edge_a: Vector2, edge_b: Vector2) -> bool:
	return edge_a.cross(v) >= 0.0 and v.cross(edge_b) >= 0.0

# True when the rectangle shares a point with the pie slice of the given radius, half angle
# (up to a quarter turn) and direction at the apex. The rectangle is cut by the two edge
# lines and what is left must come within the radius of the apex.
static func _sector_overlaps_rect(apex: Vector2, dir: Vector2, half: float, radius: float, rect: Rect2) -> bool:
	if rect.has_point(apex):
		return true
	var shape: PackedVector2Array = PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
	shape = _clip(shape, apex, dir.rotated(-half), 1.0)
	shape = _clip(shape, apex, dir.rotated(half), -1.0)
	for i: int in shape.size():
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(apex, shape[i], shape[(i + 1) % shape.size()])
		if closest.distance_squared_to(apex) <= radius * radius:
			return true
	return false

# Keeps the part of the polygon where side * edge.cross(p - apex) is not negative.
static func _clip(shape: PackedVector2Array, apex: Vector2, edge: Vector2, side: float) -> PackedVector2Array:
	var kept: PackedVector2Array = PackedVector2Array()
	for i: int in shape.size():
		var p: Vector2 = shape[i]
		var q: Vector2 = shape[(i + 1) % shape.size()]
		var dp: float = side * edge.cross(p - apex)
		var dq: float = side * edge.cross(q - apex)
		if dp >= 0.0:
			kept.append(p)
		if (dp >= 0.0) != (dq >= 0.0):
			kept.append(p + (q - p) * (dp / (dp - dq)))
	return kept
