extends Node
## Used by tests/net_reject.sh: join a full host again and again as the turned-away player.
##   -- --port=N --rounds=K
## Each round must end with the "Match full" message sooner than the host's notice window
## (so the client closed its own connection and the host had nothing to drop), leave the
## session inactive, and never spawn a bot. Exits 0 on success, 1 otherwise.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const ROUND_TIMEOUT_SECONDS: float = 6.0

var _main: Main = null
var _message: String = ""
var _ended: bool = false

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
	var notice: float = TuningConfig.get_default().reject_notice_seconds
	_main = MAIN_SCENE.instantiate() as Main
	get_tree().root.add_child(_main)
	await get_tree().process_frame
	_main._args.port = port
	var session: Session = _main.get_node("Session") as Session
	session.ended.connect(_on_ended)
	for round_number: int in rounds:
		_ended = false
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
		if elapsed >= notice:
			_fail("round %d: message took %.2f s, the host's notice window is %.2f s" % [round_number + 1, elapsed, notice])
			return
		if session.is_active() or _main.get_node("Bots").get_child_count() > 0:
			_fail("round %d: session still active or a bot exists" % [round_number + 1])
			return
		print("PASS round %d: Match full after %.2f s" % [round_number + 1, elapsed])
		await get_tree().create_timer(0.3).timeout
	print("PASS")
	get_tree().quit(0)
