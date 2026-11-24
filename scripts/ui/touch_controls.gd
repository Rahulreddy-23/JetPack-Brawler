class_name TouchControls
extends Control
## Two floating virtual sticks and a dash button for two thumbs. The left stick
## (left part of the screen) is movement; the right stick (rest of the screen)
## is aim; the dash button sits at the lower right. Output goes through the
## InputActions, the same ones the keyboard uses.

## Treat the left mouse button like a finger (desktop check with --touch-ui).
var use_mouse: bool = false

var _cfg: TuningConfig = TuningConfig.get_default()
var _move: Stick = Stick.new()
var _aim: Stick = Stick.new()
var _dash_finger: int = -1

class Stick extends RefCounted:
	var finger: int = -1
	var origin: Vector2 = Vector2.ZERO
	var position: Vector2 = Vector2.ZERO

	func value(radius: float) -> Vector2:
		return ((position - origin) / radius).limit_length(1.0) if finger != -1 else Vector2.ZERO

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visibility_changed.connect(_on_visibility_changed)

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event as InputEventScreenTouch
		_touch(touch.index, touch.position, touch.pressed)
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event as InputEventScreenDrag
		_drag(drag.index, drag.position)
	elif use_mouse and event is InputEventMouseButton:
		var button: InputEventMouseButton = event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			_touch(0, button.position, button.pressed)
	elif use_mouse and event is InputEventMouseMotion:
		_drag(0, (event as InputEventMouseMotion).position)

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var fill: Color = Color(Color.WHITE, _cfg.overlay_alpha / 2.0)
	var line: Color = Color(Color.WHITE, _cfg.overlay_alpha)
	_draw_stick(_move, _idle_center(true), fill, line)
	_draw_stick(_aim, _idle_center(false), fill, line)
	draw_circle(_dash_center(), _cfg.dash_button_radius_px, fill if _dash_finger == -1 else line)
	draw_circle(_dash_center(), _cfg.dash_button_radius_px, line, false)

func _draw_stick(stick: Stick, idle_center: Vector2, fill: Color, line: Color) -> void:
	var center: Vector2 = stick.origin if stick.finger != -1 else idle_center
	draw_circle(center, _cfg.stick_radius_px, fill)
	draw_circle(center, _cfg.stick_radius_px, line, false)
	draw_circle(center + stick.value(_cfg.stick_radius_px) * _cfg.stick_radius_px, _cfg.stick_radius_px / 2.0, line)

func _idle_center(left: bool) -> Vector2:
	var margin: float = _cfg.stick_radius_px + _cfg.hud_margin_px
	return Vector2(margin if left else size.x - margin, size.y - margin)

func _dash_center() -> Vector2:
	return size - _cfg.dash_button_offset_px

func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	if pressed:
		if pos.distance_to(_dash_center()) <= _cfg.dash_button_radius_px:
			_dash_finger = index
			Input.action_press(InputActions.DASH)
		elif pos.x < size.x * _cfg.move_zone_fraction:
			if _move.finger == -1:
				_move.finger = index
				_move.origin = pos
				_move.position = pos
		elif _aim.finger == -1:
			_aim.finger = index
			_aim.origin = pos
			_aim.position = pos
	else:
		if index == _dash_finger:
			_dash_finger = -1
			Input.action_release(InputActions.DASH)
		if index == _move.finger:
			_move.finger = -1
			_publish()
		if index == _aim.finger:
			_aim.finger = -1
			_publish()

func _drag(index: int, pos: Vector2) -> void:
	if index == _move.finger:
		_move.position = pos
	elif index == _aim.finger:
		_aim.position = pos
	_publish()

func _publish() -> void:
	_set_axis(InputActions.MOVE_LEFT, InputActions.MOVE_RIGHT, InputActions.MOVE_UP, InputActions.MOVE_DOWN, _move.value(_cfg.stick_radius_px))
	_set_axis(InputActions.AIM_LEFT, InputActions.AIM_RIGHT, InputActions.AIM_UP, InputActions.AIM_DOWN, _aim.value(_cfg.stick_radius_px))

func _set_axis(left: StringName, right: StringName, up: StringName, down: StringName, value: Vector2) -> void:
	_set_action(left, maxf(-value.x, 0.0))
	_set_action(right, maxf(value.x, 0.0))
	_set_action(up, maxf(-value.y, 0.0))
	_set_action(down, maxf(value.y, 0.0))

func _set_action(action: StringName, strength: float) -> void:
	if strength > 0.0:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)

func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		_move.finger = -1
		_aim.finger = -1
		_dash_finger = -1
		_publish()
		Input.action_release(InputActions.DASH)
