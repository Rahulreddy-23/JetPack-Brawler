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
## Velocity is in pixels per second. The tuning config is in bot heights. The
## config is read through MatchSettings.tuning_at(tick) at the top of the tick.
##
## The combat state lives in the child nodes Vitals, Arsenal and Gadgets, and the
## picture in the child Visual; all of it is listed in bot.tscn's synchronizer.

const LAYER_SOLID: int = 1
const LAYER_THIN: int = 2
## Peer id meaning "nobody" (no attacker, no owner).
const NO_PEER: int = -1
## Peer id of the phase 1 dummy bot (never -1, which is NO_PEER). The dummy's slot index is
## TuningConfig.max_players: it is never handed to a player, is not counted against
## max_players, and has no world-object slots (the dummy never fires or throws).
const DUMMY_PEER: int = 0

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

@onready var input: BotInput = $Input as BotInput
@onready var vitals: BotVitals = $Vitals as BotVitals
@onready var arsenal: BotArsenal = $Arsenal as BotArsenal
@onready var gadgets: BotGadgets = $Gadgets as BotGadgets
@onready var visual: BotVisual = $Visual as BotVisual
@onready var _shape: CollisionShape2D = $CollisionShape2D as CollisionShape2D

func _ready() -> void:
	add_to_group(&"bots")
	var cfg: TuningConfig = _display_config()
	var rect: RectangleShape2D = RectangleShape2D.new()
	rect.size = Vector2(cfg.bot_width_bh, 1.0) * cfg.bot_height_px
	_shape.shape = rect
	fuel = cfg.fuel_capacity
	vitals.reset_for_spawn(cfg)
	arsenal.reset_for_spawn(cfg)
	gadgets.reset_for_spawn(cfg)

# The config for code that is not part of the simulation (spawn set-up, HUD).
func _display_config() -> TuningConfig:
	return MatchSettings.tuning_at(NetworkRollback.display_tick)

## The body's collision rectangle in global pixels.
func body_rect() -> Rect2:
	var size: Vector2 = (_shape.shape as RectangleShape2D).size
	return Rect2(global_position - size / 2.0, size)

## The body's centre in global pixels.
func center() -> Vector2:
	return global_position

## Fuel as 0..1 for the HUD.
func fuel_fraction() -> float:
	return clampf(fuel / _display_config().fuel_capacity, 0.0, 1.0)

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
	var cfg: TuningConfig = MatchSettings.tuning_at(tick)
	last_sim_tick = tick
	# A knocked-out bot does not move or act until the resolver respawns it.
	if vitals.knocked_out:
		return
	var move: Vector2 = clean_vector(input.move)
	var aim: Vector2 = clean_vector(input.aim)
	var jet: bool = clean_bool(input.jet)
	var dash_pressed: bool = clean_bool(input.dash)

	if aim.length() > cfg.stick_deadzone:
		aim_dir = aim.normalized()
	if absf(move.x) > cfg.stick_deadzone:
		facing = 1 if move.x > 0.0 else -1

	# Thin platforms are ignored while the stick is held down, plus a short latch.
	if move.y > cfg.stick_digital_threshold:
		drop_left = cfg.drop_through_time
	else:
		drop_left = maxf(drop_left - delta, 0.0)
	collision_mask = LAYER_SOLID if drop_left > 0.0 else LAYER_SOLID | LAYER_THIN

	# Contact is derived from the position, not stored.
	var on_floor: bool = _probe_floor(cfg)
	var wall: int = _probe_wall(cfg, move.x)
	# The wall-jump window opens only while wall-sliding: in the air, touching the
	# wall, falling, with the stick pushed into the wall.
	var sliding: bool = wall != 0 and not on_floor and velocity.y > 0.0 and absf(move.x) > cfg.stick_deadzone and int(signf(move.x)) == -wall
	if sliding:
		wall_nx = wall
		wall_grace_left = cfg.wall_jump_grace
	else:
		wall_grace_left = maxf(wall_grace_left - delta, 0.0)

	dash_cooldown_left = maxf(dash_cooldown_left - delta, 0.0)
	if dash_pressed:
		dash_buffer = cfg.input_buffer_time
	else:
		dash_buffer = maxf(dash_buffer - delta, 0.0)
	if dash_buffer > 0.0 and is_dash_ready():
		_start_dash(cfg, move)

	var thrusting: bool = _update_fuel(cfg, delta, jet, on_floor)

	if dash_left > 0.0:
		_tick_dash(cfg, delta)
		return

	# While the push window is open, braking and steering are reduced so a push reads.
	var control: float = cfg.push_window_control if tick < vitals.push_until_tick else 1.0
	_tick_free_movement(cfg, delta, move, on_floor, wall, thrusting, control)

func _start_dash(cfg: TuningConfig, move: Vector2) -> void:
	var direction: Vector2 = move if move.length() > cfg.stick_deadzone else Vector2(facing, 0)
	dash_dir = direction.normalized()
	dash_left = cfg.dash_time
	dash_cooldown_left = cfg.dash_cooldown
	dash_buffer = 0.0
	thrust_level = 0.0

