class_name InputActions
extends RefCounted
## Registers the game's input actions in code, so touch and keyboard share one
## set of names. Touch controls press these actions; the bot reads them.
##
## Fire is a level: the action stays pressed while the player holds it. Melee, gadget and
## swap are edges: a press is counted here with queue_edge and BotInput hands out one
## network tick per counted press (take_edge). They are counted from events, not polled
## from the action state, because a press and release inside one frame would be lost.

const MOVE_LEFT: StringName = &"move_left"
const MOVE_RIGHT: StringName = &"move_right"
const MOVE_UP: StringName = &"move_up"
const MOVE_DOWN: StringName = &"move_down"
const AIM_LEFT: StringName = &"aim_left"
const AIM_RIGHT: StringName = &"aim_right"
const AIM_UP: StringName = &"aim_up"
const AIM_DOWN: StringName = &"aim_down"
const DASH: StringName = &"dash"
const FIRE: StringName = &"fire"
const MELEE: StringName = &"melee"
const GADGET: StringName = &"gadget"
const SWAP: StringName = &"swap"

## The actions delivered as one tick per press.
const EDGE_ACTIONS: Array[StringName] = [MELEE, GADGET, SWAP]

## Desktop mouse buttons: left fires, right swings melee.
const MOUSE_BINDINGS: Dictionary[StringName, MouseButton] = {
	FIRE: MOUSE_BUTTON_LEFT,
	MELEE: MOUSE_BUTTON_RIGHT,
}

static var _mouse_bound: bool = true
static var _pending: Dictionary[StringName, int] = {}

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
	_add(FIRE, [])
	_add(MELEE, [KEY_F])
	_add(GADGET, [KEY_E])
	_add(SWAP, [KEY_Q])
	_apply_mouse_bindings()

## Bind or unbind the desktop mouse buttons. The touch layout treats the mouse as a finger
## (--touch-ui), so it unbinds them to keep one click from also firing.
static func set_mouse_bound(bound: bool) -> void:
	_mouse_bound = bound
	ensure_registered()

## Count one press of an edge action. At most max_pending_presses wait at once.
static func queue_edge(action: StringName) -> void:
	_pending[action] = mini(_pending.get(action, 0) + 1, TuningConfig.get_default().max_pending_presses)

## Take back one counted press that has not been delivered yet (a cancelled touch).
static func cancel_edge(action: StringName) -> void:
	_pending[action] = maxi(_pending.get(action, 0) - 1, 0)

## Consume one counted press. False when none is waiting.
static func take_edge(action: StringName) -> bool:
	var waiting: int = _pending.get(action, 0)
	if waiting <= 0:
		return false
	_pending[action] = waiting - 1
	return true

## Forget every counted press (focus loss, pause, hidden controls).
static func clear_edges() -> void:
	_pending.clear()

static func _add(action: StringName, keys: Array[Key]) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for key: Key in keys:
		var event: InputEventKey = InputEventKey.new()
		event.physical_keycode = key
		InputMap.action_add_event(action, event)

static func _apply_mouse_bindings() -> void:
	for action: StringName in MOUSE_BINDINGS:
		var button: MouseButton = MOUSE_BINDINGS[action]
		var bound: bool = false
		for event: InputEvent in InputMap.action_get_events(action):
			if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == button:
				bound = true
				if not _mouse_bound:
					InputMap.action_erase_event(action, event)
		if _mouse_bound and not bound:
			var click: InputEventMouseButton = InputEventMouseButton.new()
			click.button_index = button
			InputMap.action_add_event(action, click)
