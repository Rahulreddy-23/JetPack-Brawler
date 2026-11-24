extends Node
## Used by tests/net_reject.sh: join a full host again and again as the turned-away player.
##   -- --port=N --rounds=K
## Each round must end with the "Match full" message, leave the session inactive and leave no
## bot on this client (that the host spawned none for it is checked in net_reject.sh from the
## host's log). The client is expected to close its own connection on the message, so the host
## has nothing to drop; a round in which the host dropped it first (server_disconnected) is
## reported as such and is allowed only in a minority of rounds, since a heavily loaded machine
## can make the client miss the host's notice window. Exits 0 on success, 1 otherwise.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const ROUND_TIMEOUT_SECONDS: float = 6.0

var _main: Main = null
var _message: String = ""
var _ended: bool = false
var _dropped_by_host: bool = false

func _ready() -> void:
	_run.call_deferred()

func _fail(reason: String) -> void:
	print("FAIL ", reason)
	get_tree().quit(1)

func _on_ended(message: String) -> void:
	_message = message
	_ended = true

func _run() -> void:
	var port: int = 0
	var rounds: int = 5
	for arg: String in OS.get_cmdline_user_args():
		match arg.get_slice("=", 0):
			"--port":
				port = arg.get_slice("=", 1).to_int()
			"--rounds":
				rounds = arg.get_slice("=", 1).to_int()
	_main = MAIN_SCENE.instantiate() as Main
	get_tree().root.add_child(_main)
	await get_tree().process_frame
	_main._args.port = port
	var session: Session = _main.get_node("Session") as Session
	session.ended.connect(_on_ended)
	session.multiplayer.server_disconnected.connect(func() -> void: _dropped_by_host = true)
	var dropped_rounds: int = 0
	for round_number: int in rounds:
		_ended = false
		_dropped_by_host = false
		var start: int = Time.get_ticks_msec()
		_main._on_join("127.0.0.1")
		while not _ended and float(Time.get_ticks_msec() - start) / 1000.0 < ROUND_TIMEOUT_SECONDS:
			await get_tree().process_frame
		var elapsed: float = float(Time.get_ticks_msec() - start) / 1000.0
		if not _ended:
			_fail("round %d: no message after %.1f s" % [round_number + 1, elapsed])
			return
		if not _message.begins_with("Match full"):
			_fail("round %d: wrong message '%s'" % [round_number + 1, _message])
			return
		if session.is_active():
			_fail("round %d: session still active" % [round_number + 1])
			return
		# Bots the host replicated before dropping the client are freed at the end of the frame.
		for bot: Node in _main.get_node("Bots").get_children():
			if not bot.is_queued_for_deletion():
				_fail("round %d: a bot is left on the rejected client" % [round_number + 1])
				return
		dropped_rounds += int(_dropped_by_host)
		print("PASS round %d: Match full after %.2f s, %s" % [round_number + 1, elapsed, "dropped by the host" if _dropped_by_host else "closed by the client"])
		await get_tree().create_timer(0.3).timeout
	print("%d of %d rounds ended by the client closing, %d by the host dropping it" % [rounds - dropped_rounds, rounds, dropped_rounds])
	if dropped_rounds * 3 > rounds:
		_fail("the host had to drop the rejected client in %d of %d rounds; it should close itself" % [dropped_rounds, rounds])
		return
	print("PASS")
	get_tree().quit(0)
