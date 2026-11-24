extends Node
## Active sessions refuse replacement, and a closing session keeps its own end message.
## Run: godot --headless res://tests/test_session_guard.tscn -- --port=N

var _failed: bool = false
var _last_end_message: String = ""

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
	session.ended.connect(func(message: String) -> void: _last_end_message = message)
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

	# Model a host dropping the rejected connection before initial clock sync completes.
	session._match_full()
	session._on_server_disconnected()
	_check(_last_end_message == Session.MATCH_FULL_MESSAGE, "host disconnect after rejection keeps the match-full message")
	_check(session.join("127.0.0.1", port) == OK, "joining again after rejection succeeds")
	session._on_server_disconnected()
	_check(_last_end_message == "The host went away.", "a later disconnect does not reuse the rejection message")
	_check(session.host(port, 4) == OK, "host starts while an old rejection is deferred")
	for frame: int in 3:
		await get_tree().process_frame
	_check(session.is_active() and NetworkTime.is_initial_sync_done(), "a deferred rejection leaves the new host active")
	session.leave()

	get_tree().quit(1 if _failed else 0)
