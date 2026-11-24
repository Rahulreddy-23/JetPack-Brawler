class_name InputActions
extends RefCounted
## Registers the game's input actions in code, so touch and keyboard share one
## set of names. Touch controls press these actions; the bot reads them.

const MOVE_LEFT: StringName = &"move_left"
const MOVE_RIGHT: StringName = &"move_right"
const MOVE_UP: StringName = &"move_up"
const MOVE_DOWN: StringName = &"move_down"
const AIM_LEFT: StringName = &"aim_left"
const AIM_RIGHT: StringName = &"aim_right"
const AIM_UP: StringName = &"aim_up"
const AIM_DOWN: StringName = &"aim_down"
const DASH: StringName = &"dash"

## Add every action once. Safe to call repeatedly.
static func ensure_registered() -> void:
	_add(MOVE_LEFT, [KEY_A, KEY_LEFT])
	_add(MOVE_RIGHT, [KEY_D, KEY_RIGHT])
	_add(MOVE_UP, [KEY_W, KEY_UP])
	_add(MOVE_DOWN, [KEY_S, KEY_DOWN])
	_add(AIM_LEFT, [])
	_add(AIM_RIGHT, [])
	_add(AIM_UP, [])
	_add(AIM_DOWN, [])
	_add(DASH, [KEY_SPACE, KEY_SHIFT])

static func _add(action: StringName, keys: Array[Key]) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for key: Key in keys:
		var event: InputEventKey = InputEventKey.new()
		event.physical_keycode = key
		InputMap.action_add_event(action, event)
