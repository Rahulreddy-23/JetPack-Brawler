class_name HitFlash
extends Node
## Briefly flashes a CanvasItem toward a colour (white by default), then puts it back.
## Add as a child of the CanvasItem, or assign target. Presentation only.
##
## It owns one ShaderMaterial, puts it on the target for the duration of the flash and
## restores the target's previous material afterwards. It never touches modulate, so a tint set
## by another system during the flash survives. Child CanvasItems of the target draw with their
## own material unless they set use_parent_material, so they need it to flash with the target.
##
## While flashing, the target's own material is replaced, including a CanvasItemMaterial blend
## mode. A target that itself has use_parent_material on ignores its own material, so it shows
## no flash at all.
##
## Contract: one HitFlash per target; two on the same target is unsupported and can leave it
## flashed.

const FLASH_SHADER: Shader = preload("res://effects/hit_flash.gdshader")

var target: CanvasItem

var _material: ShaderMaterial = ShaderMaterial.new()
var _previous: Material
var _time_left: float = 0.0
var _flashing: bool = false


func _ready() -> void:
	_material.shader = FLASH_SHADER
	if target == null:
		target = get_parent() as CanvasItem
	set_process(false)


## amount 1 turns the target fully into color, 0 leaves it unchanged. Safe to call again
## mid-flash: the timer restarts. If other code replaced the target's material meanwhile, that
## material becomes the one to restore. Ignored while the node is not in the tree, and for a
## duration that is not finite or not above zero, or an amount that is not finite.
func flash(duration: float, color: Color = Color.WHITE, amount: float = 1.0) -> void:
	if not is_inside_tree() or target == null or not is_instance_valid(target):
		return
	if not is_finite(duration) or duration <= 0.0 or not is_finite(amount):
		return
	if not _flashing or target.material != _material:
		_previous = target.material
		target.material = _material
		_flashing = true
	_material.set_shader_parameter("flash_color", color)
	_material.set_shader_parameter("amount", amount)
	_time_left = duration
	set_process(true)


func is_flashing() -> bool:
	return _flashing


func _process(delta: float) -> void:
	_time_left -= delta
	if _time_left <= 0.0:
		_restore()


func _restore() -> void:
	# Leave the material alone if something else replaced ours during the flash.
	if _flashing and is_instance_valid(target) and target.material == _material:
		target.material = _previous
	_previous = null
	_flashing = false
	set_process(false)


func _exit_tree() -> void:
	_restore()
