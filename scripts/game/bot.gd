class_name Bot
extends CharacterBody2D
## One jetpack bot. All movement is simulated on the network tick inside the
## netfox rollback loop (_rollback_tick), never on frame time. The server owns
## this node; the player owns only the child BotInput node.
##
## Every variable that affects future movement is listed as a state property
## in the RollbackSynchronizer (see bot.tscn): position, velocity, fuel, thrust
## ramp, dash timers and direction, input buffers, wall grace, facing and drop
## timer. Ground and wall contact are not stored; they are re-derived from the
## position at the start of each tick, so a client re-simulation matches.
##
## Velocity is in pixels per second. The tuning config is in bot heights.

const LAYER_SOLID: int = 1
const LAYER_THIN: int = 2
const PALETTE: Array[Color] = [Color.ORANGE, Color.CORNFLOWER_BLUE, Color.LIME_GREEN, Color.ORCHID]

## Remaining jetpack fuel in seconds of thrust.
var fuel: float = 0.0
## Thrust ramp, 0 to 1.
var thrust_level: float = 0.0
## Seconds left in the current dash, 0 when not dashing.
var dash_left: float = 0.0
## Seconds until the dash charge is back.
var dash_cooldown_left: float = 0.0
## Direction of the current dash.
var dash_dir: Vector2 = Vector2.ZERO
## Seconds a jetpack press that could not start yet stays valid.
var jet_buffer: float = 0.0
## Was the jetpack input held on the previous tick (for press detection).
var jet_held_prev: bool = false
## Seconds a dash press that could not start yet stays valid.
var dash_buffer: float = 0.0
## Seconds left in which a wall-jump is still allowed.
var wall_grace_left: float = 0.0
## Sign of the x component of the last wall normal: -1 wall on the right, 1 wall on the left.
var wall_nx: int = 0
## Last horizontal facing, -1 or 1.
var facing: int = 1
## Seconds left in which thin platforms are ignored.
var drop_left: float = 0.0
## Sanitised aim direction copied from the input, shown as the aim line.
var aim_dir: Vector2 = Vector2.RIGHT

## Tick of the latest _rollback_tick call. Not simulation state; the smoke test
## reads it to know whether a tick was really simulated.
var last_sim_tick: int = -1

## Peer that plays this bot. Set once by the spawner, never changes.
var peer_id: int = 0
## Spawn slot, picks the body colour. Set once by the spawner.
var slot: int = 0

var _cfg: TuningConfig = TuningConfig.get_default()

@onready var input: BotInput = $Input as BotInput
@onready var _shape: CollisionShape2D = $CollisionShape2D as CollisionShape2D

func _ready() -> void:
	add_to_group(&"bots")
	var rect: RectangleShape2D = RectangleShape2D.new()
	rect.size = Vector2(_cfg.bot_width_bh, 1.0) * _cfg.bot_height_px
	_shape.shape = rect
	fuel = _cfg.fuel_capacity

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var size: Vector2 = Vector2(_cfg.bot_width_bh, 1.0) * _cfg.bot_height_px
	draw_rect(Rect2(-size / 2.0, size), PALETTE[slot % PALETTE.size()])
	if thrust_level > 0.0:
		draw_rect(Rect2(Vector2(-size.x / 2.0, size.y / 2.0), Vector2(size.x, size.y * thrust_level / 2.0)), Color.YELLOW)
	draw_line(Vector2.ZERO, aim_dir * _cfg.aim_line_length * _cfg.bot_height_px, Color.WHITE, _cfg.aim_line_width_px)

## Fuel as 0..1 for the HUD.
func fuel_fraction() -> float:
	return clampf(fuel / _cfg.fuel_capacity, 0.0, 1.0)

## True when a dash could start now.
func is_dash_ready() -> bool:
	return dash_cooldown_left <= 0.0 and dash_left <= 0.0

