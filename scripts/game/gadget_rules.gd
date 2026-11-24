class_name GadgetRules
extends RefCounted
## Host-side gadget and world-object rules, called by the CombatResolver once per tick
## (step 2): launches from gadget use, and everything every object does after launch: motion,
## wall and bot contact, arming, fuses, blasts and plate launches, for rockets as well as bombs
## and plates (a rocket's blast numbers come from cfg.weapons[ItemIds.ROCKET_TUBE]). Pure
## functions of state; they write only the state of world objects and append Hits. The slot
## range arithmetic is WorldObjects.slot_range; the dummy has none and never throws.
##
## Owner: task D (world objects and gadgets).
## Motion itself (gravity, bounce, landing, the fuse) is WorldObject._rollback_tick; this file
## holds what an object does to bots and to other objects.

const CombatMath: GDScript = preload("res://combat/combat_math.gd")

## Collect this tick's hits from bombs, blasts and plates, in this order: phase 1 cycle reset
## of prior-cycle objects, gadget use, rocket contact, blasts, plate launches. bots are sorted
## by peer id. The slots take the arena's solid rectangles from WorldObjects.solids, so the
## solids passed in are not needed here.
static func collect(tick: int, bots: Array[Bot], objects: WorldObjects, _solids: Array[Rect2], cfg: TuningConfig, hits: Array[Hit]) -> void:
	# Phase 1 test cycle: once a later cycle begins, clear any object from an earlier cycle
	# before blasts, plates or new throws run, even if a stall skipped the exact boundary tick.
	var into_cycle: int = MatchSettings.hazard_ticks(tick)
	if into_cycle >= 0:
		var cycle_start: int = tick - into_cycle
		if cycle_start > MatchSettings.round_start_tick:
			for slot: WorldObject in objects.slots():
				if slot.active and slot.spawn_tick < cycle_start:
					slot.active = false
	_use_gadgets(tick, bots, objects, cfg)
	_rocket_contacts(tick, bots, objects, cfg)
	_blasts(tick, bots, objects, cfg, hits)
	_plates(tick, bots, objects, cfg, hits)

# A bomb is thrown, a plate dropped or tossed, along the direction the gadget was used in.
static func _use_gadgets(tick: int, bots: Array[Bot], objects: WorldObjects, cfg: TuningConfig) -> void:
	var px: float = cfg.bot_height_px
	for bot: Bot in bots:
		if not bot.gadgets.used_at(tick):
			continue
		var direction: Vector2 = bot.gadgets.gadget_dir
		match bot.gadgets.used_id():
			ItemIds.COOKER_BOMB:
				objects.launch(ItemIds.OBJECT_BOMB, bot.slot, bot.peer_id, bot.center(), direction * cfg.bomb_throw_speed * px, tick, cfg)
			ItemIds.SPRING_PLATE:
				objects.launch(ItemIds.OBJECT_PLATE, bot.slot, bot.peer_id, bot.center(), direction * cfg.plate_throw_speed * px, tick, cfg)

# A rocket that touches a bot sets itself off, at the contact point. Its owner is safe until the
# rocket is armed. Contact sweeps the path the rocket actually traveled this tick (up to any
# wall or range stop on this tick) against each bot's end-of-tick rectangle grown by the
# rocket's radius. Deflection affects the next move.
# What this misses: a bot's own movement during the tick is not subtracted, so a bot that crossed
# the path and ended beyond it is missed unless the end-of-tick rectangle still meets the path;
# the grown rectangle has square corners, so a near miss past a corner counts as a hit.
static func _rocket_contacts(tick: int, bots: Array[Bot], objects: WorldObjects, cfg: TuningConfig) -> void:
	for slot: WorldObject in objects.slots():
		if not slot.active or slot.kind != ItemIds.OBJECT_ROCKET or (slot.explode_tick >= 0 and slot.explode_tick != tick):
			continue
		var radius: float = WorldObjects.round_radius(slot, cfg)
		var end: Vector2 = slot.global_position
		var start: Vector2 = slot.rocket_step_start
		var first: float = -1.0
		for bot: Bot in bots:
			if bot.vitals.knocked_out or (bot.peer_id == slot.owner_peer and tick < slot.arm_tick):
				continue
			var t: float = CombatGeometry.segment_rect(start, end, bot.body_rect().grow(radius))
			if t >= 0.0 and (first < 0.0 or t < first):
				first = t
		if first >= 0.0:
			slot.explode_tick = tick
			slot.global_position = start + (end - start) * first

