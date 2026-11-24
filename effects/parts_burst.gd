class_name PartsBurst
extends Node2D
## Throws grey-box parts (panels, nuts, springs) with the engine's rigid-body physics.
## Show physics only: runs locally on each phone, never synced, never affects the fight.
## Every tuning property is set by the caller; all default to zero, which spawns nothing.
## Place this node under the world root, never under a bot: the pieces are its children and
## are freed with it, so a node that dies with its bot would delete the parts mid-flight.

@export var piece_count: int = 0
## Seconds before a piece is freed.
@export var lifetime: float = 0.0
## Seconds at the end of the lifetime spent fading out.
@export var fade_time: float = 0.0
## Launch speed in pixels per second.
@export var impulse: float = 0.0
## Fraction of the impulse that is randomised per piece, 0 to 1.
@export_range(0.0, 1.0) var impulse_variation: float = 0.0
## Total cone width around the burst direction.
@export var spread_degrees: float = 0.0
## Maximum spin in radians per second, either direction.
@export var spin: float = 0.0
@export var piece_size_min: float = 0.0
@export var piece_size_max: float = 0.0
@export_range(0.0, 1.0) var bounce: float = 0.0
## Hard cap on live pieces across all bursts; the oldest are freed first.
@export var max_debris: int = 0

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


## position_global is where the burst starts, direction is the push direction (zero means up).
func burst(position_global: Vector2, color: Color, direction: Vector2) -> void:
	if not is_inside_tree():
		return
	var dir: Vector2 = direction.normalized() if direction != Vector2.ZERO else Vector2.UP
	var material: PhysicsMaterial = PhysicsMaterial.new()
	material.bounce = bounce
	var half_spread: float = deg_to_rad(spread_degrees) * 0.5
	for i: int in piece_count:
		var piece: DebrisPiece = DebrisPiece.new()
		var kind: DebrisPiece.Kind = _rng.randi_range(0, DebrisPiece.Kind.size() - 1) as DebrisPiece.Kind
		var a: float = _rng.randf_range(piece_size_min, piece_size_max)
		var b: float = _rng.randf_range(piece_size_min, piece_size_max)
		var size: Vector2 = Vector2(a, b)
		if kind == DebrisPiece.Kind.NUT:
			size = Vector2(a, a)
		elif kind == DebrisPiece.Kind.SPRING:
			size = Vector2(piece_size_max, piece_size_min)
		piece.setup(kind, size, color, lifetime, fade_time, material)
		piece.position = position_global
		add_child(piece)
		var angle: float = dir.angle() + _rng.randf_range(-half_spread, half_spread)
		var speed: float = impulse * (1.0 - impulse_variation * _rng.randf())
		piece.linear_velocity = Vector2.from_angle(angle) * speed
		piece.angular_velocity = _rng.randf_range(-spin, spin)
		DebrisPiece.register(piece, max_debris)