## Input values arrive from the network without a schema, so any type can show
## up. A value that is not a Vector2, or has a non-finite part, is neutral;
## otherwise it is clamped to length 1. Runs on the server (and on clients,
## identically) before any input value is used.
static func clean_vector(value: Variant) -> Vector2:
	if typeof(value) != TYPE_VECTOR2:
		return Vector2.ZERO
	var vector: Vector2 = value
	if not (is_finite(vector.x) and is_finite(vector.y)):
		return Vector2.ZERO
	return vector.limit_length(1.0)

## A button value that is not a bool is "not pressed".
static func clean_bool(value: Variant) -> bool:
	return typeof(value) == TYPE_BOOL and value == true

func _rollback_tick(delta: float, tick: int, _is_fresh: bool) -> void:
	last_sim_tick = tick
	var move: Vector2 = clean_vector(input.move)
	var aim: Vector2 = clean_vector(input.aim)
	var jet: bool = clean_bool(input.jet)
	var dash_pressed: bool = clean_bool(input.dash)

	if aim.length() > _cfg.stick_deadzone:
		aim_dir = aim.normalized()
	if absf(move.x) > _cfg.stick_deadzone:
		facing = 1 if move.x > 0.0 else -1

	# Thin platforms are ignored while the stick is held down, plus a short latch.
	if move.y > _cfg.stick_digital_threshold:
		drop_left = _cfg.drop_through_time
	else:
		drop_left = maxf(drop_left - delta, 0.0)
	collision_mask = LAYER_SOLID if drop_left > 0.0 else LAYER_SOLID | LAYER_THIN

	# Contact is derived from the position, not stored.
	var on_floor: bool = _probe_floor()
	var wall: int = _probe_wall(move.x)
	# The wall-jump window opens only while wall-sliding: in the air, touching the
	# wall, falling, with the stick pushed into the wall.
	var sliding: bool = wall != 0 and not on_floor and velocity.y > 0.0 and absf(move.x) > _cfg.stick_deadzone and int(signf(move.x)) == -wall
	if sliding:
		wall_nx = wall
		wall_grace_left = _cfg.wall_jump_grace
	else:
		wall_grace_left = maxf(wall_grace_left - delta, 0.0)

	dash_cooldown_left = maxf(dash_cooldown_left - delta, 0.0)
	if dash_pressed:
		dash_buffer = _cfg.input_buffer_time
	else:
		dash_buffer = maxf(dash_buffer - delta, 0.0)
	if dash_buffer > 0.0 and is_dash_ready():
		_start_dash(move)

	var thrusting: bool = _update_fuel(delta, jet, on_floor)

	if dash_left > 0.0:
		_tick_dash(delta)
		return

	_tick_free_movement(delta, move, on_floor, wall, thrusting)

func _start_dash(move: Vector2) -> void:
	var direction: Vector2 = move if move.length() > _cfg.stick_deadzone else Vector2(facing, 0)
	dash_dir = direction.normalized()
	dash_left = _cfg.dash_time
	dash_cooldown_left = _cfg.dash_cooldown
	dash_buffer = 0.0
	thrust_level = 0.0

# Jetpack press buffer, thrust ramp, fuel burn and ground refill. Returns true
# when the jetpack fires this tick. Fuel only refills on the ground.
func _update_fuel(delta: float, jet: bool, on_floor: bool) -> bool:
	if jet and not jet_held_prev:
		jet_buffer = _cfg.input_buffer_time
	else:
		jet_buffer = maxf(jet_buffer - delta, 0.0)
	jet_held_prev = jet

	var thrusting: bool = dash_left <= 0.0 and fuel > 0.0 and (jet or jet_buffer > 0.0)
	if thrusting:
		jet_buffer = 0.0
		thrust_level = minf(thrust_level + delta / _cfg.thrust_ramp_time, 1.0)
		fuel = maxf(fuel - delta, 0.0)
	else:
		thrust_level = 0.0
		if on_floor:
			fuel = minf(fuel + delta * _cfg.fuel_capacity / _cfg.fuel_refill_time, _cfg.fuel_capacity)
	return thrusting

