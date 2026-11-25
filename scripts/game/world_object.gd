class_name WorldObject
extends Node2D
## One slot of the world-object pool: a rocket, a Cooker Bomb or a Spring Plate
## (scenes/world_object.tscn). The slot is created once on every peer, owned by the host,
## never freed, reparented or queue-freed; an unused slot is state (active = false), not
## absence. Objects move on the host only; clients display the host's state.
##
## Owner: task D (world objects and gadgets).
## Shapes: a bomb and a rocket are circles (bomb_radius, the rocket's projectile_radius,
## both in bot heights); a plate is the rectangle plate_size centred on global_position.
## A rocket, a bomb and a plate collide with the arena's solid rectangles only (not thin
## platforms). What a slot does to bots (contact, blasts, plate launches) is decided by
## GadgetRules; the slot only moves itself and sets explode_tick.

## Distance in pixels left between a bouncing or landing object and the surface, so the next
## cast does not start exactly on the boundary (a numeric guard, not a tuning value).
const SURFACE_GAP_PX: float = 0.01

## True while the slot holds a live object.
var active: bool = false
## ItemIds.OBJECT_ROCKET, OBJECT_BOMB or OBJECT_PLATE; meaningful while active.
var kind: int = ItemIds.NONE
## Peer id of the owner (credit and arming), or Bot.NO_PEER.
var owner_peer: int = Bot.NO_PEER
## Velocity in pixels per second.
var velocity: Vector2 = Vector2.ZERO
## Tick (absolute) at which the object was launched. The oldest spawn_tick is replaced
## when no slot is free.
var spawn_tick: int = 0
## Tick (absolute) from which the owner can set a rocket off, or from which a landed plate
## launches anyone.
var arm_tick: int = 0
## Tick (absolute) at which a bomb's fuse ends, or at which a rocket has flown its range (a
## rocket always has one, however slow).
var fuse_tick: int = 0
## Tick (absolute) at which the object exploded, or -1.
var explode_tick: int = -1
## True once a bomb has come to rest, or a plate has landed.
var landed: bool = false
## Counts launches into this slot. Never reset; effects compare it with the highest value seen.
var launches: int = 0
## Counts blasts of this slot. Never reset; effects compare it with the highest value seen.
var blasts: int = 0

## Start of the rocket's motion for contact tests on this tick. The host writes it on launch
## and before every replayed move, so it does not need to be synchronized.
var rocket_step_start: Vector2 = Vector2.ZERO

# Presentation only: the highest launches value this peer has drawn.
var _seen_launches: int = 0
# Host only, not state: whether peers are sent this slot this tick. An idle slot is sent only
# once per object_idle_send_interval, not every tick (24 idle slots otherwise cost most of
# the object bandwidth).
var _sending: bool = false
# Host only, not state: the last tick through which the slot is still sent.
var _send_until_tick: int = -1

@onready var _interpolator: TickInterpolator = get_node_or_null("TickInterpolator") as TickInterpolator
@onready var _synchronizer: RollbackSynchronizer = get_node_or_null("RollbackSynchronizer") as RollbackSynchronizer

# A slot built without its scene (a test double) has neither child; it then sends and teleports nothing.
func _ready() -> void:
	if _synchronizer != null:
		_synchronizer.visibility_filter.add_visibility_filter(_is_sent_to)
	# netfox interpolates in its own _process, right after the tick loop, before any other
	# node's _process, so a reused slot must be teleported from this signal (emitted after the
	# rollback of the loop, before the interpolation of the same frame), not from _process.
	NetworkTime.after_tick_loop.connect(_on_after_tick_loop)

func _on_after_tick_loop() -> void:
	if launches != _seen_launches:
		_seen_launches = launches
		if _interpolator != null:
			_interpolator.teleport()

func _update_filter() -> void:
	if _synchronizer != null:
		_synchronizer.visibility_filter.update_visibility()

func _is_sent_to(_peer: int) -> bool:
	return _sending

## Forget that the slot was being sent (a session started or stopped).
func reset_sending() -> void:
	_send_until_tick = -1
	if _sending:
		_sending = false
		_update_filter()

## Host only. Send this slot's state to peers every tick while it is active and for one
## interval after it goes inactive (so every peer sees the end of the object), and otherwise
## once per interval, staggered by slot index (so a late joiner, and a value written into an
## idle slot, still arrive within an interval). Called every tick on the host, and by
## WorldObjects.launch so the first state of a new object is already sent.
func refresh_sending(tick: int, cfg: TuningConfig) -> void:
	var interval: int = maxi(WorldObjects.seconds_to_ticks(cfg.object_idle_send_interval, cfg), 1)
	if active:
		_send_until_tick = maxi(_send_until_tick, tick + interval)
	var should_send: bool = tick <= _send_until_tick or (tick + get_index()) % interval == 0
	if should_send != _sending:
		_sending = should_send
		_update_filter()

# netfox runs this on EVERY peer for this inputless slot, not only on its owner. It moves and
# changes state only where this peer is the authority (the host), and leaves an inactive
# slot completely unchanged everywhere. The position after the move is where the object is at
# the end of this tick, and where a blast at explode_tick == tick is centred.
func _rollback_tick(delta: float, tick: int, _is_fresh: bool) -> void:
	if not is_multiplayer_authority():
		return
	var cfg: TuningConfig = MatchSettings.tuning_at(tick)
	refresh_sending(tick, cfg)
	if not active or explode_tick >= 0:
		return
	var pool: WorldObjects = get_parent() as WorldObjects
	if pool == null:
		return
	match kind:
		ItemIds.OBJECT_ROCKET:
			_step_rocket(delta, tick, cfg, pool)
		ItemIds.OBJECT_BOMB:
			_step_bomb(delta, tick, cfg, pool)
		ItemIds.OBJECT_PLATE:
			_step_plate(delta, tick, cfg, pool)
	if explode_tick < 0 and active and pool.bounds_px.has_area() and not pool.bounds_px.has_point(global_position):
		active = false

