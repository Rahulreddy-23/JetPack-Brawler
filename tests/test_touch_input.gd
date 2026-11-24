extends Node
## Fire, melee, gadget and swap from touch: the aim ring, the quick tap, the buttons, finger
## capture rules, focus loss, and the one-tick delivery of the edge inputs at several frame
## rates. Touch events are routed to TouchControls._input like the other touch tests.
## A virtual clock plays frames and network ticks the way netfox's loop does (after each frame,
## as many ticks as the clock has fallen behind), so every case is exact and repeatable.
## Run: godot --headless --path . res://tests/test_touch_input.tscn

## Frame rates tried: several frames per 30 Hz tick, one per tick, several ticks per frame.
const FRAME_RATES: Array[int] = [60, 30, 20, 10]
## Smallest touch target the task allows, in viewport pixels (48 dp is about 84 px on a phone
## whose 720 px viewport height is about 411 dp; the task wants about 9 mm, which is more).
const MIN_TARGET_PX: float = 84.0
## Keeps a clock that is a hair over a whole tick from counting as a second tick.
const FLOAT_SLACK: float = 0.000001
## netfox's max_ticks_per_frame.
const MAX_TICKS_PER_FRAME: int = 8

var _failed: bool = false
var _cfg: TuningConfig = TuningConfig.get_default()
var _controls: TouchControls = null
var _input: BotInput = null
var _now: float = 0.0
var _next_tick_time: float = 0.0
var _tick: int = 0
## One entry per simulated tick: the tick, then the values BotInput left for it.
var _log: Array[Dictionary] = []
var _next_finger: int = 10

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		_failed = true

func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.index = index
	event.position = pos
	event.pressed = pressed
	_controls._input(event)

func _drag(index: int, pos: Vector2) -> void:
	var event: InputEventScreenDrag = InputEventScreenDrag.new()
	event.index = index
	event.position = pos
	_controls._input(event)

# A new control set and bot input. The bot input has gathered once unless prime is false, as a
# bot that has been running does; an unprimed one is a bot that has just spawned.
func _fresh(prime: bool = true) -> void:
	if _controls != null:
		_controls._release_all()
		_controls.free()
		_input.get_parent().free()
	InputActions.clear_edges()
	_controls = TouchControls.new()
	_controls.clock_msec = func() -> int: return roundi(_now * 1000.0)
	add_child(_controls)
	var parent: Node2D = Node2D.new()
	_input = BotInput.new()
	parent.add_child(_input)
	add_child(parent)
	if prime:
		_input._on_after_tick(0.0, 0)
	_log.clear()
	_now = 0.0
	_next_tick_time = 0.0
	_tick = 0

func _cancel(index: int, pos: Vector2) -> void:
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.index = index
	event.position = pos
	event.pressed = false
	event.canceled = true
	_controls._input(event)

# One rendered frame of this length. Ticks follow netfox: as many as the clock has fallen
# behind, at most MAX_TICKS_PER_FRAME, each gathered in after_tick.
func _frame(fps: int) -> void:
	_now += 1.0 / float(fps)
	var dt: float = 1.0 / float(_cfg.tick_rate)
	var ticks: int = mini(int(ceil((_now - _next_tick_time) / dt - FLOAT_SLACK)), MAX_TICKS_PER_FRAME)
	for i: int in maxi(ticks, 0):
		_input._on_after_tick(dt, _tick)
		_log.append({"tick": _tick, "melee": _input.melee, "gadget": _input.gadget, "swap": _input.swap, "fire": _input.fire, "aim": _input.aim})
		_tick += 1
		_next_tick_time += dt

func _frames(fps: int, seconds: float) -> void:
	for i: int in roundi(seconds * float(fps)):
		_frame(fps)

# How many recorded ticks had this input true, and whether two such ticks were adjacent.
func _true_ticks(field: String) -> Array[int]:
	var ticks: Array[int] = []
	for entry: Dictionary in _log:
		if entry[field] == true:
			ticks.append(entry["tick"] as int)
	return ticks