# A dash is a fixed distance in a fixed time. The last tick only uses the time
# that is left, so the distance is exact. Momentum resumes at the exit speed.
func _tick_dash(delta: float) -> void:
	var px: float = _cfg.bot_height_px
	var step: float = minf(delta, dash_left)
	dash_left -= step
	velocity = dash_dir * (_cfg.dash_distance / _cfg.dash_time) * px
	_move(velocity * step)
	if dash_left <= 0.0:
		dash_left = 0.0
		velocity = dash_dir * _cfg.dash_exit_speed * px

func _tick_free_movement(delta: float, move: Vector2, on_floor: bool, wall: int, thrusting: bool) -> void:
	var px: float = _cfg.bot_height_px

	# Wall-jump: push away from the wall within the grace window after a slide.
	if not on_floor and wall_grace_left > 0.0 and absf(move.x) > _cfg.stick_deadzone and int(signf(move.x)) == wall_nx:
		velocity = Vector2(wall_nx * _cfg.wall_jump_speed_x, -_cfg.wall_jump_speed_y) * px
		wall_grace_left = 0.0

	# Horizontal: accelerate toward the stick speed, brake gently in the air so momentum carries.
	# Speed grows from zero at the dead zone to full run speed at full deflection.
	var target_x: float = 0.0
	if absf(move.x) > _cfg.stick_deadzone:
		var deflection: float = (absf(move.x) - _cfg.stick_deadzone) / (1.0 - _cfg.stick_deadzone)
		target_x = signf(move.x) * clampf(deflection, 0.0, 1.0) * _cfg.run_speed * px
	var accel: float
	if target_x != 0.0:
		accel = _cfg.ground_accel if on_floor else _cfg.air_accel
	else:
		accel = _cfg.ground_brake if on_floor else _cfg.air_brake
	velocity.x = move_toward(velocity.x, target_x, accel * px * delta)

	# Vertical: gravity, thrust up to the climb speed, then the fall limit.
	velocity.y += _cfg.gravity * px * delta
	if thrusting:
		var climb_cap: float = -_cfg.climb_speed * px
		if velocity.y > climb_cap:
			# Ramp the lift beyond gravity so even one tick of thrust gives a small hop.
			var thrust: float = lerpf(_cfg.gravity, _cfg.thrust_accel, thrust_level)
			velocity.y = maxf(velocity.y - thrust * px * delta, climb_cap)
	velocity.y = minf(velocity.y, _cfg.fall_speed_limit * px)

	# Wall-slide: touching a wall in the air while pushing into it slows the fall.
	if wall != 0 and not on_floor and absf(move.x) > _cfg.stick_deadzone and int(signf(move.x)) == -wall:
		velocity.y = minf(velocity.y, _cfg.wall_slide_speed * px)

	_move(velocity * delta)

# Move and slide along what is hit, removing the velocity into each surface.
func _move(motion: Vector2) -> void:
	var remaining: Vector2 = motion
	for i: int in _cfg.max_slides:
		var hit: KinematicCollision2D = move_and_collide(remaining)
		if hit == null:
			return
		var normal: Vector2 = hit.get_normal()
		velocity = velocity.slide(normal)
		remaining = hit.get_remainder().slide(normal)
		if remaining.is_zero_approx():
			return

func _probe_floor() -> bool:
	var hit: KinematicCollision2D = move_and_collide(Vector2(0.0, _cfg.probe_distance_px), true)
	return hit != null and hit.get_normal().y < 0.0

# Returns the x sign of the wall normal when a wall is touching, else 0.
# The side the stick pushes toward is checked first.
func _probe_wall(push: float) -> int:
	var first: int = -1 if push < 0.0 else 1
	for side: int in [first, -first]:
		var hit: KinematicCollision2D = move_and_collide(Vector2(side * _cfg.probe_distance_px, 0.0), true)
		if hit != null:
			var normal: Vector2 = hit.get_normal()
			if absf(normal.x) > absf(normal.y):
				return int(signf(normal.x))
	return 0
