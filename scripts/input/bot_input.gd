class_name BotInput
extends Node
## Input node of one bot. Owned by the peer that plays the bot; netfox sends
## these properties to the server, which feeds them into the simulation.
## Per netfox guidance, values are recorded after each network tick: held
## values are sampled, one-off presses are latched until the next tick.

## These are Variant on purpose: a remote client can send any type, and the
## bot treats a wrong type as neutral input (see Bot.clean_vector).
## Left stick: x runs, y up fires the jetpack, y down drops through thin platforms.
var move: Variant = Vector2.ZERO
## Right stick (or mouse) aim direction. Zero means no aim input.
var aim: Variant = Vector2.ZERO
## True if the jetpack was requested at any frame since the last tick.
var jet: Variant = false
## True if the dash button was pressed at any frame since the last tick.
var dash: Variant = false
## True while the fire button (or the aim stick past its outer ring) is held.
var fire: Variant = false
## True for exactly one tick per melee request (quick tap on the aim stick or the melee button).
var melee: Variant = false
## True for exactly one tick per gadget button press.
var gadget: Variant = false
## True for exactly one tick per weapon swap icon press.
var swap: Variant = false

## True for the dummy bot: nobody plays it, so it gathers nothing and its input stays neutral.
var dummy: bool = false
## Scripted input for the network smoke test (set by the launcher).
var autopilot: bool = false
## Ticks to wait after spawning before the autopilot script starts.
var autopilot_delay_ticks: int = 0

var _cfg: TuningConfig = TuningConfig.get_default()
var _jet_latch: bool = false
var _dash_latch: bool = false
var _edge_sent: Dictionary[StringName, bool] = {}
var _started: bool = false
var _autopilot_start_tick: int = -1

@onready var _bot: Node2D = get_parent() as Node2D

func _ready() -> void:
	InputActions.ensure_registered()

func _exit_tree() -> void:
	if NetworkTime.after_tick.is_connected(_on_after_tick):
		NetworkTime.after_tick.disconnect(_on_after_tick)

func _enter_tree() -> void:
	if not NetworkTime.after_tick.is_connected(_on_after_tick):
		NetworkTime.after_tick.connect(_on_after_tick)

# Presses of the edge actions are counted from events, so a press and release inside one
# frame is not lost. Touch counts its own presses in TouchControls.
func _input(event: InputEvent) -> void:
	if dummy or autopilot or not is_multiplayer_authority():
		return
	for action: StringName in InputActions.EDGE_ACTIONS:
		if event.is_action_pressed(action):
			InputActions.queue_edge(action)

func _process(_delta: float) -> void:
	if dummy or not is_multiplayer_authority():
		return
	if Input.get_action_strength(InputActions.MOVE_UP) > _cfg.stick_digital_threshold:
		_jet_latch = true
	if Input.is_action_just_pressed(InputActions.DASH):
		_dash_latch = true

func _on_after_tick(_delta: float, tick: int) -> void:
	if dummy or not is_multiplayer_authority():
		return
	if autopilot:
		_gather_autopilot(tick)
	else:
		if not _started:
			# Presses made before this bot existed (while connecting) are not played back.
			_started = true
			InputActions.clear_edges()
			InputActions.pending_touch_fire_aim = Vector2.ZERO
		_gather_device()

func _gather_device() -> void:
	var stick_move: Vector2 = Input.get_vector(InputActions.MOVE_LEFT, InputActions.MOVE_RIGHT, InputActions.MOVE_UP, InputActions.MOVE_DOWN)
	move = stick_move
	var stick_aim: Vector2 = Input.get_vector(InputActions.AIM_LEFT, InputActions.AIM_RIGHT, InputActions.AIM_UP, InputActions.AIM_DOWN)
	var fire_held: bool = Input.is_action_pressed(InputActions.FIRE)
	var pending_aim: Vector2 = InputActions.pending_touch_fire_aim
	InputActions.pending_touch_fire_aim = Vector2.ZERO
	if not fire_held and pending_aim != Vector2.ZERO:
		aim = pending_aim
	elif stick_aim.length() > _cfg.stick_deadzone:
		aim = stick_aim
	elif DisplayServer.is_touchscreen_available():
		aim = Vector2.ZERO
	else:
		aim = (_bot.get_global_mouse_position() - _bot.global_position).normalized()
	jet = _jet_latch or stick_move.y < -_cfg.stick_digital_threshold
	dash = _dash_latch
	_jet_latch = false
	_dash_latch = false
	fire = fire_held or pending_aim != Vector2.ZERO
	melee = _next_edge(InputActions.MELEE)
	gadget = _next_edge(InputActions.GADGET)
	swap = _next_edge(InputActions.SWAP)

# This runs once per network tick, right before netfox records the input for it, so each
# counted press becomes true in exactly one recorded tick: the tick after a delivery never
# delivers, and a press that arrives while no tick runs stays counted until one does. Two
# presses before one tick are spread over two ticks with a false tick between them, so the
# consumer always sees two separate edges. The last delivery is remembered here, not read
# back from the input property, because netfox rewrites input properties when it rolls back.
func _next_edge(action: StringName) -> bool:
	var deliver: bool = not _edge_sent.get(action, false) and InputActions.take_edge(action)
	_edge_sent[action] = deliver
	return deliver

func _gather_autopilot(tick: int) -> void:
	if _autopilot_start_tick < 0:
		_autopilot_start_tick = tick + autopilot_delay_ticks
	var step: Dictionary = AutopilotScript.sample(tick - _autopilot_start_tick, _cfg.tick_rate)
	move = step.get("move", Vector2.ZERO) as Vector2
	aim = step.get("aim", Vector2.ZERO) as Vector2
	jet = step.get("jet", false) as bool
	dash = step.get("dash", false) as bool
