extends SceneTree
## Run after importing the project: godot --headless --script res://tests/test_menu_touch.gd

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var menu: Menu = Menu.new()
	root.add_child(menu)
	await process_frame
	await process_frame

	var fields: Array[Node] = menu.find_children("*", "LineEdit", true, false)
	if fields.size() != 1:
		print("FAIL expected one address field")
		quit(1)
		return

	var address: LineEdit = fields[0] as LineEdit
	var center: Vector2 = address.get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var touch: InputEventScreenTouch = InputEventScreenTouch.new()
		touch.position = center
		touch.pressed = pressed
		# Route the touch through the viewport to exercise the actual menu control.
		root.push_input(touch, true)

	if not address.has_focus() or not address.is_editing():
		print("FAIL tapping the address field did not start editing")
		quit(1)
		return
	print("PASS tapping the address field starts editing")
	quit(0)
