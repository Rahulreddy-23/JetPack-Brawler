extends SceneTree
## Touch controls release everything on focus loss and ignore drags from untracked fingers.
## Run after importing: godot --headless --script res://tests/test_touch_focus.gd

var _failed: bool = false

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		_failed = true

func _touch(controls: TouchControls, index: int, pos: Vector2, pressed: bool) -> void:
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.index = index
	event.position = pos
	event.pressed = pressed
	controls._input(event)

func _drag(controls: TouchControls, index: int, pos: Vector2) -> void:
	var event: InputEventScreenDrag = InputEventScreenDrag.new()
	event.index = index
	event.position = pos
	controls._input(event)

func _run() -> void:
	InputActions.ensure_registered()
	var controls: TouchControls = TouchControls.new()
	root.add_child(controls)
	await process_frame
	await process_frame
	var move_start: Vector2 = Vector2(100.0, controls.size.y * 0.5)
	var aim_start: Vector2 = Vector2(controls.size.x * 0.8, controls.size.y * 0.5)
	var dash_pos: Vector2 = controls.size - TuningConfig.get_default().dash_button_offset_px

	# Hold the move stick (finger 0) and the dash button (finger 1), then lose focus.
	_touch(controls, 0, move_start, true)
	_drag(controls, 0, move_start + Vector2(60.0, 0.0))
	_touch(controls, 1, dash_pos, true)
	_check(Input.get_action_strength(InputActions.MOVE_RIGHT) > 0.0, "move stick drives move_right")
	_check(Input.is_action_pressed(InputActions.DASH), "dash button presses dash")
	controls.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(Input.get_action_strength(InputActions.MOVE_RIGHT) == 0.0, "focus out: move neutral")
	_check(not Input.is_action_pressed(InputActions.DASH), "focus out: dash released")
	_touch(controls, 0, aim_start, true)
	_drag(controls, 0, aim_start + Vector2(60.0, 0.0))
	_check(Input.get_action_strength(InputActions.AIM_RIGHT) > 0.0, "after focus out a new finger 0 in the aim zone drives aim")
	_check(Input.get_action_strength(InputActions.MOVE_RIGHT) == 0.0, "after focus out that finger does not drive move")
	_touch(controls, 0, aim_start, false)

	# Pause releases too.
	_touch(controls, 0, move_start, true)
	_drag(controls, 0, move_start + Vector2(0.0, -60.0))
	_check(Input.get_action_strength(InputActions.MOVE_UP) > 0.0, "move stick drives move_up")
	controls.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	_check(Input.get_action_strength(InputActions.MOVE_UP) == 0.0, "pause: move neutral")

	# A drag from a finger that holds nothing must not touch held actions (keyboard).
	Input.action_press(InputActions.MOVE_LEFT, 1.0)
	_drag(controls, 7, move_start)
	_check(Input.get_action_strength(InputActions.MOVE_LEFT) == 1.0, "untracked drag leaves keyboard movement alone")
	Input.action_release(InputActions.MOVE_LEFT)

	quit(1 if _failed else 0)
