extends Node
## Main: touch controls are hidden on the menu and shown only while a session runs;
## the join address must be an IP address.
## Run: godot --headless res://tests/test_main_touch.tscn -- --touch-ui --port=N

var _failed: bool = false

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		_failed = true

func _run() -> void:
	var main: Main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Main
	get_tree().root.add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var touch: TouchControls = main.get_node("TouchLayer/Touch") as TouchControls
	var session: Session = main.get_node("Session") as Session
	var menu: Menu = main.get_node("MenuLayer/Menu") as Menu

	_check(not touch.visible, "touch controls hidden on the menu")
	_check(menu._address_field.max_length >= 39, "address field fits an IPv6 literal")

	for bad: String in ["", "   ", "localhost", "host.example.com", "192.168.1"]:
		menu.show_menu("")
		main._on_join(bad)
		_check(not session.is_active() and session.multiplayer.multiplayer_peer is OfflineMultiplayerPeer, "no connection attempt for '%s'" % bad)
		_check(not menu._message.text.is_empty(), "message shown for '%s'" % bad)
		_check(not touch.visible, "touch controls still hidden after refused '%s'" % bad)

	main._on_join("  127.0.0.1 ")
	_check(session.is_active(), "valid IPv4 address is passed to join")
	main._on_leave()
	_check(not session.is_active(), "left")

	main._on_host()
	_check(touch.visible, "touch controls shown after Host")
	main._on_leave()
	_check(not touch.visible, "touch controls hidden after Leave")
	get_tree().quit(1 if _failed else 0)
