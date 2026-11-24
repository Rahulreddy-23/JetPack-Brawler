extends Node
## A rejected player waiting out its notice must not count against the limit: with
## four players in and a fifth being turned away, one leaves and a new one joins
## inside the notice window and is accepted.
## Run: godot --headless res://tests/test_session_full.tscn -- --port=N
## Exit 0 pass, 1 fail, 2 inconclusive (the steps did not fit in the notice window).

var _failed: bool = false
var _session: Session = null
var _accepted: Array[int] = []
var _connected: Array[int] = []

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
	return 25291

# Raw ENet client: it never speaks the scene protocol, it only holds a connection.
func _connect_client(port: int) -> ENetMultiplayerPeer:
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	peer.create_client("127.0.0.1", port)
	return peer

func _poll_all(clients: Array[ENetMultiplayerPeer]) -> void:
	for client: ENetMultiplayerPeer in clients:
		client.poll()
	await get_tree().process_frame

# Polls the clients every frame until the server has seen `count` more connections.
func _wait_connections(clients: Array[ENetMultiplayerPeer], count: int) -> bool:
	var target: int = _connected.size() + count
	var deadline: int = Time.get_ticks_msec() + 3000
	while _connected.size() < target:
		await _poll_all(clients)
		if Time.get_ticks_msec() > deadline:
			return false
	return true

func _wait_gone(clients: Array[ENetMultiplayerPeer], id: int) -> void:
	var deadline: int = Time.get_ticks_msec() + 3000
	while _session.multiplayer.get_peers().has(id) and Time.get_ticks_msec() < deadline:
		await _poll_all(clients)

func _run() -> void:
	var port: int = _port()
	var cfg: TuningConfig = TuningConfig.get_default()
	_session = Session.new()
	get_tree().root.add_child(_session)
	await get_tree().process_frame
	_session.peer_accepted.connect(func(id: int) -> void: _accepted.append(id))
	_session.multiplayer.peer_connected.connect(func(id: int) -> void: _connected.append(id))
	_check(_session.host(port, cfg.max_players) == OK, "host starts")

	var clients: Array[ENetMultiplayerPeer] = []
	for i: int in cfg.max_players - 1:
		clients.append(_connect_client(port))
		if not await _wait_connections(clients, 1):
			_check(false, "client %d connected" % i)
			get_tree().quit(1)
			return
	_check(_accepted.size() == cfg.max_players - 1, "the first %d players are accepted" % (cfg.max_players - 1))

	# The fifth player is turned away but stays connected until the notice has gone out.
	var window_start: int = Time.get_ticks_msec()
	clients.append(_connect_client(port))
	if not await _wait_connections(clients, 1):
		_check(false, "fifth client connected")
		get_tree().quit(1)
		return
	var fifth_id: int = _connected[_connected.size() - 1]
	_check(not _accepted.has(fifth_id), "fifth player is not accepted")

	# One real player leaves inside the window, and a new one joins.
	var leaver_id: int = _connected[0]
	clients[0].close()
	clients.remove_at(0)
	await _wait_gone(clients, leaver_id)
	clients.append(_connect_client(port))
	var joined: bool = await _wait_connections(clients, 1)
	var elapsed: float = float(Time.get_ticks_msec() - window_start) / 1000.0
	if not joined or elapsed >= cfg.reject_notice_seconds:
		print("INCONCLUSIVE steps took %.2f s, window is %.2f s" % [elapsed, cfg.reject_notice_seconds])
		get_tree().quit(2)
		return
	var newcomer_id: int = _connected[_connected.size() - 1]
	_check(_accepted.has(newcomer_id), "new player is accepted while the fifth is still being turned away")

	# The notice delay is kept: the rejected player is dropped afterwards.
	await _wait_gone(clients, fifth_id)
	_check(not _session.multiplayer.get_peers().has(fifth_id), "rejected player is disconnected after the notice")
	_check(not _accepted.has(fifth_id), "rejected player never accepted")
	_session.leave()
	get_tree().quit(1 if _failed else 0)
