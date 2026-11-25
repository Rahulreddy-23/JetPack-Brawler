class_name TouchControls
extends Control
## Two floating virtual sticks and four buttons for two thumbs. The left stick (left part
## of the screen) is movement; the right stick (rest of the screen) is aim, fires when it is
## pushed past the fire ring, and a quick tap on it swings melee. Dash, melee, gadget and
## swap buttons sit around the right stick. Output goes through the InputActions, the same
## ones the keyboard uses: fire and dash are held actions, melee, gadget and swap are counted
## presses (InputActions.queue_edge) that BotInput turns into one tick each.
##
## A finger that lands on a button belongs to that button until it lifts and never drives a
## stick; a stick drag that slides over a button does not press it (buttons are tested on
## touch down only).

## Treat the left mouse button like a finger (desktop check with --touch-ui). The mouse then
## stops being fire and melee, so one click does not do both.
var use_mouse: bool = false:
	set(value):
		use_mouse = value
		InputActions.set_mouse_bound(not value)

## Milliseconds clock for tap timing; touch events carry no time. Tests replace it.
var clock_msec: Callable = Callable()

var _cfg: TuningConfig = TuningConfig.get_default()
var _move: Stick = Stick.new()
var _aim: Stick = Stick.new()
var _aim_down_msec: int = 0
var _aim_max_px: float = 0.0
var _buttons: Array[TouchButton] = []

class Stick extends RefCounted:
	var finger: int = -1
	var origin: Vector2 = Vector2.ZERO
	var position: Vector2 = Vector2.ZERO

	func value(radius: float) -> Vector2:
		return ((position - origin) / radius).limit_length(1.0) if finger != -1 else Vector2.ZERO

class TouchButton extends RefCounted:
	var action: StringName
	var label: String
	## Centre as an offset from the bottom-right corner.
	var offset: Vector2
	var radius: float
	## True: a press is counted once; false: the action is held while the finger is down.
	var edge: bool
	var finger: int = -1

	func _init(p_action: StringName, p_label: String, p_offset: Vector2, p_radius: float, p_edge: bool) -> void:
		action = p_action
		label = p_label
		offset = p_offset
		radius = p_radius
		edge = p_edge

func _ready() -> void:
	# The actions must exist before any touch, and no bot has registered them yet on the menu.
	InputActions.ensure_registered()
	_buttons = [
		TouchButton.new(InputActions.DASH, "DASH", _cfg.dash_button_offset_px, _cfg.dash_button_radius_px, false),
		TouchButton.new(InputActions.MELEE, "MELEE", _cfg.melee_button_offset_px, _cfg.touch_button_radius_px, true),
		TouchButton.new(InputActions.GADGET, "GADGET", _cfg.gadget_button_offset_px, _cfg.touch_button_radius_px, true),
		TouchButton.new(InputActions.SWAP, "SWAP", _cfg.swap_button_offset_px, _cfg.touch_button_radius_px, true),
	]
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visibility_changed.connect(_on_visibility_changed)
	resized.connect(queue_redraw)

## Centre of the button for an action, in this control's coordinates.
func button_center(action: StringName) -> Vector2:
	for button: TouchButton in _buttons:
		if button.action == action:
			return size - button.offset
	return Vector2.ZERO

## True while a finger holds the button for this action.
func is_button_held(action: StringName) -> bool:
	for button: TouchButton in _buttons:
		if button.action == action:
			return button.finger != -1
	return false

func _notification(what: int) -> void:
	# A finger lifted while the app is in the background never sends its release.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		_release_all()

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event as InputEventScreenTouch
		_touch(touch.index, touch.position, touch.pressed, touch.canceled)
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event as InputEventScreenDrag
		_drag(drag.index, drag.position)
	elif use_mouse and event is InputEventMouseButton:
		var button: InputEventMouseButton = event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			_touch(0, button.position, button.pressed)
	elif use_mouse and event is InputEventMouseMotion:
		_drag(0, (event as InputEventMouseMotion).position)

