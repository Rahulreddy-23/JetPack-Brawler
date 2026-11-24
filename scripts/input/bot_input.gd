class_name BotInput
extends Node
## Input node of one bot. Owned by the peer that plays the bot; netfox sends
## these properties to the server, which feeds them into the simulation.
## Per netfox guidance, values are recorded after each network tick: held
## values are sampled, one-off presses are latched until the next tick.

## These four are Variant on purpose: a remote client can send any type, and the
## bot treats a wrong type as neutral input (see Bot.clean_vector).
## Left stick: x runs, y up fires the jetpack, y down drops through thin platforms.
var move: Variant = Vector2.ZERO
## Right stick (or mouse) aim direction. Zero means no aim input.
var aim: Variant = Vector2.ZERO
## True if the jetpack was requested at any frame since the last tick.
var jet: Variant = false
## True if the dash button was pressed at any frame since the last tick.
var dash: Variant = false

## Scripted input for the network smoke test (set by the launcher).
var autopilot: bool = false
## Ticks to wait after spawning before the autopilot script starts.
var autopilot_delay_ticks: int = 0

var _cfg: TuningConfig = TuningConfig.get_default()
var _jet_latch: bool = false
var _dash_latch: bool = false
var _autopilot_start_tick: int = -1

@onready var _bot: Node2D = get_parent() as Node2D

func _ready() -> void:
	InputActions.ensure_registered()
	NetworkTime.after_tick.connect(_on_after_tick)

func _process(_delta: float) -> void:
	if not is_multiplayer_authority():
		return
	if Input.get_action_strength(InputActions.MOVE_UP) > _cfg.stick_digital_threshold:
		_jet_latch = true
	if Input.is_action_just_pressed(InputActions.DASH):
		_dash_latch = true

func _on_after_tick(_delta: float, tick: int) -> void:
	if not is_multiplayer_authority():
		return
	if autopilot:
		_gather_autopilot(tick)
	else:
		_gather_device()

func _gather_device() -> void:
	var stick_move: Vector2 = Input.get_vector(InputActions.MOVE_LEFT, InputActions.MOVE_RIGHT, InputActions.MOVE_UP, InputActions.MOVE_DOWN)
	move = stick_move
	var stick_aim: Vector2 = Input.get_vector(InputActions.AIM_LEFT, InputActions.AIM_RIGHT, InputActions.AIM_UP, InputActions.AIM_DOWN)
	if stick_aim.length() > _cfg.stick_deadzone:
		aim = stick_aim
	elif DisplayServer.is_touchscreen_available():
		aim = Vector2.ZERO
	else:
		aim = (_bot.get_global_mouse_position() - _bot.global_position).normalized()
	jet = _jet_latch or stick_move.y < -_cfg.stick_digital_threshold
	dash = _dash_latch
	_jet_latch = false
	_dash_latch = false

func _gather_autopilot(tick: int) -> void:
	if _autopilot_start_tick < 0:
		_autopilot_start_tick = tick + autopilot_delay_ticks
	var step: Dictionary = AutopilotScript.sample(tick - _autopilot_start_tick, _cfg.tick_rate)
	move = step.get("move", Vector2.ZERO) as Vector2
	aim = step.get("aim", Vector2.ZERO) as Vector2
	jet = step.get("jet", false) as bool
	dash = step.get("dash", false) as bool
