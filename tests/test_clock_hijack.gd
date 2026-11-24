extends Node
## Only the server may set a client's clock. A peer that is not the server must
## not be able to set or disturb the host's reference clock through netfox's
## command handlers. This hosts, calls the handlers the way the command server
## does for a non-server sender (peer 2), and checks the host's clock and tick
## rate are unchanged, now and a second later. It then becomes a client that is
## waiting for the answer to ping 0, and checks that a forged set-timestamp and
## a forged pong for ping 0 from peer 2 change nothing while the server's own
## pong is used. Run:
##   godot --headless --path . res://tests/test_clock_hijack.tscn
## Exits 0 when the clock is unaffected, 1 otherwise (also on timeout).

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_SECONDS: float = 30.0
const FORGED_TIME: float = 100000.0
const FAKE_PEER: int = 2
const SERVER_PEER: int = 1
const WATCH_SECONDS: float = 1.0
## Allowed difference between clock time and real time, and in ticks per watch.
const CLOCK_TOLERANCE_SECONDS: float = 0.1
const TICK_TOLERANCE: int = 4
## Taken from TEST_PORT so that suites can run side by side (tests/run_all.sh sets it).
const DEFAULT_PORT: int = 25102

var _failures: int = 0

func _ready() -> void:
	get_tree().create_timer(TIMEOUT_SECONDS).timeout.connect(_on_timeout)
	_run()

func _port() -> int:
	var text: String = OS.get_environment("TEST_PORT")
	return text.to_int() if text.is_valid_int() else DEFAULT_PORT

func _on_timeout() -> void:
	print("FAIL timeout, test did not finish")
	get_tree().quit(1)

func _check(ok: bool, label: String) -> void:
	if ok:
		print("PASS ", label)
	else:
		_failures += 1
		print("FAIL ", label)

# Watch the host's clock for a while and compare it with real time.
func _watch(label: String) -> void:
	var clock_start: float = NetworkTimeSynchronizer.get_time()
	var tick_start: int = NetworkTime.tick
	var real_start: int = Time.get_ticks_msec()
	await get_tree().create_timer(WATCH_SECONDS).timeout
	var real: float = float(Time.get_ticks_msec() - real_start) / 1000.0
	var clock: float = NetworkTimeSynchronizer.get_time() - clock_start
	var ticks: int = NetworkTime.tick - tick_start
	var expected_ticks: int = roundi(real * float(NetworkTime.tickrate))
	_check(absf(clock - real) <= CLOCK_TOLERANCE_SECONDS, "%s: clock advanced %.3f s in %.3f s of real time" % [label, clock, real])
	_check(absi(ticks - expected_ticks) <= TICK_TOLERANCE, "%s: %d ticks ran, expected about %d" % [label, ticks, expected_ticks])

# A client with one ping in flight. The forged answer carries a timestamp far in
# the future; if it were used, the clock discipline would panic and jump to it.
func _client_case(main: Main) -> void:
	main._on_leave()
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	peer.create_client("127.0.0.1", _port() + 1)
	multiplayer.multiplayer_peer = peer
	var sync: _NetworkTimeSynchronizer = NetworkTimeSynchronizer
	sync._sample_buffer = _RingBuffer.new(sync.sync_samples)
	var sample: NetworkClockSample = NetworkClockSample.new()
	sample.ping_sent = sync.get_time()
	sync._awaiting_samples[0] = sample
	var before: float = sync.get_time()

	sync._handle_pong(FAKE_PEER, var_to_bytes([0, FORGED_TIME, FORGED_TIME]))
	_check(not multiplayer.is_server(), "client case: this peer is a client")
	sync._handle_set_timestamp(FAKE_PEER, var_to_bytes(FORGED_TIME))
	_check(absf(sync.get_time() - before) < CLOCK_TOLERANCE_SECONDS, "a forged set-timestamp from peer %d does not move the client clock" % FAKE_PEER)
	_check(absf(sync.get_time() - before) < CLOCK_TOLERANCE_SECONDS, "a forged pong from peer %d does not move the client clock" % FAKE_PEER)
	_check(sync._awaiting_samples.has(0), "a forged pong from peer %d does not use up the sample the client waits for" % FAKE_PEER)

	sync._handle_pong(SERVER_PEER, var_to_bytes([0, sync.get_time(), sync.get_time()]))
	_check(not sync._awaiting_samples.has(0), "control: the server's pong for the same ping is used")
	_check(absf(sync.get_time() - before) < CLOCK_TOLERANCE_SECONDS, "control: the server's pong leaves the clock where it was")

func _run() -> void:
	var main: Main = MAIN_SCENE.instantiate() as Main
	add_child(main)
	main._args.port = _port()
	main._on_host()
	await get_tree().create_timer(1.0).timeout
	await _watch("before")

	var before: float = NetworkTimeSynchronizer.get_time()
	NetworkTimeSynchronizer._handle_set_timestamp(FAKE_PEER, var_to_bytes(FORGED_TIME))
	NetworkTimeSynchronizer._handle_pong(FAKE_PEER, var_to_bytes([0, FORGED_TIME, FORGED_TIME]))
	_check(absf(NetworkTimeSynchronizer.get_time() - before) < CLOCK_TOLERANCE_SECONDS, "a forged set-timestamp from peer %d does not move the host clock" % FAKE_PEER)
	await _watch("after forged messages")
	await _watch("a second later")
	await _client_case(main)

	print("%d failures" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)