func _adjacent(ticks: Array[int]) -> bool:
	for i: int in range(1, ticks.size()):
		if ticks[i] == ticks[i - 1] + 1:
			return true
	return false

func _aim_start() -> Vector2:
	return Vector2(_controls.size.x * 0.8, _controls.size.y * 0.3)

# Press a button for hold seconds on a frame, counted in whole frames; 0 means down and up
# inside the same frame.
func _press_button(action: StringName, fps: int, hold: float) -> void:
	var finger: int = _next_finger
	_next_finger += 1
	_touch(finger, _controls.button_center(action), true)
	if hold <= 0.0:
		_touch(finger, _controls.button_center(action), false)
		_frame(fps)
	else:
		_frames(fps, hold)
		_touch(finger, _controls.button_center(action), false)

func _run() -> void:
	InputActions.ensure_registered()
	_fresh()
	await get_tree().process_frame
	await get_tree().process_frame
	_test_fire_ring()
	_test_tap_and_melee_button()
	_test_edge_latching()
	_test_consecutive_presses()
	_test_pending_cap_and_spawn()
	_test_cancel()
	_test_capture_rules()
	_test_two_fingers()
	_test_focus_out()
	_test_layout()
	_test_keyboard_and_mouse()
	_test_input_types()
	get_tree().quit(1 if _failed else 0)

func _test_fire_ring() -> void:
	_fresh()
	var radius: float = _cfg.stick_radius_px
	var start: Vector2 = _aim_start()
	_touch(0, start, true)
	_drag(0, start + Vector2(radius * _cfg.fire_ring_fraction * 0.5, 0.0))
	_check(not Input.is_action_pressed(InputActions.FIRE), "a drag inside the ring does not fire")
	_check(Input.get_action_strength(InputActions.AIM_RIGHT) > 0.0, "inside the ring the aim still points right")
	_drag(0, start + Vector2(radius * _cfg.fire_ring_fraction + 2.0, 0.0))
	_check(Input.is_action_pressed(InputActions.FIRE), "a drag past the ring fires")
	_frame(30)
	_check(_input.fire == true and (_input.aim as Vector2).x > 0.5, "BotInput carries fire and the aim direction")
	var aim_past: float = Input.get_action_strength(InputActions.AIM_RIGHT)
	_drag(0, start + Vector2(radius * 3.0, 0.0))
	_check(Input.is_action_pressed(InputActions.FIRE) and Input.get_action_strength(InputActions.AIM_RIGHT) >= aim_past, "far past the ring still fires with the same direction")
	_drag(0, start + Vector2(radius * _cfg.fire_ring_fraction - 2.0, 0.0))
	_check(not Input.is_action_pressed(InputActions.FIRE), "dragging back inside the ring stops fire")
	_drag(0, start + Vector2(0.0, radius))
	_check(Input.is_action_pressed(InputActions.FIRE), "fire works in any direction (down)")
	_touch(0, start, false)
	_check(not Input.is_action_pressed(InputActions.FIRE), "releasing clears fire")
	_check(Input.get_action_strength(InputActions.AIM_DOWN) == 0.0, "releasing clears aim")
	_frame(30)
	_check(_input.fire == false, "BotInput clears fire after release")

