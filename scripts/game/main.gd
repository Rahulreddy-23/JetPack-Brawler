class_name Main
extends Node
## Wires the start menu, session, arena, spawner, camera, HUD and touch controls
## together. Hosting and joining go through the same bot spawner, so solo play
## (a host with no clients) uses the same code path as a match.

var _cfg: TuningConfig = TuningConfig.get_default()
var _args: LaunchArgs = LaunchArgs.new()
var _local_bot: Bot = null
var _probe: SmokeProbe = null
var _role: String = "menu"
var _joined_text: String = ""

@onready var _session: Session = $Session as Session
@onready var _spawner: BotSpawner = $BotSpawner as BotSpawner
@onready var _camera: Camera2D = $Camera as Camera2D
@onready var _menu: Menu = $MenuLayer/Menu as Menu
@onready var _hud: Hud = $HudLayer/Hud as Hud
@onready var _touch: TouchControls = $TouchLayer/Touch as TouchControls
@onready var _layout: ArenaLayout = ($Arena as Arena).layout

func _ready() -> void:
	_args = LaunchArgs.parse(OS.get_cmdline_user_args())
	if NetworkTime.tickrate != _cfg.tick_rate:
		push_error("netfox tickrate %d differs from config tick_rate %d" % [NetworkTime.tickrate, _cfg.tick_rate])

	_touch.use_mouse = _args.touch_ui
	_touch.visible = _args.touch_ui or DisplayServer.is_touchscreen_available()
	_spawner.autopilot = _args.autopilot
	_spawner.bot_spawned.connect(_on_bot_spawned)
	_session.ended.connect(_on_session_ended)
	_session.peer_accepted.connect(_spawner.on_peer_accepted)
	_menu.host_pressed.connect(_on_host)
	_menu.join_pressed.connect(_on_join)
	_menu.leave_pressed.connect(_on_leave)
	_setup_camera()
	RenderingServer.set_default_clear_color(Color.BLACK)

	if _args.trace:
		_probe = SmokeProbe.new()
		add_child(_probe)
	if _args.quit_after > 0.0:
		get_tree().create_timer(_args.quit_after).timeout.connect(_finish)
	if _args.host:
		_on_host()
	elif not _args.join.is_empty():
		_on_join(_args.join)

func _process(_delta: float) -> void:
	if _local_bot != null and is_instance_valid(_local_bot):
		_camera.global_position = _local_bot.global_position

func _setup_camera() -> void:
	var px: float = _cfg.bot_height_px
	var margin: float = _cfg.camera_margin_px
	_camera.limit_left = int(_layout.bounds.position.x * px - margin)
	_camera.limit_top = int(_layout.bounds.position.y * px - margin)
	_camera.limit_right = int(_layout.bounds.end.x * px + margin)
	_camera.limit_bottom = int(_layout.bounds.end.y * px + margin)

func _port() -> int:
	return _args.port if _args.port > 0 else _cfg.port

func _on_host() -> void:
	var err: Error = _session.host(_port(), _cfg.max_players)
	if err != OK:
		_menu.show_menu("Could not host: %s" % error_string(err))
		return
	_role = "host"
	var addresses: PackedStringArray = Session.local_ipv4_addresses()
	var text: String = "Hosting on %s port %d" % [", ".join(addresses) if not addresses.is_empty() else "no network address found", _port()]
	_menu.show_session(text)
	print("LISTENING port=%d" % _port())

func _on_join(address: String) -> void:
	if address.is_empty():
		_menu.show_menu("Type the host's IP address first.")
		return
	var err: Error = _session.join(address, _port())
	if err != OK:
		_menu.show_menu("Could not connect: %s" % error_string(err))
		return
	_role = "client"
	_joined_text = "Joined %s port %d" % [address, _port()]
	_menu.show_session("Connecting to %s port %d..." % [address, _port()])

func _on_leave() -> void:
	_session.leave()
	_return_to_menu("")

func _on_session_ended(message: String) -> void:
	print("SESSION_ENDED %s" % message)
	_return_to_menu(message)

func _return_to_menu(message: String) -> void:
	_spawner.clear()
	_local_bot = null
	_hud.bot = null
	_joined_text = ""
	_role = "menu"
	_menu.show_menu(message)

func _on_bot_spawned(bot: Bot) -> void:
	print("BOT_SPAWNED peer=%d" % bot.peer_id)
	if bot.peer_id == multiplayer.get_unique_id():
		_local_bot = bot
		_hud.bot = bot
		if _role == "client":
			_menu.show_session(_joined_text)
		_camera.global_position = bot.position

func _finish() -> void:
	if _probe != null:
		_probe.dump(_role)
	get_tree().quit()
