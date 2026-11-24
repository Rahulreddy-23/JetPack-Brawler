extends Node2D
## Designer demo for the impact feel kit. Keys 1 to 5, the on-screen buttons, or a tap on the
## empty screen trigger the effects. All numbers here are demo values only.

const PIECE_COUNT: int = 14
const LIFETIME: float = 2.5
const FADE_TIME: float = 0.5
const IMPULSE: float = 650.0
const IMPULSE_VARIATION: float = 0.5
const SPREAD_DEGREES: float = 120.0
const SPIN: float = 12.0
const PIECE_SIZE_MIN: float = 8.0
const PIECE_SIZE_MAX: float = 22.0
const BOUNCE: float = 0.5
const MAX_DEBRIS: int = 60
const SHAKE_STRENGTH: float = 18.0
const SHAKE_DECAY: float = 60.0
const FREEZE_FRAMES: int = 3
const FLASH_SECONDS: float = 0.08
const BURST_COLOR: Color = Color(0.75, 0.75, 0.78)
const MOVER_SPEED: float = 900.0
const MOVER_SPIN: float = 3.0
const WALL_THICKNESS: float = 40.0

@onready var _burst: PartsBurst = $PartsBurst
@onready var _shake: ScreenShake = $Camera2D/ScreenShake
@onready var _freeze: HitFreeze = $Mover/Visual/HitFreeze
@onready var _flash: HitFlash = $Target/HitFlash
@onready var _target: Polygon2D = $Target
@onready var _mover: Node2D = $Mover
@onready var _visual: Polygon2D = $Mover/Visual
@onready var _camera: Camera2D = $Camera2D


func _ready() -> void:
	var size: Vector2 = get_viewport_rect().size
	_camera.position = size * 0.5
	_burst.piece_count = PIECE_COUNT
	_burst.lifetime = LIFETIME
	_burst.fade_time = FADE_TIME
	_burst.impulse = IMPULSE
	_burst.impulse_variation = IMPULSE_VARIATION
	_burst.spread_degrees = SPREAD_DEGREES
	_burst.spin = SPIN
	_burst.piece_size_min = PIECE_SIZE_MIN
	_burst.piece_size_max = PIECE_SIZE_MAX
	_burst.bounce = BOUNCE
	_burst.max_debris = MAX_DEBRIS
	_shake.decay_per_second = SHAKE_DECAY
	_make_box(_target, Vector2(80.0, 80.0), Color(0.9, 0.5, 0.2))
	_target.position = Vector2(size.x * 0.5, size.y - 200.0)
	_make_box(_visual, Vector2(40.0, 40.0), Color(0.3, 0.8, 0.9))
	_mover.position = Vector2(0.0, 120.0)
	_add_wall(Vector2(size.x * 0.5, size.y + WALL_THICKNESS * 0.5), Vector2(size.x, WALL_THICKNESS))
	_add_wall(Vector2(-WALL_THICKNESS * 0.5, size.y * 0.5), Vector2(WALL_THICKNESS, size.y * 2.0))
	_add_wall(Vector2(size.x + WALL_THICKNESS * 0.5, size.y * 0.5), Vector2(WALL_THICKNESS, size.y * 2.0))
	_add_buttons()
	_add_label()


func _process(delta: float) -> void:
	# A constantly moving and spinning parent so the hit freeze on its visual child is easy to see.
	_mover.position.x = wrapf(_mover.position.x + MOVER_SPEED * delta, 0.0, get_viewport_rect().size.x)
	_mover.rotation += MOVER_SPIN * delta


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_1: _do_burst(_target.position)
			KEY_2: _shake.shake(SHAKE_STRENGTH)
			KEY_3: _freeze.freeze(FREEZE_FRAMES)
			KEY_4: _flash.flash(FLASH_SECONDS)
			KEY_5: _do_all()
	elif event is InputEventMouseButton and event.pressed:
		_do_burst(get_global_mouse_position())


func _do_burst(at: Vector2) -> void:
	_burst.burst(at, BURST_COLOR, Vector2.UP)


func _do_all() -> void:
	_do_burst(_target.position)
	_shake.shake(SHAKE_STRENGTH)
	_freeze.freeze(FREEZE_FRAMES)
	_flash.flash(FLASH_SECONDS)


func _make_box(poly: Polygon2D, size: Vector2, color: Color) -> void:
	var h: Vector2 = size * 0.5
	poly.polygon = PackedVector2Array([-h, Vector2(h.x, -h.y), h, Vector2(-h.x, h.y)])
	poly.color = color


func _add_wall(center: Vector2, size: Vector2) -> void:
	var body: StaticBody2D = StaticBody2D.new()
	body.collision_layer = DebrisLayers.WORLD
	body.collision_mask = 0
	body.position = center
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = size
	var collider: CollisionShape2D = CollisionShape2D.new()
	collider.shape = shape
	body.add_child(collider)
	add_child(body)


func _add_buttons() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	var row: HBoxContainer = HBoxContainer.new()
	row.position = Vector2(12.0, 12.0)
	layer.add_child(row)
	var names: Array[String] = ["1 Burst", "2 Shake", "3 Freeze", "4 Flash", "5 All"]
	var actions: Array[Callable] = [
		func() -> void: _do_burst(_target.position),
		func() -> void: _shake.shake(SHAKE_STRENGTH),
		func() -> void: _freeze.freeze(FREEZE_FRAMES),
		func() -> void: _flash.flash(FLASH_SECONDS),
		_do_all,
	]
	for i: int in names.size():
		var button: Button = Button.new()
		button.text = names[i]
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(actions[i])
		row.add_child(button)


func _add_label() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	var label: Label = Label.new()
	label.text = "Keys 1-5 or the buttons. Tap empty screen for a burst there."
	label.position = Vector2(12.0, 64.0)
	layer.add_child(label)