func _test_tap_and_melee_button() -> void:
	for fps: int in FRAME_RATES:
		# A quick tap: down and up one frame apart, well under the tap time.
		_fresh()
		_touch(0, _aim_start(), true)
		_frame(fps)
		_touch(0, _aim_start(), false)
		_frames(fps, 0.5)
		_check(_true_ticks("melee").size() == 1, "quick tap on the aim stick: melee for exactly one tick at %d fps" % fps)
		_check(_true_ticks("fire").is_empty(), "quick tap never fires at %d fps" % fps)
	# Tap and release inside one frame.
	_fresh()
	_touch(0, _aim_start(), true)
	_touch(0, _aim_start(), false)
	_frames(30, 0.5)
	_check(_true_ticks("melee").size() == 1 and _true_ticks("fire").is_empty(), "a tap that begins and ends in one frame swings once and never fires")

	# Too slow.
	_fresh()
	_touch(0, _aim_start(), true)
	_frames(30, _cfg.tap_time + 0.2)
	_touch(0, _aim_start(), false)
	_frames(30, 0.5)
	_check(_true_ticks("melee").is_empty() and _true_ticks("fire").is_empty(), "a slow press gives no melee and no fire")

	# Moved past the tap distance but inside the fire ring: not a tap, not a shot.
	_fresh()
	_touch(0, _aim_start(), true)
	_drag(0, _aim_start() + Vector2(_cfg.tap_distance_px + 4.0, 0.0))
	_check(_cfg.tap_distance_px + 4.0 < _cfg.stick_radius_px * _cfg.fire_ring_fraction, "the moved touch stays inside the fire ring")
	_frame(30)
	_drag(0, _aim_start())
	_touch(0, _aim_start(), false)
	_frames(30, 0.5)
	_check(_true_ticks("melee").is_empty() and _true_ticks("fire").is_empty(), "a touch that moved past the tap distance gives no melee, even if it came back")

	# A drag that fired and was released quickly is not a tap.
	_fresh()
	_touch(0, _aim_start(), true)
	_drag(0, _aim_start() + Vector2(_cfg.stick_radius_px, 0.0))
	_touch(0, _aim_start() + Vector2(_cfg.stick_radius_px, 0.0), false)
	_frames(30, 0.5)
	_check(_true_ticks("melee").is_empty(), "releasing a quick fire drag is not a melee tap")

	# The tap distance must leave room under the fire ring so a tap can never fire.
	_check(_cfg.tap_distance_px < _cfg.stick_radius_px * _cfg.fire_ring_fraction, "config: tap distance is inside the fire ring")

	for fps: int in FRAME_RATES:
		for hold: float in [0.0, 0.05, 1.0]:
			_fresh()
			_press_button(InputActions.MELEE, fps, hold)
			_frames(fps, 0.5)
			var ticks: Array[int] = _true_ticks("melee")
			_check(ticks.size() == 1, "melee button, hold %.2f s at %d fps: exactly one tick (got %d)" % [hold, fps, ticks.size()])
			_check(_true_ticks("fire").is_empty(), "melee button never fires (hold %.2f at %d fps)" % [hold, fps])

func _test_edge_latching() -> void:
	for action: StringName in [InputActions.GADGET, InputActions.SWAP]:
		for fps: int in FRAME_RATES:
			for hold: float in [0.0, 0.05, 1.0]:
				_fresh()
				_press_button(action, fps, hold)
				_frames(fps, 0.5)
				var ticks: Array[int] = _true_ticks(String(action))
				_check(ticks.size() == 1, "%s button, hold %.2f s at %d fps: exactly one tick (got %d)" % [action, hold, fps, ticks.size()])
				for other: StringName in InputActions.EDGE_ACTIONS:
					if other != action:
						_check(_true_ticks(String(other)).is_empty(), "%s does not set %s (hold %.2f at %d fps)" % [action, other, hold, fps])

