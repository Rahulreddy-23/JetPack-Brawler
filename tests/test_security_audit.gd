extends Node
## Regression tests for security, crash, and logic fixes audited on geminiceo.
## Run:
##   godot --headless --path . res://tests/test_security_audit.tscn
## Exits 0 when every check passes, 1 otherwise.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_SECONDS: float = 30.0
const PORT: int = 25110

var _failures: int = 0
var _checks: int = 0

func _ready() -> void:
	get_tree().create_timer(TIMEOUT_SECONDS).timeout.connect(_on_timeout)
	_run()

func _on_timeout() -> void:
	print("FAIL timeout, security audit test did not finish")
	get_tree().quit(1)

func _check(ok: bool, label: String) -> void:
	_checks += 1
	if ok:
		print("PASS ", label)
	else:
		_failures += 1
		print("FAIL ", label)

func _run() -> void:
	InputActions.ensure_registered()
	var main: Main = MAIN_SCENE.instantiate() as Main
	add_child(main)
	main._args.port = PORT
	main._on_host()
	var bots: Node = main.get_node("Bots")
	while bots.get_child_count() == 0:
		await get_tree().process_frame
	var bot: Bot = bots.get_child(0) as Bot
	await get_tree().create_timer(0.5).timeout

	# 1. Host rejects spoofed _handle_set_timestamp and malformed _handle_pong.
	var clock_before: float = NetworkTimeSynchronizer.get_time()
	NetworkTimeSynchronizer._handle_set_timestamp(2, var_to_bytes(NAN))
	NetworkTimeSynchronizer._handle_set_timestamp(2, var_to_bytes(1.0e9))
	NetworkTimeSynchronizer._handle_pong(2, PackedByteArray())
	NetworkTimeSynchronizer._handle_pong(2, var_to_bytes(42))
	NetworkTimeSynchronizer._handle_pong(2, var_to_bytes([]))
	NetworkTimeSynchronizer._handle_ping(2, PackedByteArray())
	NetworkTimeSynchronizer._handle_ping(2, var_to_bytes("bad"))
	var clock_after: float = NetworkTimeSynchronizer.get_time()
	_check(is_finite(clock_after) and absf(clock_after - clock_before) < 2.0, "host clock survives spoofed set_timestamp and malformed pong/ping")

	# 2. Boundary future tick (+history_limit = +64) is rejected and does not wipe history.
	var tick_now: int = NetworkTime.tick
	var edge_snap: _Snapshot = _Snapshot.new(tick_now + NetworkRollback.history_limit)
	edge_snap.set_property(bot.input, ^":move", Vector2.RIGHT)
	edge_snap.set_auth(bot.input, true)
	var merged_edge: bool = NetworkHistoryServer._merge_rollback_input(edge_snap)
	_check(not merged_edge, "tick + history_limit (+64) snapshot is rejected")

	# 3. Snapshot.sanitize also clears _auth_subjects for unauthorized nodes.
	var spoof_snap: _Snapshot = _Snapshot.new(tick_now)
	spoof_snap.set_property(bot, ^":global_position", Vector2(9999.0, 9999.0))
	spoof_snap.set_auth(bot, true)
	spoof_snap.sanitize(2)
	_check(spoof_snap.is_empty() and not spoof_snap.is_auth(bot), "sanitize clears both data and auth flag")

	# 4. Crafted sparse diff packet with out-of-range bit indices does not crash.
	var sparse_buf: StreamPeerBuffer = StreamPeerBuffer.new()
	sparse_buf.put_u32(tick_now)
	NetworkSchemas._netref().encode(_NetworkIdentityReference.of_full_name(str(bot.get_path())), sparse_buf)
	NetworkSchemas.varuint().encode(0, sparse_buf)
	# Set bits 0..20 (exceeds Bot's 15 properties) via continuation bytes.
	sparse_buf.put_u8(0xFF)
	sparse_buf.put_u8(0xFF)
	sparse_buf.put_u8(0x7F)
	NetworkSynchronizationServer._handle_diff_state(2, sparse_buf.data_array)
	_check(true, "crafted out-of-range diff state packet survived without crash")

	# 5. Conflicting peer network identifier does not assert-crash debug host.
	var id_buf: StreamPeerBuffer = StreamPeerBuffer.new()
	id_buf.put_utf8_string(str(bot.get_path()))
	NetworkSchemas.varuint().encode(10, id_buf)
	NetworkIdentityServer._handle_ids(2, id_buf.data_array)
	var id_buf2: StreamPeerBuffer = StreamPeerBuffer.new()
	id_buf2.put_utf8_string(str(bot.get_path()))
	NetworkSchemas.varuint().encode(11, id_buf2)
	NetworkIdentityServer._handle_ids(2, id_buf2.data_array)
	_check(true, "conflicting _handle_ids from remote peer survived without assert")

	# 6. Zero-filled redundant input packet is bounded and does not spin.
	var zero_flood: PackedByteArray = PackedByteArray()
	zero_flood.resize(2048)
	zero_flood.fill(0)
	NetworkSynchronizationServer._handle_input(2, zero_flood)
	_check(true, "zero-filled redundant input packet handled safely")

	# 7. Rapid host leave + re-host does not lose Bot1 from BotSpawner._bots.
	main._on_leave()
	main._on_host()
	await get_tree().process_frame
	await get_tree().process_frame
	var spawner: BotSpawner = main.get_node("BotSpawner") as BotSpawner
	_check(spawner.get_bots().has(1) and is_instance_valid(spawner.get_bots()[1]), "rapid leave and re-host preserves host bot in spawner")

	# 8. Invalid IP address is rejected before ENet DNS lookup.
	main._on_leave()
	main._on_join("not-an-ip-address")
	var session: Session = main.get_node("Session") as Session
	_check(not session.is_active(), "invalid IP address rejected cleanly")

	# 9. TouchControls drag from non-active finger does not clobber keyboard action.
	var touch: TouchControls = main.get_node("TouchLayer/Touch") as TouchControls
	touch.visible = true
	touch.use_mouse = true
	Input.action_press(InputActions.MOVE_RIGHT)
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = Vector2(100.0, 100.0)
	touch._unhandled_input(motion)
	_check(Input.is_action_pressed(InputActions.MOVE_RIGHT), "idle mouse motion with touch-ui does not cancel keyboard movement")
	Input.action_release(InputActions.MOVE_RIGHT)

	print("%d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)
