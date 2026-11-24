class_name ScreenShake
extends Node
## Add as a child of a Camera2D. Adds a decaying random offset on top of Camera2D.offset and
## removes exactly what it added when finished. Presentation only; runs on frame time.
## Contract: other systems must change the camera through position or by adding to offset,
## not by assigning offset every frame, or the shake contribution is lost for that frame.

## Strength lost per second, in pixels. Zero or less ends a shake after one frame.
@export var decay_per_second: float = 0.0
## 0 turns shake off, 1 is full strength. This is the accessibility scale.
@export_range(0.0, 1.0) var reduce_shake: float = 1.0:
	set(value):
		reduce_shake = clampf(value, 0.0, 1.0)

var _strength: float = 0.0
var _applied: Vector2 = Vector2.ZERO
var _camera: Camera2D
# Own generator so the shake never advances the global random sequence gameplay may seed.
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_camera = get_parent() as Camera2D
	if _camera == null:
		push_error("ScreenShake must be a child of a Camera2D")
	set_process(false)


## Strength is the maximum offset in pixels. A stronger call replaces a weaker running shake.
func shake(strength: float) -> void:
	if _camera == null or not is_finite(strength):
		return
	_strength = maxf(_strength, strength)
	set_process(true)


func is_shaking() -> bool:
	return is_processing()


func _process(delta: float) -> void:
	var target: Vector2 = Vector2.ZERO
	if _strength > 0.0:
		var s: float = _strength * reduce_shake
		# Whole pixels keep the add/remove exact when nothing else offsets the camera.
		target = Vector2(_rng.randf_range(-s, s), _rng.randf_range(-s, s)).round()
	_camera.offset += target - _applied
	_applied = target
	_strength = maxf(_strength - decay_per_second * delta, 0.0) if decay_per_second > 0.0 else 0.0
	if _strength <= 0.0 and _applied == Vector2.ZERO:
		set_process(false)


func _exit_tree() -> void:
	if is_instance_valid(_camera):
		_camera.offset -= _applied
	_applied = Vector2.ZERO