func _test_consecutive_presses() -> void:
	for action: StringName in InputActions.EDGE_ACTIONS:
		for fps: int in FRAME_RATES:
			# Start the pair after 0 to 3 idle frames, so at 60 fps both frames with a tick between
			# them and frames without one are covered.
			for idle: int in 4:
				_fresh()
				_frames(fps, float(idle) / float(fps))
				# Two presses in two consecutive frames, each a down and up inside its frame.
				_press_button(action, fps, 0.0)
				_press_button(action, fps, 0.0)
				_frames(fps, 0.5)
				var ticks: Array[int] = _true_ticks(String(action))
				_check(ticks.size() == 2 and not _adjacent(ticks), "%s: two presses in consecutive frames give two separate ticks at %d fps after %d idle frames (got %s)" % [action, fps, idle, ticks])
	# Two quick taps on the aim stick.
	_fresh()
	for i: int in 2:
		_touch(0, _aim_start(), true)
		_frame(60)
		_touch(0, _aim_start(), false)
		_frame(60)
	_frames(60, 0.5)
	_check(_true_ticks("melee").size() == 2, "two quick taps on the aim stick give two melee ticks")
	# A press while no tick runs is kept, not lost.
	_fresh()
	_touch(0, _controls.button_center(InputActions.MELEE), true)
	_touch(0, _controls.button_center(InputActions.MELEE), false)
	_input._on_after_tick(0.0, 0)
	_check(_input.melee == true, "a press made before any tick is delivered at the next tick")
	_input._on_after_tick(0.0, 1)
	_check(_input.melee == false, "and is not repeated on the tick after")

func _test_pending_cap_and_spawn() -> void:
	# More presses than the cap before one tick deliver at most the cap, on separate ticks.
	var cap: int = _cfg.max_pending_presses
	for action: StringName in InputActions.EDGE_ACTIONS:
		_fresh()
		for i: int in cap * 3 + 2:
			_touch(i, _controls.button_center(action) if action != InputActions.MELEE else _aim_start(), true)
			_touch(i, _controls.button_center(action) if action != InputActions.MELEE else _aim_start(), false)
		_frames(60, 1.0)
		var ticks: Array[int] = _true_ticks(String(action))
		_check(ticks.size() == cap and not _adjacent(ticks), "%d presses of %s before any tick deliver exactly the cap of %d (got %d)" % [cap * 3 + 2, action, cap, ticks.size()])
	# Presses made before the bot exists are not played back when it spawns.
	_fresh(false)
	for action: StringName in InputActions.EDGE_ACTIONS:
		_touch(0, _controls.button_center(action), true)
		_touch(0, _controls.button_center(action), false)
	_touch(1, _aim_start(), true)
	_touch(1, _aim_start(), false)
	_frames(60, 1.0)
	_check(_true_ticks("melee").is_empty() and _true_ticks("gadget").is_empty() and _true_ticks("swap").is_empty(), "presses made before the bot exists are not delivered after it spawns")
	# The same bot then takes presses as usual.
	_press_button(InputActions.SWAP, 60, 0.0)
	_frames(60, 0.5)
	_check(_true_ticks("swap").size() == 1, "a press after the bot started gathering is delivered")

func _test_cancel() -> void:
	# A cancelled aim-zone touch is not a tap, and releases fire.
	_fresh()
	_touch(0, _aim_start(), true)
	_frame(60)
	_cancel(0, _aim_start())
	_frames(60, 0.5)
	_check(_true_ticks("melee").is_empty(), "a cancelled touch in the aim zone is not a melee tap")
	_fresh()
	_touch(0, _aim_start(), true)
	_drag(0, _aim_start() + Vector2(_cfg.stick_radius_px, 0.0))
	_check(Input.is_action_pressed(InputActions.FIRE), "fire held before the cancel")
	_cancel(0, _aim_start())
	_check(not Input.is_action_pressed(InputActions.FIRE) and Input.get_action_strength(InputActions.AIM_RIGHT) == 0.0, "a cancelled touch releases fire and aim")
	_frames(60, 0.5)
	_check(_true_ticks("melee").is_empty() and _true_ticks("fire").is_empty(), "and neither melee nor fire reaches the bot")
	# A cancelled move touch releases the stick.
	_fresh()
	_touch(0, Vector2(100.0, 300.0), true)
	_drag(0, Vector2(200.0, 300.0))
	_cancel(0, Vector2(200.0, 300.0))
	_check(Input.get_action_strength(InputActions.MOVE_RIGHT) == 0.0, "a cancelled move touch releases the move stick")
	# A cancelled touch on each button releases it and is not a press.
	for action: StringName in [InputActions.DASH, InputActions.MELEE, InputActions.GADGET, InputActions.SWAP]:
		_fresh()
		_touch(0, _controls.button_center(action), true)
		_cancel(0, _controls.button_center(action))
		_check(not _controls.is_button_held(action) and not Input.is_action_pressed(InputActions.DASH), "a cancelled touch releases the %s button" % action)
		_frames(60, 0.5)
		_check(_true_ticks("melee").is_empty() and _true_ticks("gadget").is_empty() and _true_ticks("swap").is_empty(), "a cancelled touch on the %s button is not a press" % action)
	# A cancel does not remove a different, real press that is still waiting.
	_fresh()
	_touch(0, _controls.button_center(InputActions.GADGET), true)
	_touch(0, _controls.button_center(InputActions.GADGET), false)
	_touch(1, _controls.button_center(InputActions.GADGET), true)
	_cancel(1, _controls.button_center(InputActions.GADGET))
	_touch(2, _controls.button_center(InputActions.SWAP), true)
	_cancel(2, _controls.button_center(InputActions.SWAP))
	_frames(60, 0.5)
	_check(_true_ticks("gadget").size() == 1 and _true_ticks("swap").is_empty(), "a cancel takes back only its own press")

