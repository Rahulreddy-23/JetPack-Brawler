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
## ENet packet throttle (first guesses). ENet lowers a connection's throttle, and with it the
## share of unreliable packets it sends at all, whenever a round trip is slower than the
## recent best, which Wi-Fi jitter does constantly. Input and state travel as unreliable
## packets, so a lowered throttle loses them. Interval is how often (ms) ENet re-measures the
## best round trip, acceleration is how fast the throttle climbs back, and deceleration is how
## fast it falls: 0 keeps it at the maximum so the throttle never drops a packet.
@export var throttle_interval_ms: int = 0
@export var throttle_acceleration: int = 0
@export var throttle_deceleration: int = 0

@export_group("Health and push")
## GDD: health 100, no regeneration.
@export var max_health: float = 0.0
## Lead's reading of the GDD: the push multiplier is 1 at this health or more and
## rises in a straight line to low_health_push_multiplier at 0 (first guess for the 25).
@export var low_health_threshold: float = 0.0
## GDD: a bot at low health flies about twice as far from the same hit.
@export var low_health_push_multiplier: float = 0.0
## Architecture D10: every push (weapon hit, melee, blast, recoil) becomes a velocity change of
## P * this in bh/s, then the low-health multiplier applies to pushes on the victim (first guess).
## plate_launch_speed is a speed, not a GDD push, and is not scaled.
@export var push_speed_scale: float = 0.0
## Seconds after the last hit or push during which a knockout is credited to the
## attacker (lead's call, first guess).
@export var credit_window: float = 0.0
## GDD: each knockout repairs 20 health for the attacker.
@export var knockout_repair: float = 0.0
## Phase 1 scaffolding: seconds a knocked-out bot waits before it respawns (first guess).
@export var respawn_time: float = 0.0
## Rulings: a blast hurts its owner for this fraction of the damage (first guess one half).
@export_range(0.0, 1.0) var self_damage_scale: float = 0.0

@export_group("Push window")
## Product decision: seconds after a push during which braking and steering are
## reduced so the push reads (first guess).
@export var push_window_time: float = 0.0
## Fraction (0 to 1) of normal braking and steering left while the push window is
## open (first guess).
@export_range(0.0, 1.0) var push_window_control: float = 0.0

@export_group("Weapons")
## Indexed by ItemIds weapon id: rivet gun, bolt thrower, scrap blaster, festival rocket
## tube. The bolt thrower is set so a full health bar empties in about one second of
## hits (GDD starting values). Everything else is a first guess.
@export var weapons: Array[WeaponStats] = []
## Weapon slots per bot: the rivet gun and one picked-up weapon (architecture).
@export var weapon_slot_count: int = 0
## Gadget slots per bot (GDD: two gadgets).
@export var gadget_slot_count: int = 0

@export_group("Melee")
## Damage of a melee hit (first guess).
@export var melee_damage: float = 0.0
## GDD: push from melee 2.5, before push_speed_scale.
@export var melee_push: float = 0.0
## Reach from the bot centre in bh (first guess).
@export var melee_range: float = 0.0
## Total width of the swing in degrees (first guess).
@export var melee_arc_degrees: float = 0.0
## Seconds before the next swing (first guess).
@export var melee_cooldown: float = 0.0
## Speed in bh/s of a bomb or rocket sent back by a swing (first guess).
@export var melee_deflect_speed: float = 0.0

@export_group("Gadgets and world objects")
## Seconds between two gadget uses (first guess).
@export var gadget_cooldown: float = 0.0
## Gravity on thrown objects in bh/s^2 (first guess).
@export var object_gravity: float = 0.0
## GDD: Cooker Bomb has a 3-second timer.
@export var bomb_fuse_time: float = 0.0
## Architecture ruling: blast push is 0 at 3 bot heights.
@export var bomb_blast_radius: float = 0.0
## GDD: push at the centre of a bomb blast is 5, before push_speed_scale.
@export var bomb_blast_push: float = 0.0
## Damage of the bomb blast at the centre (first guess).
@export var bomb_blast_damage: float = 0.0
## Throw speed in bh/s (first guess).
@export var bomb_throw_speed: float = 0.0
## Collision radius of the bomb in bh (first guess).
@export var bomb_radius: float = 0.0
## Fraction of speed kept after a bounce, 0 to 1 (first guess).
@export_range(0.0, 1.0) var bomb_bounce: float = 0.0
## Spring Plate size in bh (first guess).
@export var plate_size: Vector2 = Vector2.ZERO
## Speed a plate gives whoever steps on it, in bh/s (first guess).
@export var plate_launch_speed: float = 0.0
## Throw speed of a plate in bh/s (first guess).
@export var plate_throw_speed: float = 0.0
## Seconds after landing before a plate launches anyone (first guess).
@export var plate_arm_time: float = 0.0
## Object slots in the world pool per player and per kind. The pool holds
## max_players times the sum of these three (first guesses: above fire rate times lifetime).
@export var rocket_slots_per_owner: int = 0
@export var bomb_slots_per_owner: int = 0
## GDD: each player can have two traps placed at once.
@export var plate_slots_per_owner: int = 0

@export_group("Pickups")
## Seconds before a pickup spot offers its item again (first guess).
@export var pickup_respawn_time: float = 0.0
## Radius in bh within which a bot picks up an item (first guess).
@export var pickup_radius: float = 0.0