# Every object that explodes this tick hits the live bots inside its radius, pushes the other
# bombs and rockets away, and is removed from the next tick.
static func _blasts(tick: int, bots: Array[Bot], objects: WorldObjects, cfg: TuningConfig, hits: Array[Hit]) -> void:
	var px: float = cfg.bot_height_px
	for slot: WorldObject in objects.slots():
		if not slot.active or slot.kind == ItemIds.OBJECT_PLATE or slot.explode_tick != tick:
			continue
		var radius: float = cfg.bomb_blast_radius
		var centre_push: float = cfg.bomb_blast_push
		var centre_damage: float = cfg.bomb_blast_damage
		if slot.kind == ItemIds.OBJECT_ROCKET:
			var stats: WeaponStats = cfg.weapon_stats(ItemIds.ROCKET_TUBE)
			radius = stats.blast_radius
			centre_push = stats.blast_push
			centre_damage = stats.blast_damage
		var centre: Vector2 = slot.global_position / px
		for bot: Bot in bots:
			if bot.vitals.knocked_out:
				continue
			var target: Vector2 = bot.center() / px
			var distance: float = target.distance_to(centre)
			if distance >= radius:
				continue
			var hit: Hit = Hit.new()
			hit.victim = bot
			hit.attacker_peer = slot.owner_peer
			hit.damage = centre_damage * (1.0 - distance / radius)
			hit.push = CombatMath.blast_push(target, centre, centre_push, radius)
			hit.bullet = false
			hits.append(hit)
		for other: WorldObject in objects.slots():
			if other == slot or not other.active or other.kind == ItemIds.OBJECT_PLATE or other.explode_tick >= 0:
				continue
			var push: Vector2 = CombatMath.blast_push(other.global_position / px, centre, centre_push, radius)
			if push != Vector2.ZERO:
				other.velocity += push * cfg.push_speed_scale * px
				other.landed = false
		slot.blasts += 1
		slot.active = false

# A landed, armed plate launches straight up every live bot whose feet are on it and that is
# not already moving upward, its owner included. The plate stays.
static func _plates(tick: int, bots: Array[Bot], objects: WorldObjects, cfg: TuningConfig, hits: Array[Hit]) -> void:
	var feet_height: float = cfg.plate_size.y * cfg.bot_height_px
	for slot: WorldObject in objects.slots():
		if not slot.active or slot.kind != ItemIds.OBJECT_PLATE or not slot.landed or tick < slot.arm_tick:
			continue
		var plate: Rect2 = WorldObjects.plate_rect(slot, cfg)
		for bot: Bot in bots:
			if bot.vitals.knocked_out or bot.velocity.y < 0.0:
				continue
			var body: Rect2 = bot.body_rect()
			var feet: Rect2 = Rect2(body.position.x, body.end.y - feet_height, body.size.x, feet_height)
			if not plate.intersects(feet, true):
				continue
			var hit: Hit = Hit.new()
			hit.victim = bot
			hit.attacker_peer = slot.owner_peer
			hit.damage = 0.0
			hit.push = Vector2(0.0, -cfg.plate_launch_speed)
			hit.bullet = false
			hit.scale_push = false
			# A launch replaces the victim's vertical velocity (see Hit).
			hit.launch = true
			hits.append(hit)