func _test_capture_rules() -> void:
	# A finger that starts on a button is not captured by a stick, even when it slides off.
	_fresh()
	var dash: Vector2 = _controls.button_center(InputActions.DASH)
	_touch(0, dash, true)
	_check(Input.is_action_pressed(InputActions.DASH), "dash button presses dash")
	_drag(0, dash + Vector2(-300.0, 0.0))
	_check(Input.get_action_strength(InputActions.AIM_LEFT) == 0.0 and Input.get_action_strength(InputActions.AIM_UP) == 0.0, "a finger that began on a button does not drive the aim stick")
	_check(not Input.is_action_pressed(InputActions.FIRE), "and does not fire")
	_touch(0, dash + Vector2(-300.0, 0.0), false)
	_check(not Input.is_action_pressed(InputActions.DASH), "lifting it releases the button")
	# The same for a button on the right side with a drag towards the move zone.
	_touch(1, _controls.button_center(InputActions.GADGET), true)
	_drag(1, Vector2(50.0, 50.0))
	_check(Input.get_action_strength(InputActions.MOVE_LEFT) == 0.0 and Input.get_action_strength(InputActions.MOVE_UP) == 0.0, "a finger that began on a button does not drive the move stick")
	_touch(1, Vector2(50.0, 50.0), false)
	_frames(30, 0.5)
	_check(_true_ticks("gadget").size() == 1, "the gadget press counted once")

	# A stick drag crossing a button does not press it.
	_fresh()
	var start: Vector2 = _aim_start()
	_touch(0, start, true)
	for target: StringName in [InputActions.DASH, InputActions.MELEE, InputActions.GADGET, InputActions.SWAP]:
		_drag(0, _controls.button_center(target))
		_drag(0, start)
	_touch(0, start, false)
	_frames(30, 0.5)
	_check(not Input.is_action_pressed(InputActions.DASH), "a stick drag over the dash button does not press it")
	_check(_true_ticks("gadget").is_empty() and _true_ticks("swap").is_empty(), "a stick drag over the gadget and swap buttons does not press them")
	_check(_true_ticks("melee").is_empty(), "a stick drag over the melee button does not press it, and is not a tap")

	# A move-stick drag over a button does not press it either.
	_fresh()
	_touch(0, Vector2(100.0, 100.0), true)
	_drag(0, _controls.button_center(InputActions.GADGET))
	_touch(0, _controls.button_center(InputActions.GADGET), false)
	_frames(30, 0.5)
	_check(_true_ticks("gadget").is_empty(), "a move-stick drag over a button does not press it")

