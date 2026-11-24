class_name TuningConfig
extends Resource
## Schema for the single tuning resource. The numbers themselves live in
## config/tuning.tres (defaults here are zero on purpose, so a missing key is
## obvious in the tests). Gameplay scripts read this resource and never hold
## tuning literals. Distances and speeds are in bot
## heights (bh) unless the name ends in _px. Times are in seconds.
## Values marked "first guess" are not in the GDD and need designer review.

const DEFAULT_PATH: String = "res://config/tuning.tres"

static var _cached: TuningConfig = null

@export_group("Scale")
## Pixels in one bot height. All bh values are multiplied by this.
@export var bot_height_px: float = 0.0
## Bot collision width in bot heights (first guess).
@export var bot_width_bh: float = 0.0

@export_group("Run and air control")
## GDD: run speed 6 per second.
@export var run_speed: float = 0.0
## Ground acceleration toward the stick speed, bh/s^2 (first guess).
@export var ground_accel: float = 0.0
## Ground braking with the stick released, bh/s^2 (first guess).
@export var ground_brake: float = 0.0
## Air steering acceleration, bh/s^2 (first guess).
@export var air_accel: float = 0.0
## Air braking with the stick released, bh/s^2; low so momentum carries (first guess).
@export var air_brake: float = 0.0

@export_group("Gravity and jetpack")
## Gravity, bh/s^2 (first guess).
@export var gravity: float = 0.0
## GDD: jetpack climb speed 7 per second at full thrust.
@export var climb_speed: float = 0.0
## GDD: fall speed limit 12 per second.
@export var fall_speed_limit: float = 0.0
## Upward acceleration at full thrust, bh/s^2 (first guess).
@export var thrust_accel: float = 0.0
## GDD: thrust builds over about 0.15 s.
@export var thrust_ramp_time: float = 0.0
## GDD: 2.5 seconds of thrust.
@export var fuel_capacity: float = 0.0
## GDD: full refill in 2 seconds on the ground.
@export var fuel_refill_time: float = 0.0

@export_group("Dash")
## GDD: 3 bot heights.
@export var dash_distance: float = 0.0
## GDD: in 0.15 s.
@export var dash_time: float = 0.0
## GDD: 3 second cooldown (one charge).
@export var dash_cooldown: float = 0.0
## Speed carried out of a dash, bh/s; above run speed so a dash flings the bot
## further into a jetpack burn (first guess).
@export var dash_exit_speed: float = 0.0

@export_group("Walls and thin platforms")
## Fall speed while wall-sliding, bh/s (first guess).
@export var wall_slide_speed: float = 0.0
## Horizontal speed away from the wall on a wall-jump, bh/s (first guess).
@export var wall_jump_speed_x: float = 0.0
## Upward speed on a wall-jump, bh/s (first guess).
@export var wall_jump_speed_y: float = 0.0
## Time the bot ignores thin platforms after the stick goes down (first guess).
@export var drop_through_time: float = 0.0

@export_group("Forgiveness")
## GDD: a jetpack or dash input up to 0.1 s early still counts.
@export var input_buffer_time: float = 0.0
## Lead's reading of the GDD: wall-jump allowed 0.1 s after leaving the wall.
@export var wall_jump_grace: float = 0.0

@export_group("Input")
## Stick magnitude below which horizontal run and dash direction are ignored (first guess).
@export var stick_deadzone: float = 0.0
## Stick magnitude on one axis that counts as up or down (first guess).
@export var stick_digital_threshold: float = 0.0
## Touch stick outer radius (first guess).
@export var stick_radius_px: float = 0.0
## Touch dash button radius (first guess).
@export var dash_button_radius_px: float = 0.0
## Dash button centre offset from the bottom-right corner (first guess).
@export var dash_button_offset_px: Vector2 = Vector2.ZERO
## Fraction of the screen width on the left that starts the move stick (first guess).
@export var move_zone_fraction: float = 0.0
## Opacity of touch controls and HUD overlays (first guess).
@export var overlay_alpha: float = 0.0

@export_group("Collision probes")
## Distance probed for ground and walls each tick, in pixels.
@export var probe_distance_px: float = 0.0
## Collision resolution passes per tick.
@export var max_slides: int = 0

@export_group("HUD and camera")
## Fuel gauge size in pixels (first guess).
@export var hud_gauge_size_px: Vector2 = Vector2.ZERO
## HUD margin from the screen corner in pixels (first guess).
@export var hud_margin_px: float = 0.0
## Length of the aim line in bot heights (first guess).
@export var aim_line_length: float = 0.0
## Aim line thickness in pixels (first guess).
@export var aim_line_width_px: float = 0.0
## How far the camera may look past the arena floor and side walls (not above
## the ceiling), in pixels,
## so a bot standing there is drawn clear of the touch sticks (first guess).
@export var camera_margin_px: float = 0.0

@export_group("Network")
## GDD: 30 ticks per second. Must equal the netfox project setting time/tickrate.
@export var tick_rate: int = 0
## Prototype stage: 4 players per match (including the host).
@export var max_players: int = 0
## Extra ENet connection slots beyond max_players - 1, so a player who arrives
## at a full match can be told "match full" instead of timing out.
@export var spare_connection_slots: int = 0
## Seconds the server waits after telling a turned-away player "match full"
## before it drops the connection (first guess).
@export var reject_notice_seconds: float = 0.0
## ENet port for host and join.
@export var port: int = 0

## Load the shared config once and reuse it.
static func get_default() -> TuningConfig:
	if _cached == null:
		_cached = load(DEFAULT_PATH) as TuningConfig
	return _cached