func _draw() -> void:
	var fill: Color = Color(Color.WHITE, _cfg.overlay_alpha / 2.0)
	var line: Color = Color(Color.WHITE, _cfg.overlay_alpha)
	_draw_stick(_move, _idle_center(true), fill, line, false)
	_draw_stick(_aim, _idle_center(false), fill, line, true)
	var font: Font = ThemeDB.fallback_font
	var font_size: int = _cfg.hud_text_size_px
	for button: TouchButton in _buttons:
		var center: Vector2 = size - button.offset
		draw_circle(center, button.radius, fill if button.finger == -1 else line)
		draw_circle(center, button.radius, line, false, _cfg.touch_ring_width_px)
		var text_size: Vector2 = font.get_string_size(button.label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
		var baseline: float = center.y + (font.get_ascent(font_size) - font.get_descent(font_size)) / 2.0
		draw_string(font, Vector2(center.x - text_size.x / 2.0, baseline), button.label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, line)

func _draw_stick(stick: Stick, idle_center: Vector2, fill: Color, line: Color, has_fire_ring: bool) -> void:
	var center: Vector2 = stick.origin if stick.finger != -1 else idle_center
	draw_circle(center, _cfg.stick_radius_px, fill)
	draw_circle(center, _cfg.stick_radius_px, line, false)
	if has_fire_ring:
		# Past this ring the stick fires.
		var ring: Color = Color.ORANGE if _is_fire_held() else line
		draw_circle(center, _cfg.stick_radius_px * _cfg.fire_ring_fraction, ring, false, _cfg.touch_ring_width_px)
	draw_circle(center + stick.value(_cfg.stick_radius_px) * _cfg.stick_radius_px, _cfg.stick_radius_px / 2.0, line)

func _idle_center(left: bool) -> Vector2:
	var margin: float = _cfg.stick_radius_px + _cfg.hud_margin_px
	return Vector2(margin if left else size.x - margin, size.y - margin)

func _button_at(pos: Vector2) -> TouchButton:
	for button: TouchButton in _buttons:
		if pos.distance_to(size - button.offset) <= button.radius:
			return button
	return null

func _is_fire_held() -> bool:
	return _aim.finger != -1 and _aim.value(_cfg.stick_radius_px).length() >= _cfg.fire_ring_fraction

# A cancelled touch (the system took the gesture) releases what it held and counts as nothing.
func _touch(index: int, pos: Vector2, pressed: bool, canceled: bool = false) -> void:
	if pressed:
		var button: TouchButton = _button_at(pos)
		if button != null:
			# The finger is spoken for even when the button is already held by another one.
			if button.finger == -1:
				_press(button, index)
		elif pos.x < size.x * _cfg.move_zone_fraction:
			if _move.finger == -1:
				_move.finger = index
				_move.origin = pos
				_move.position = pos
		elif _aim.finger == -1:
			_aim.finger = index
			_aim.origin = pos
			_aim.position = pos
			_aim_down_msec = _now_msec()
			_aim_max_px = 0.0
	else:
		for button: TouchButton in _buttons:
			if button.finger == index:
				_release(button)
				if canceled and button.edge:
					InputActions.cancel_edge(button.action)
		if index == _move.finger:
			_move.finger = -1
			_publish()
		if index == _aim.finger:
			if not canceled:
				_update_aim(pos)
			elif _aim_max_px >= _cfg.stick_radius_px * _cfg.fire_ring_fraction:
				InputActions.pending_touch_fire_aim = Vector2.ZERO
			var is_tap: bool = not canceled and float(_now_msec() - _aim_down_msec) / 1000.0 <= _cfg.tap_time and _aim_max_px <= _cfg.tap_distance_px
			_aim.finger = -1
			_publish()
			if is_tap:
				InputActions.queue_edge(InputActions.MELEE)
	queue_redraw()

func _drag(index: int, pos: Vector2) -> void:
	if index == _move.finger:
		_move.position = pos
	elif index == _aim.finger:
		_update_aim(pos)
	else:
		return
	_publish()
	queue_redraw()

func _update_aim(pos: Vector2) -> void:
	var was_firing: bool = _is_fire_held()
	_aim.position = pos
	_aim_max_px = maxf(_aim_max_px, pos.distance_to(_aim.origin))
	if _is_fire_held() and (not was_firing or InputActions.pending_touch_fire_aim != Vector2.ZERO):
		# Arm on crossing and keep updating until BotInput samples it, even if the thumb
		# curves and pulls back inside the ring before the next tick.
		InputActions.pending_touch_fire_aim = _aim.value(_cfg.stick_radius_px)

func _press(button: TouchButton, index: int) -> void:
	button.finger = index
	if button.edge:
		InputActions.queue_edge(button.action)
	else:
		Input.action_press(button.action)

func _release(button: TouchButton) -> void:
	button.finger = -1
	if not button.edge:
		Input.action_release(button.action)

func _now_msec() -> int:
	return clock_msec.call() as int if clock_msec.is_valid() else Time.get_ticks_msec()

func _publish() -> void:
	_set_axis(InputActions.MOVE_LEFT, InputActions.MOVE_RIGHT, InputActions.MOVE_UP, InputActions.MOVE_DOWN, _move.value(_cfg.stick_radius_px))
	_set_axis(InputActions.AIM_LEFT, InputActions.AIM_RIGHT, InputActions.AIM_UP, InputActions.AIM_DOWN, _aim.value(_cfg.stick_radius_px))
	_set_action(InputActions.FIRE, 1.0 if _is_fire_held() else 0.0)

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
		_release_all()

func _release_all() -> void:
	_move.finger = -1
	_aim.finger = -1
	for button: TouchButton in _buttons:
		_release(button)
	_publish()
	InputActions.clear_edges()
	InputActions.pending_touch_fire_aim = Vector2.ZERO
	queue_redraw()