func _test_two_fingers() -> void:
	_fresh()
	_touch(0, _controls.button_center(InputActions.MELEE), true)
	_touch(1, _controls.button_center(InputActions.GADGET), true)
	_check(_controls.is_button_held(InputActions.MELEE) and _controls.is_button_held(InputActions.GADGET), "two fingers on two buttons are both held")
	_touch(2, _controls.button_center(InputActions.SWAP), true)
	_touch(3, _controls.button_center(InputActions.DASH), true)
	_frames(30, 0.5)
	_touch(0, _controls.button_center(InputActions.MELEE), false)
	_touch(1, _controls.button_center(InputActions.GADGET), false)
	_touch(2, _controls.button_center(InputActions.SWAP), false)
	_touch(3, _controls.button_center(InputActions.DASH), false)
	_frames(30, 0.5)
	_check(_true_ticks("melee").size() == 1 and _true_ticks("gadget").size() == 1 and _true_ticks("swap").size() == 1, "two fingers on two buttons both register once each")
	# Aim stick held and firing while a button is tapped by another finger.
	_fresh()
	_touch(0, _aim_start(), true)
	_drag(0, _aim_start() + Vector2(_cfg.stick_radius_px, 0.0))
	_touch(1, _controls.button_center(InputActions.GADGET), true)
	_touch(1, _controls.button_center(InputActions.GADGET), false)
	_frames(30, 0.5)
	_check(Input.is_action_pressed(InputActions.FIRE) and _true_ticks("gadget").size() == 1, "a button tap while the aim stick fires: both register, fire stays held")
	_touch(0, _aim_start(), false)

func _test_focus_out() -> void:
	for what: int in [Node.NOTIFICATION_APPLICATION_FOCUS_OUT, Node.NOTIFICATION_APPLICATION_PAUSED]:
		_fresh()
		_touch(0, _aim_start(), true)
		_drag(0, _aim_start() + Vector2(_cfg.stick_radius_px, 0.0))
		_touch(1, _controls.button_center(InputActions.MELEE), true)
		_touch(2, _controls.button_center(InputActions.GADGET), true)
		_touch(3, _controls.button_center(InputActions.SWAP), true)
		_touch(4, _controls.button_center(InputActions.DASH), true)
		_check(Input.is_action_pressed(InputActions.FIRE) and Input.is_action_pressed(InputActions.DASH), "before focus loss: fire and dash held")
		_controls.notification(what)
		_check(not Input.is_action_pressed(InputActions.FIRE), "focus loss %d releases fire" % what)
		_check(not Input.is_action_pressed(InputActions.DASH), "focus loss %d releases dash" % what)
		for action: StringName in InputActions.EDGE_ACTIONS:
			_check(not _controls.is_button_held(action), "focus loss %d releases the %s button" % [what, action])
		_check(Input.get_action_strength(InputActions.AIM_RIGHT) == 0.0, "focus loss %d releases the aim" % what)
		_frames(30, 0.3)
		_check(_true_ticks("melee").is_empty() and _true_ticks("gadget").is_empty() and _true_ticks("swap").is_empty() and _true_ticks("fire").is_empty(), "focus loss %d: nothing reaches the bot afterwards" % what)
		# The old fingers lifting later change nothing; a new finger works.
		_touch(1, _controls.button_center(InputActions.MELEE), false)
		_frames(30, 0.3)
		_check(_true_ticks("melee").is_empty(), "lifting a released finger counts as nothing")
	# Hiding the controls (the menu) releases everything too.
	_fresh()
	_touch(0, _aim_start(), true)
	_drag(0, _aim_start() + Vector2(_cfg.stick_radius_px, 0.0))
	_touch(1, _controls.button_center(InputActions.SWAP), true)
	_controls.visible = false
	_check(not Input.is_action_pressed(InputActions.FIRE) and not _controls.is_button_held(InputActions.SWAP), "hiding the controls releases fire and every button")
	_touch(2, _controls.button_center(InputActions.MELEE), true)
	_touch(2, _controls.button_center(InputActions.MELEE), false)
	_frames(30, 0.3)
	_check(_true_ticks("melee").is_empty() and _true_ticks("swap").is_empty(), "hidden controls ignore touches and drop counted presses")
	_controls.visible = true