# A straight line. Meeting a solid sets the blast off at the contact point; flying the whole
# range sets it off in the air.
func _step_rocket(delta: float, tick: int, cfg: TuningConfig, pool: WorldObjects) -> void:
	var radius: float = WorldObjects.round_radius(self, cfg)
	var from: Vector2 = global_position
	rocket_step_start = from
	var to: Vector2 = from + velocity * delta
	var hit: CastResult = CombatGeometry.cast(from, to, pool.grown_solids(Vector2(radius, radius)))
	if hit.index < 0:
		global_position = to
		# A rocket that has flown its range explodes where it is (fuse_tick is its range limit,
		# which every rocket has).
		if tick >= fuse_tick:
			explode_tick = tick
		return
	global_position = from + (to - from) * hit.t
	explode_tick = tick

# Gravity, bounce off solids, rest when slow, explode when the fuse ends.
func _step_bomb(delta: float, tick: int, cfg: TuningConfig, pool: WorldObjects) -> void:
	var px: float = cfg.bot_height_px
	if not landed:
		velocity.y += cfg.object_gravity * px * delta
		var radius: float = WorldObjects.round_radius(self, cfg)
		var from: Vector2 = global_position
		var to: Vector2 = from + velocity * delta
		var hit: CastResult = CombatGeometry.cast(from, to, pool.grown_solids(Vector2(radius, radius)))
		if hit.index < 0:
			global_position = to
		else:
			# A zero normal means it started inside a surface: bounce back the way it came.
			var normal: Vector2 = hit.normal
			if normal == Vector2.ZERO:
				normal = -velocity.normalized() if velocity != Vector2.ZERO else Vector2.UP
			global_position = from + (to - from) * hit.t + normal * SURFACE_GAP_PX
			velocity = velocity.bounce(normal) * cfg.bomb_bounce
			if normal.y < 0.0 and velocity.length() < cfg.bomb_rest_speed * px:
				velocity = Vector2.ZERO
				landed = true
	if tick >= fuse_tick:
		explode_tick = tick

# Gravity until it lands on a solid.
func _step_plate(delta: float, tick: int, cfg: TuningConfig, pool: WorldObjects) -> void:
	if landed:
		return
	var px: float = cfg.bot_height_px
	velocity.y += cfg.object_gravity * px * delta
	var from: Vector2 = global_position
	var to: Vector2 = from + velocity * delta
	var half: Vector2 = cfg.plate_size * px / 2.0
	var hit: CastResult = CombatGeometry.cast(from, to, pool.grown_solids(half))
	if hit.index >= 0 and hit.normal == Vector2.ZERO:
		# Wedged: the plate is wider than the gap it was thrown into (a zero normal means it starts
		# inside a solid). Let it fall by its height alone, so it lands on the floor of the gap.
		hit = CombatGeometry.cast(from, to, pool.grown_solids(Vector2(0.0, half.y)))
	if hit.index < 0:
		global_position = to
		return
	if hit.normal == Vector2.ZERO:
		# Even its height is inside a solid: there is nowhere for it to land.
		active = false
		return
	global_position = from + (to - from) * hit.t + hit.normal * SURFACE_GAP_PX
	if hit.normal.y < 0.0:
		velocity = Vector2.ZERO
		landed = true
		arm_tick = tick + WorldObjects.seconds_to_ticks(cfg.plate_arm_time, cfg)
	else:
		velocity = velocity.slide(hit.normal)

func _process(_delta: float) -> void:
	visible = active
	if active:
		queue_redraw()

## The owner's body colour, picked from the same palette as the bot's Visual. The slots are
## grouped by owner, so the owner's slot index follows from this slot's index.
func owner_color(cfg: TuningConfig) -> Color:
	var per_owner: int = cfg.rocket_slots_per_owner + cfg.bomb_slots_per_owner + cfg.plate_slots_per_owner
	return BotVisual.PALETTE[floori(float(get_index()) / float(per_owner)) % BotVisual.PALETTE.size()]

func _draw() -> void:
	if not active:
		return
	var cfg: TuningConfig = MatchSettings.tuning_at(NetworkRollback.display_tick)
	var armed: bool = landed and NetworkRollback.display_tick >= arm_tick
	var alpha: float = 1.0
	# Armed traps and ticking bombs blink faintly so everyone can see them.
	if armed or kind == ItemIds.OBJECT_BOMB:
		alpha = 0.7 + 0.3 * absf(sin(float(Time.get_ticks_msec()) / 1000.0 * TAU))
	match kind:
		ItemIds.OBJECT_PLATE:
			var color: Color = owner_color(cfg)
			color.a = alpha
			var size: Vector2 = cfg.plate_size * cfg.bot_height_px
			draw_rect(Rect2(-size / 2.0, size), color)
		ItemIds.OBJECT_BOMB:
			draw_circle(Vector2.ZERO, WorldObjects.round_radius(self, cfg), Color(0.9, 0.45, 0.1, alpha))
		_:
			draw_circle(Vector2.ZERO, WorldObjects.round_radius(self, cfg), Color(0.9, 0.15, 0.15, alpha))
