extends Node
## Used by tests/net_relay.sh: a client must not be able to send an RPC to another client.
##   -- --role=host --port=N                  : host, print every ping that arrives
##   -- --role=target --port=N                : join, print its own id, print every ping that arrives
##   -- --role=sender --port=N --target=ID    : join, ping the host (control) and the target client
## Pings are printed as "GOT <text> from <id>". Runs for --seconds, then quits.

var _role: String = "host"
var _port: int = 0
var _target: int = 0
var _seconds: float = 10.0
var _session: Session = null

func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var value: String = arg.get_slice("=", 1)
		match arg.get_slice("=", 0):
			"--role":
				_role = value
			"--port":
				_port = value.to_int()
			"--target":
				_target = value.to_int()
			"--seconds":
				_seconds = value.to_float()
	_session = Session.new()
	add_child(_session)
	get_tree().create_timer(_seconds).timeout.connect(get_tree().quit)
	_run.call_deferred()

@rpc("any_peer", "call_remote", "reliable")
func ping(text: String) -> void:
	print("GOT %s from %d" % [text, multiplayer.get_remote_sender_id()])

func _run() -> void:
	if _role == "host":
		print("LISTENING" if _session.host(_port, TuningConfig.get_default().max_players) == OK else "HOST FAILED")
		return
	if _session.join("127.0.0.1", _port) != OK:
		print("JOIN FAILED")
		return
	await multiplayer.connected_to_server
	print("ID %d" % multiplayer.get_unique_id())
	if _role == "sender":
		await get_tree().create_timer(1.0).timeout
		ping.rpc_id(1, "control")
		ping.rpc_id(_target, "direct")