func _test_layout() -> void:
	for width: float in [1280.0, 1560.0, 2000.0]:
		_fresh()
		_controls.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		_controls.size = Vector2(width, 720.0)
		var zone_edge: float = width * _cfg.move_zone_fraction
		var actions: Array[StringName] = [InputActions.DASH, InputActions.MELEE, InputActions.GADGET, InputActions.SWAP]
		for i: int in actions.size():
			var center: Vector2 = _controls.button_center(actions[i])
			var radius: float = _cfg.dash_button_radius_px if actions[i] == InputActions.DASH else _cfg.touch_button_radius_px
			_check(radius * 2.0 >= MIN_TARGET_PX, "%s button is at least %d px across" % [actions[i], MIN_TARGET_PX])
			_check(center.x - radius > zone_edge, "%s button is clear of the move zone at width %d" % [actions[i], width])
			_check(center.x + radius < width - _cfg.hud_margin_px and center.y + radius < 720.0 - _cfg.hud_margin_px and center.y - radius > 0.0, "%s button is clear of the screen edges at width %d" % [actions[i], width])
			for j: int in range(i + 1, actions.size()):
				var other_radius: float = _cfg.dash_button_radius_px if actions[j] == InputActions.DASH else _cfg.touch_button_radius_px
				_check(center.distance_to(_controls.button_center(actions[j])) > radius + other_radius, "%s and %s buttons do not overlap at width %d" % [actions[i], actions[j], width])

func _test_keyboard_and_mouse() -> void:
	_fresh()
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = KEY_E
	key.pressed = true
	_input._input(key)
	key = key.duplicate() as InputEventKey
	key.pressed = false
	_input._input(key)
	var echo: InputEventKey = InputEventKey.new()
	echo.physical_keycode = KEY_Q
	echo.pressed = true
	echo.echo = true
	_input._input(echo)
	_frames(30, 0.5)
	_check(_true_ticks("gadget").size() == 1, "the gadget key gives one tick even when pressed and released inside a frame")
	_check(_true_ticks("swap").is_empty(), "a key repeat (echo) is not a press")
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.pressed = true
	_input._input(click)
	_frames(30, 0.5)
	_check(_true_ticks("melee").size() == 1, "the right mouse button swings melee for one tick")
	_check(InputMap.action_has_event(InputActions.FIRE, _left_click()), "the left mouse button is bound to fire")
	_controls.use_mouse = true
	_check(not InputMap.action_has_event(InputActions.FIRE, _left_click()), "in touch-ui mode the mouse is a finger, not fire")
	_controls.use_mouse = false
	_check(InputMap.action_has_event(InputActions.FIRE, _left_click()), "and the binding returns when the mouse is not a finger")

func _left_click() -> InputEventMouseButton:
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	return click

func _test_input_types() -> void:
	_fresh()
	_press_button(InputActions.MELEE, 30, 0.0)
	_frames(30, 0.2)
	_check(typeof(_input.fire) == TYPE_BOOL and typeof(_input.melee) == TYPE_BOOL and typeof(_input.gadget) == TYPE_BOOL and typeof(_input.swap) == TYPE_BOOL, "fire, melee, gadget and swap are bool")
	_check(typeof(_input.aim) == TYPE_VECTOR2 and typeof(_input.move) == TYPE_VECTOR2, "aim and move are Vector2")
	# The bot's own checks still turn a non-finite aim into neutral.
	_check(Bot.clean_vector(Vector2(NAN, 0.0)) == Vector2.ZERO and Bot.clean_vector(Vector2(0.0, INF)) == Vector2.ZERO, "a non-finite aim is still cleaned")
	_check(not Bot.clean_bool("yes") and Bot.clean_bool(true), "a non-bool button value is not a press")