@export_group("Hazard")
## GDD: the hazard starts rising at 30 seconds.
@export var hazard_start_time: float = 0.0
## GDD: the hazard reaches its top at 45 seconds.
@export var hazard_cap_time: float = 0.0
## Phase 1 scaffolding (architecture ruling 3): the hazard cycle repeats every this
## many seconds, then everything resets. 45 per the ruling, so the top is held for
## one tick only; raise it to hold the top longer.
@export var hazard_cycle_time: float = 0.0

@export_group("Effects")
## Numbers for the presentation kit (effects/). Defaults are the designer demo values;
## all are first guesses.
@export var debris_piece_count: int = 0
@export var debris_lifetime: float = 0.0
@export var debris_fade_time: float = 0.0
@export var debris_impulse_px: float = 0.0
@export var debris_impulse_variation: float = 0.0
@export var debris_spread_degrees: float = 0.0
@export var debris_spin: float = 0.0
@export var debris_size_min_px: float = 0.0
@export var debris_size_max_px: float = 0.0
@export var debris_bounce: float = 0.0
@export var debris_max: int = 0
## Screen shake strength in pixels for an ordinary hit and for a knockout.
@export var shake_strength_hit_px: float = 0.0
@export var shake_strength_knockout_px: float = 0.0
## Shake strength lost per second, pixels.
@export var shake_decay_per_second: float = 0.0
## Decision record: hit freeze holds the hit bot's picture for two or three frames.
@export var hit_freeze_frames: int = 0
## Seconds of the white hit flash.
@export var hit_flash_seconds: float = 0.0

# --- task D ---
## Seconds after a rocket is launched or deflected before its own owner can set it off
## (first guess, long enough to leave the muzzle).
@export var rocket_arm_time: float = 0.0
## A bomb whose speed after a floor bounce is below this, in bh/s, comes to rest (first guess).
@export var bomb_rest_speed: float = 0.0
## An idle object slot is sent to peers once per this many seconds instead of every tick, and
## a slot is still sent every tick for this long after its object ends (first guess).
@export var object_idle_send_interval: float = 0.0

# --- task F ---
@export_group("Touch fire, melee and buttons")
## Aim stick deflection, as a fraction of stick_radius_px, at or past which the fire input is
## set; the ring is drawn at this radius (first guess).
@export_range(0.0, 1.0) var fire_ring_fraction: float = 0.0
## A touch in the aim zone released within this many seconds, and never moved more than
## tap_distance_px, is a melee tap (first guess).
@export var tap_time: float = 0.0
## Most a tap may move from where it began, in pixels. Keep it below fire_ring_fraction
## times stick_radius_px so a tap can never fire (first guess).
@export var tap_distance_px: float = 0.0
## Radius of the melee, gadget and swap buttons in pixels, about 10 mm on a phone (first guess).
@export var touch_button_radius_px: float = 0.0
## Button centres as offsets from the bottom-right corner, like dash_button_offset_px (first guess).
@export var melee_button_offset_px: Vector2 = Vector2.ZERO
@export var gadget_button_offset_px: Vector2 = Vector2.ZERO
@export var swap_button_offset_px: Vector2 = Vector2.ZERO
## Line width of the touch rings and button outlines in pixels (first guess).
@export var touch_ring_width_px: float = 0.0
## Text size of button labels and of the weapon and gadget lines of the HUD, in pixels (first guess).
@export var hud_text_size_px: int = 0

## Most presses of one edge action (melee, gadget, swap) kept waiting for a network tick;
## more are dropped, so taps made while no tick runs do not play back later (first guess).
@export var max_pending_presses: int = 0

## Load the shared config once and reuse it.
static func get_default() -> TuningConfig:
	if _cached == null:
		_cached = load(DEFAULT_PATH) as TuningConfig
	return _cached

## Stats of a weapon by ItemIds weapon id; null for an id that is not a weapon.
func weapon_stats(id: int) -> WeaponStats:
	if id < 0 or id >= weapons.size():
		return null
	return weapons[id]

# --- task E ---
@export_group("Presentation (task E)")
## Heaviest hit that still gets no hit freeze: a hit whose vitals.last_hit_push is at least this
## long (bh/s, after scaling) freezes the bot's picture. Light rapid fire stays below it (first guess).
@export var hit_freeze_min_push: float = 0.0
## Seconds a tracer line takes to fade out (first guess).
@export var tracer_seconds: float = 0.0
## Tracer line thickness in pixels (first guess).
@export var tracer_width_px: float = 0.0
## Seconds a muzzle flash is visible (first guess).
@export var muzzle_flash_seconds: float = 0.0
## Muzzle flash radius in pixels (first guess).
@export var muzzle_flash_radius_px: float = 0.0
## Distance from the bot centre to the muzzle, in bot heights (first guess).
@export var muzzle_offset_bh: float = 0.0
## Seconds a melee arc is visible (first guess).
@export var melee_arc_seconds: float = 0.0
## Melee arc line thickness in pixels (first guess).
@export var melee_arc_width_px: float = 0.0
## Distance in bot heights beyond which a blast no longer shakes the screen; the shake is
## shake_strength_knockout_px at the local bot and falls in a straight line to zero here (first guess).
@export var blast_shake_range_bh: float = 0.0
## Tracers, muzzle flashes and melee arcs that can be on screen at once, each (first guess).
@export var fx_pool_size: int = 0
## Size of the health bar above a bot, in pixels (first guess).
@export var health_bar_size_px: Vector2 = Vector2.ZERO
## Gap between the top of a bot and its health bar, in pixels (first guess).
@export var health_bar_offset_px: float = 0.0
## Seconds the health bar stays on screen after the bot's health changes (first guess).
@export var health_bar_hold_seconds: float = 0.0
@export_group("")