# Jetpack press buffer, thrust ramp, fuel burn and ground refill. Returns true
# when the jetpack fires this tick. Fuel only refills on the ground.
func _update_fuel(cfg: TuningConfig, delta: float, jet: bool, on_floor: bool) -> bool:
	if jet and not jet_held_prev:
		jet_buffer = cfg.input_buffer_time
	else:
		jet_buffer = maxf(jet_buffer - delta, 0.0)
	jet_held_prev = jet

	var thrusting: bool = dash_left <= 0.0 and fuel > 0.0 and (jet or jet_buffer > 0.0)
	if thrusting:
		jet_buffer = 0.0
		thrust_level = minf(thrust_level + delta / cfg.thrust_ramp_time, 1.0)
		fuel = maxf(fuel - delta, 0.0)
	else:
		thrust_level = 0.0
		if on_floor:
			fuel = minf(fuel + delta * cfg.fuel_capacity / cfg.fuel_refill_time, cfg.fuel_capacity)
	return thrusting

# A dash is a fixed distance in a fixed time. The last tick only uses the time
# that is left, so the distance is exact. Momentum resumes at the exit speed.
func _tick_dash(cfg: TuningConfig, delta: float) -> void:
	var px: float = cfg.bot_height_px
	var step: float = minf(delta, dash_left)
	dash_left -= step
	velocity = dash_dir * (cfg.dash_distance / cfg.dash_time) * px
	_move(cfg, velocity * step)
	if dash_left <= 0.0:
		finish_dash(cfg)

## Apply the exit velocity when a dash completes or is interrupted by a push.
func finish_dash(cfg: TuningConfig) -> void:
	dash_left = 0.0
	velocity = dash_dir * cfg.dash_exit_speed * cfg.bot_height_px

# control scales the horizontal acceleration and braking (1 normally, less in the push window).
func _tick_free_movement(cfg: TuningConfig, delta: float, move: Vector2, on_floor: bool, wall: int, thrusting: bool, control: float) -> void:
	var px: float = cfg.bot_height_px

	# Wall-jump: push away from the wall within the grace window after a slide.
	if not on_floor and wall_grace_left > 0.0 and absf(move.x) > cfg.stick_deadzone and int(signf(move.x)) == wall_nx:
		velocity = Vector2(wall_nx * cfg.wall_jump_speed_x, -cfg.wall_jump_speed_y) * px
		wall_grace_left = 0.0

	# Horizontal: accelerate toward the stick speed, brake gently in the air so momentum carries.
	# Speed grows from zero at the dead zone to full run speed at full deflection.
	var target_x: float = 0.0
	if absf(move.x) > cfg.stick_deadzone:
		var deflection: float = (absf(move.x) - cfg.stick_deadzone) / (1.0 - cfg.stick_deadzone)
		target_x = signf(move.x) * clampf(deflection, 0.0, 1.0) * cfg.run_speed * px
	var accel: float
	if target_x != 0.0:
		accel = cfg.ground_accel if on_floor else cfg.air_accel
	else:
		accel = cfg.ground_brake if on_floor else cfg.air_brake
	velocity.x = move_toward(velocity.x, target_x, accel * control * px * delta)

	# Vertical: gravity, thrust up to the climb speed, then the fall limit.
	velocity.y += cfg.gravity * px * delta
	if thrusting:
		var climb_cap: float = -cfg.climb_speed * px
		if velocity.y > climb_cap:
			# Ramp the lift from gravity up to full thrust, so even one tick of
			# thrust gives a small hop instead of nothing.
			var thrust: float = lerpf(cfg.gravity, cfg.thrust_accel, thrust_level)
			velocity.y = maxf(velocity.y - thrust * px * delta, climb_cap)
	velocity.y = minf(velocity.y, cfg.fall_speed_limit * px)

	# Wall-slide: touching a wall in the air while pushing into it slows the fall.
	if wall != 0 and not on_floor and absf(move.x) > cfg.stick_deadzone and int(signf(move.x)) == -wall:
		velocity.y = minf(velocity.y, cfg.wall_slide_speed * px)

	_move(cfg, velocity * delta)

# Move and slide along what is hit, removing the velocity into each surface.
func _move(cfg: TuningConfig, motion: Vector2) -> void:
	var remaining: Vector2 = motion
	for i: int in cfg.max_slides:
		var hit: KinematicCollision2D = move_and_collide(remaining)
		if hit == null:
			return
		var normal: Vector2 = hit.get_normal()
		velocity = velocity.slide(normal)
		remaining = hit.get_remainder().slide(normal)
		if remaining.is_zero_approx():
			return

func _probe_floor(cfg: TuningConfig) -> bool:
	var hit: KinematicCollision2D = move_and_collide(Vector2(0.0, cfg.probe_distance_px), true)
	return hit != null and hit.get_normal().y < 0.0

# Returns the x sign of the wall normal when a wall is touching, else 0.
# The side the stick pushes toward is checked first.
func _probe_wall(cfg: TuningConfig, push: float) -> int:
	var first: int = -1 if push < 0.0 else 1
	for side: int in [first, -first]:
		var hit: KinematicCollision2D = move_and_collide(Vector2(side * cfg.probe_distance_px, 0.0), true)
		if hit != null:
			var normal: Vector2 = hit.get_normal()
			if absf(normal.x) > absf(normal.y):
				return int(signf(normal.x))
	return 0
