extends Node
## A host whose main thread stalls for a short while (below netfox's stall
## threshold) must still store every input tick an honest client sent. Commands
## are handled in the multiplayer poll, before NetworkTime runs its tick loop, so
## right after a hitch the host's NetworkTime.tick lags its clock while the
## client's inputs are stamped with the real time. Used by tests/net_hitch.sh,
## which starts the client:
##   godot --headless --path . res://tests/test_host_hitch.tscn -- --port=N
## The client is a normal autopilot client. This process hosts the real game
## scene, waits for the client's bot, hitches for 400, 700 and 950 ms, and counts
## the input ticks it stored for the client (the first arrival of each tick).
## The client sends one input snapshot per tick, so any tick missing between the
## first and the last one stored is a lost one. The host must also have simulated
## the client's bot on every tick it stored an input for; a tick that was stored
## but never simulated counts the same way. Exits 0 when none is lost or skipped.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_SECONDS: float = 60.0
const WAIT_FOR_CLIENT_SECONDS: float = 25.0
const SETTLE_SECONDS: float = 3.0
const RECOVER_SECONDS: float = 2.5
const HITCHES_MSEC: Array[int] = [400, 700, 950]
## Ticks around a hitch that count towards it, for the report.
const REPORT_MARGIN_TICKS: int = 5

var _main: Main = null
var _client_input: Node = null
var _stored: Dictionary = {}
## Age of each merged input tick when it was merged: the host's tick minus the input's tick.
var _ages: Dictionary = {}
var _simulated: Dictionary = {}
var _pending_hitch_msec: int = 0
var _hitch_ticks: Array[Dictionary] = []

func _ready() -> void:
	get_tree().create_timer(TIMEOUT_SECONDS).timeout.connect(_on_timeout)
	NetworkSynchronizationServer._on_input.connect(_on_input)
	NetworkRollback.after_process_tick.connect(_on_after_process_tick)
	_run()

func _on_timeout() -> void:
	print("FAIL timeout, test did not finish")
	get_tree().quit(1)

# Emitted when a merged input snapshot carried something new, i.e. the first
# time a tick of that input was stored.
func _on_input(snapshot: _Snapshot) -> void:
	if _client_input != null and snapshot.has_subject(_client_input):
		_stored[snapshot.tick] = true
		_ages[snapshot.tick] = NetworkTime.tick - snapshot.tick

func _on_after_process_tick(tick: int) -> void:
	var bot: Bot = _client_bot()
	if bot != null and bot.last_sim_tick == tick:
		_simulated[tick] = true

# The hitch runs in _process, after NetworkTime's loop for this frame: the next
# frame's poll then delivers the packets that queued up during it.
func _process(_delta: float) -> void:
	if _pending_hitch_msec > 0:
		_hitch_ticks.append({"msec": _pending_hitch_msec, "tick": NetworkTime.tick})
		OS.delay_msec(_pending_hitch_msec)
		_pending_hitch_msec = 0

func _client_bot() -> Bot:
	for bot: Bot in _main.get_node("Bots").get_children():
		if bot.peer_id > 1:
			return bot
	return null

func _run() -> void:
	InputActions.ensure_registered()
	var port: int = LaunchArgs.parse(OS.get_cmdline_user_args()).port
	# The spawner's node path must match the client's, so Main goes directly under root.
	_main = MAIN_SCENE.instantiate() as Main
	get_tree().root.add_child.call_deferred(_main)
	await get_tree().process_frame
	_main._args.port = port
	_main._on_host()
	print("LISTENING port=%d" % port)

	var waited: float = 0.0
	while _client_bot() == null:
		await get_tree().process_frame
		waited += get_process_delta_time()
		if waited > WAIT_FOR_CLIENT_SECONDS:
			print("FAIL no client joined within %d s" % int(WAIT_FOR_CLIENT_SECONDS))
			get_tree().quit(1)
			return
	_client_input = _client_bot().input
	await get_tree().create_timer(SETTLE_SECONDS).timeout

	for msec: int in HITCHES_MSEC:
		_pending_hitch_msec = msec
		await get_tree().create_timer(RECOVER_SECONDS).timeout

	var ticks: Array = _stored.keys()
	ticks.sort()
	if ticks.is_empty():
		print("FAIL the host stored no input from the client")
		get_tree().quit(1)
		return
	var first: int = ticks.front()
	var last: int = ticks.back()
	var missing: Array[int] = []
	for tick: int in range(first, last + 1):
		if not _stored.has(tick):
			missing.append(tick)
	print("client input ticks stored: %d of %d between @%d and @%d" % [ticks.size(), last - first + 1, first, last])
	# Ticks the host has not reached yet at the end cannot have been simulated.
	var skipped: Array[int] = []
	for tick: int in ticks:
		if tick < NetworkTime.tick - 1 and not _simulated.has(tick):
			skipped.append(tick)
	var failures: int = 0
	for hitch: Dictionary in _hitch_ticks:
		var from: int = (hitch["tick"] as int) - REPORT_MARGIN_TICKS
		var to: int = (hitch["tick"] as int) + NetworkTime.seconds_to_ticks(float(hitch["msec"] as int) / 1000.0) + 2 * NetworkTime.max_ticks_per_frame
		var lost: int = 0
		for tick: int in missing:
			if tick >= from and tick <= to:
				lost += 1
		var never_simulated: int = 0
		for tick: int in skipped:
			if tick >= from and tick <= to:
				never_simulated += 1
		var oldest: int = -1000
		for tick: int in _ages:
			if tick >= from and tick <= to:
				oldest = maxi(oldest, _ages[tick] as int)
		var ok: bool = lost == 0 and never_simulated == 0
		print("INPUT_AGE hitch %d ms: oldest input merged was %d ticks old (allowance %d)" % [hitch["msec"] as int, oldest, RollbackSimulationServer._get_hole_allowance()])
		failures += 0 if ok else 1
		print("%s host hitch of %d ms at @%d: %d client input ticks lost, %d stored but never simulated" % ["PASS" if ok else "FAIL", hitch["msec"] as int, hitch["tick"] as int, lost, never_simulated])
	if failures == 0 and (missing.size() > 0 or skipped.size() > 0):
		print("FAIL client input ticks lost outside the hitches: %s; stored but never simulated: %s" % [str(missing), str(skipped)])
		failures += 1
	print("%d failures" % failures)
	get_tree().quit(1 if failures > 0 else 0)
