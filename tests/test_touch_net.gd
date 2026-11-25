extends Node
## The touch controls against the real netfox tick loop: a host runs the Main scene, touch
## events go through the viewport, and every network tick is sampled right after BotInput
## gathers (netfox records the input for that tick straight after). Melee, gadget and swap
## must be true for exactly one tick per press at 60 and at 20 frames per second, fire is a
## level, and the values have the right types.
## Run: godot --headless --path . res://tests/test_touch_net.tscn -- --touch-ui --port=N

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const FRAME_RATES: Array[int] = [60, 20]
const HOLDS_SECONDS: Array[float] = [0.0, 1.0]
const SETTLE_SECONDS: float = 0.5
const TIMEOUT_SECONDS: float = 120.0

var _failed: bool = false
var _cfg: TuningConfig = TuningConfig.get_default()
var _main: Main = null
var _bot: Bot = null
var _touch: TouchControls = null
var _ticks: Array[Dictionary] = []
var _next_finger: int = 20

func _ready() -> void:
	get_tree().create_timer(TIMEOUT_SECONDS).timeout.connect(_on_timeout)
	_run.call_deferred()

func _on_timeout() -> void:
	print("FAIL timeout, the test did not finish")
	get_tree().quit(1)

func _check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		_failed = true

# Connected after BotInput's own after_tick handler, so it sees the gathered values.
func _on_after_tick(_delta: float, tick: int) -> void:
	if _bot == null:
		return
	_ticks.append({"tick": tick, "melee": _bot.input.melee, "gadget": _bot.input.gadget, "swap": _bot.input.swap, "fire": _bot.input.fire, "aim": _bot.input.aim})

func _touch_event(index: int, pos: Vector2, pressed: bool) -> void:
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.index = index
	event.position = pos
	event.pressed = pressed
	get_viewport().push_input(event, true)

func _drag_event(index: int, pos: Vector2) -> void:
	var event: InputEventScreenDrag = InputEventScreenDrag.new()
	event.index = index
	event.position = pos
	get_viewport().push_input(event, true)

func _count(field: String) -> int:
	var count: int = 0
	for entry: Dictionary in _ticks:
		if entry[field] == true:
			count += 1
	return count

func _aim_start() -> Vector2:
	return Vector2(_touch.size.x * 0.8, _touch.size.y * 0.3)

# One finger on a target: a button, or the aim stick for a melee tap. Hold zero lifts the
# finger in the same frame it went down.
func _press(target: StringName, hold: float) -> void:
	var finger: int = _next_finger
	_next_finger += 1
	var pos: Vector2 = _aim_start() if target == InputActions.FIRE else _touch.button_center(target)
	_touch_event(finger, pos, true)
	if hold > 0.0:
		await get_tree().create_timer(hold).timeout
	_touch_event(finger, pos, false)

func _settle() -> void:
	await get_tree().create_timer(SETTLE_SECONDS).timeout

func _run() -> void:
	_main = MAIN_SCENE.instantiate() as Main
	add_child(_main)
	_touch = _main.get_node("TouchLayer/Touch") as TouchControls
	_main._on_host()
	var bots: Node = _main.get_node("Bots")
	while bots.get_child_count() == 0:
		await get_tree().process_frame
	_bot = bots.get_child(0) as Bot
	NetworkTime.after_tick.connect(_on_after_tick)
	await _settle()
	_check(_touch.visible, "the touch controls are shown while hosting")

	for fps: int in FRAME_RATES:
		Engine.max_fps = fps
		await _settle()
		for hold: float in HOLDS_SECONDS:
			for target: StringName in [InputActions.MELEE, InputActions.GADGET, InputActions.SWAP]:
				_ticks.clear()
				await _press(target, hold)
				await _settle()
				_check(_count(String(target)) == 1, "%s button, hold %.1f s at %d fps: true for exactly one network tick (got %d)" % [target, hold, fps, _count(String(target))])
		# A quick tap on the aim stick: one melee tick, never fire.
		_ticks.clear()
		await _press(InputActions.FIRE, _cfg.tap_time / 2.0)
		await _settle()
		_check(_count("melee") == 1 and _count("fire") == 0, "aim stick tap at %d fps: one melee tick, never fire (melee %d, fire %d)" % [fps, _count("melee"), _count("fire")])

		# Fire is a level: true on every tick while the stick is held past the ring.
		_ticks.clear()
		_touch_event(1, _aim_start(), true)
		_drag_event(1, _aim_start() + Vector2(_cfg.stick_radius_px, 0.0))
		await _settle()
		var held: int = _ticks.size()
		_check(held > 0 and _count("fire") == held, "fire is true on every tick while held at %d fps (%d of %d)" % [fps, _count("fire"), held])
		_check(typeof(_bot.input.fire) == TYPE_BOOL and typeof(_bot.input.melee) == TYPE_BOOL and typeof(_bot.input.gadget) == TYPE_BOOL and typeof(_bot.input.swap) == TYPE_BOOL, "fire, melee, gadget and swap reach the input node as bool")
		_check(typeof(_bot.input.aim) == TYPE_VECTOR2 and (_bot.input.aim as Vector2).x > 0.5, "aim reaches the input node as a Vector2 pointing the stick's way")
		# Focus loss releases the held fire on the next tick.
		_touch.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		_ticks.clear()
		await _settle()
		_check(_count("fire") == 0 and _bot.input.fire == false, "focus out at %d fps: fire is released" % fps)
		_touch_event(1, _aim_start(), false)

	Engine.max_fps = 0
	# A non-finite aim acts as a neutral stick, including for the aim line.
	_bot.input.move = Vector2.LEFT
	_bot.input.aim = Vector2.UP
	_bot._rollback_tick(1.0 / float(_cfg.tick_rate), NetworkTime.tick, true)
	_check(_bot.aim_dir == Vector2.UP, "the aim line points up before the stick returns to neutral")
	_bot.input.aim = Vector2(NAN, INF)
	_bot._rollback_tick(1.0 / float(_cfg.tick_rate), NetworkTime.tick, true)
	_check(_bot.aim_dir == Vector2.LEFT, "a non-finite aim points the aim line along the bot's facing")
	_bot.input.melee = "yes"
	_bot.input.fire = 7
	_check(not Bot.clean_bool(_bot.input.melee) and not Bot.clean_bool(_bot.input.fire), "wrongly typed button values count as not pressed")

	_main._on_leave()
	get_tree().quit(1 if _failed else 0)
