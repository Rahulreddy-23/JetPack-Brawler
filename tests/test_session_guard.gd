extends Node
## host() and join() refuse while a session is active and change nothing.
## Run: godot --headless res://tests/test_session_guard.tscn -- --port=N

var _failed: bool = false

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		_failed = true

func _port() -> int:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--port="):
			return arg.get_slice("=", 1).to_int()
	return 25290

func _run() -> void:
	var session: Session = Session.new()
	get_tree().root.add_child(session)
	await get_tree().process_frame
	var port: int = _port()

	_check(session.host(port, 4) == OK, "first host succeeds")
	var peer: MultiplayerPeer = session.multiplayer.multiplayer_peer
	_check(session.host(port + 1, 4) == ERR_ALREADY_IN_USE, "host while hosting is refused")
	_check(session.join("127.0.0.1", port) == ERR_ALREADY_IN_USE, "join while hosting is refused")
	_check(session.multiplayer.multiplayer_peer == peer, "peer unchanged after refused calls")
	_check(session.is_active(), "still active")
	session.leave()
	_check(not session.is_active(), "inactive after leave")

	_check(session.join("127.0.0.1", port) == OK, "join succeeds when idle")
	peer = session.multiplayer.multiplayer_peer
	_check(session.join("127.0.0.1", port) == ERR_ALREADY_IN_USE, "join while joined is refused")
	_check(session.host(port + 1, 4) == ERR_ALREADY_IN_USE, "host while joined is refused")
	_check(session.multiplayer.multiplayer_peer == peer, "peer unchanged after refused calls (client)")
	session.leave()

	get_tree().quit(1 if _failed else 0)
