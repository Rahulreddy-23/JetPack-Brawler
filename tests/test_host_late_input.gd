extends Node
## One client input arriving late, on demand. The simulator holds the packets the client
## sends in one short window (--sim-hold-ms, --sim-hold-at-ms, --sim-hold-window-ms), so the
## packets after the window overtake them. Every input packet carries the last
## input_redundancy ticks, so one late packet changes nothing; a window of that many packets
## leaves a hole of one tick: the host has the client's input for the ticks after it and
## not for the tick itself. This hosts the real game, records every full state the host writes
## for the client's bot and the host tick at which each client input first arrived, and reports:
##   - the ticks whose first state sent differs from the last one sent (stale states on the
##     wire, each one tick of movement behind) and how far off they are;
##   - the tick the hole is at, and how many ticks after its tick its input arrived,
##     against how many ticks after theirs the other inputs arrive.
## Exits 1 when any state was sent for a tick and later replaced by a different one (the
## fault; the whole state is compared), or when the client's bot was first simulated after its
## first input tick, or when the hole's input arrived less than 3 ticks inside the input
## allowance (a test must not sit on the boundary), 0 when none of these. With --expect-refused
## the hold is meant to be past the allowance: the hole's input must be refused (never stored),
## the bot must not have been simulated on those ticks, and still no state is replaced.
## With --expect-pause the client was stopped for about a second (tests/net_late_input.sh,
## PAUSE_MS): its inputs are missing for all those ticks; the bot must not have been
## simulated on any of them and its state must not have moved across them.
## With --expect-silent every input of the client is later than the allowance (LATENCY_MS):
## the host must refuse them all, never simulate the bot, and count the refusals for the peer.
## Used by tests/net_late_input.sh, which starts the client:
##   godot --headless --path . res://tests/test_host_late_input.tscn -- --host --port=N --trace
##     --quit-after=S --sim-hold-ms=N --sim-hold-at-ms=N --sim-hold-window-ms=N [--expect-refused | --expect-pause | --expect-silent] [--tick-log]

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_SECONDS: float = 60.0
const WAIT_FOR_CLIENT_SECONDS: float = 25.0
const PLAY_SECONDS: float = 9.0
## Positions closer than this are the same state.
const SAME_PIXELS: float = 0.001
## A straggler must arrive at least this many ticks inside the input allowance.
const BOUNDARY_MARGIN_TICKS: int = 3
## The join is sampled for the refusal count while fewer input ticks than this were stored.
const JOIN_SAMPLE_TICKS: int = 60
## A pause of the client leaves at least this many ticks without input (1 s is 30 at 30 ticks per second).
const MIN_PAUSE_TICKS: int = 20

## Writes like the real dense serializer and notes the position of every bot it is asked to
## write, with the tick it is for and the host tick at which it was written.
class Recorder extends _DenseSnapshotSerializer:
	var rows: Array[Dictionary] = []
	var watched: _PropertyPool = null

	func write_for(peer: int, snapshot: _Snapshot, properties: _PropertyPool, filter: Callable = _default_filter) -> Array[PackedByteArray]:
		if properties == watched:
			for subject: Object in properties.get_subjects():
				if not (filter.call(subject) and snapshot.is_auth(subject)):
					continue
				var row: Dictionary = {"bot": subject, "tick": snapshot.tick, "now": NetworkTime.tick, "pos": Vector2.ZERO, "signature": str(snapshot._data[subject])}
				for property: NodePath in snapshot.get_subject_properties(subject):
					if str(property).ends_with("global_position"):
						row["pos"] = snapshot.get_property(subject, property)
				rows.append(row)
		return super.write_for(peer, snapshot, properties, filter)

var _main: Main = null
var _recorder: Recorder = null
var _client_input: Node = null
## Client input tick -> host tick at which it first arrived.
var _arrived: Dictionary = {}
var _first_simulated_tick: int = -1
## The most input snapshots of the client refused in the second before a sample, over the first
## ticks of the session (the join): inputs of the first ticks that arrived after later ones.
var _join_refused: int = 0
## Ticks the client's bot was simulated on, as it happened.
var _simulated: Dictionary = {}
## Every pass of the client's bot over a tick, for --tick-log.
var _passes: Array[Dictionary] = []

func _ready() -> void:
	get_tree().create_timer(TIMEOUT_SECONDS).timeout.connect(_on_timeout)
	NetworkSynchronizationServer._on_input.connect(_on_input)
	NetworkRollback.after_process_tick.connect(_on_after_process_tick)
	_run()

func _on_timeout() -> void:
	print("FAIL timeout, test did not finish")
	get_tree().quit(1)

func _on_input(snapshot: _Snapshot) -> void:
	if _client_input != null and snapshot.has_subject(_client_input) and not _arrived.has(snapshot.tick):
		_arrived[snapshot.tick] = NetworkTime.tick

# The first tick the client's bot was simulated on, as it happened (not in the final history).
func _on_after_process_tick(tick: int) -> void:
	var bot: Bot = _client_bot()
	if bot != null:
		_passes.append({"now": NetworkTime.tick, "tick": tick, "input": _arrived.has(tick), "sim": bot.last_sim_tick == tick, "x": bot.global_position.x})
	if bot != null and bot.last_sim_tick == tick:
		_simulated[tick] = true
		if _first_simulated_tick < 0:
			_first_simulated_tick = tick

# Samples the refusal count during the join: input for a tick before the first accepted input,
# arriving after later input, is refused (netfox patch 15); the owner's client, which simulated
# those ticks, then shows its bot wrong for them, once.
func _process(_delta: float) -> void:
	if _client_input != null and _arrived.size() < JOIN_SAMPLE_TICKS:
		_join_refused = maxi(_join_refused, NetworkHistoryServer.get_recent_refused_input_count(_client_input.get_multiplayer_authority()))

func _client_bot() -> Bot:
	for bot: Bot in _main.get_node("Bots").get_children():
		if bot.peer_id > 1:
			return bot
	return null

func _run() -> void:
	_recorder = Recorder.new(NetworkSynchronizationServer._schemas, NetworkIdentityServer)
	_recorder.max_packet_size = NetworkSynchronizationServer._max_packet_size
	_recorder.watched = NetworkSynchronizationServer._rb_owned_state_properties
	NetworkSynchronizationServer._dense_serializer = _recorder

	# The spawner's node path must match the client's, so Main goes directly under root.
	_main = MAIN_SCENE.instantiate() as Main
	get_tree().root.add_child.call_deferred(_main)

	var waited: float = 0.0
	while _client_bot() == null:
		await get_tree().process_frame
		waited += get_process_delta_time()
		if waited > WAIT_FOR_CLIENT_SECONDS:
			print("FAIL no client joined within %d s" % int(WAIT_FOR_CLIENT_SECONDS))
			get_tree().quit(1)
			return
	var client_bot: Bot = _client_bot()
	_client_input = client_bot.input
	print("CLIENT_JOINED")
	await get_tree().create_timer(PLAY_SECONDS).timeout

	var failed: bool = _report(client_bot)
	# Main prints the trace the caller compares, then quits; the exit code is set after.
	_main._finish()
	get_tree().quit(1 if failed else 0)

# Every input of the client was refused as later than the allowance.
func _report_silent(client_bot: Bot) -> bool:
	var peer: int = _client_input.get_multiplayer_authority()
	var count: int = NetworkHistoryServer.get_recent_refused_input_count(peer)
	var states_sent: int = 0
	for row: Dictionary in _recorder.rows:
		states_sent += 1 if row["bot"] == client_bot else 0
	print("SILENT peer=%d inputs_stored=%d ticks_simulated=%d refused_in_last_second=%d states_sent_for_the_bot=%d" % [peer, _arrived.size(), _simulated.size(), count, states_sent])
	var failed: bool = false
	if not _arrived.is_empty():
		print("FAIL %d inputs were stored: the latency did not pass the allowance" % _arrived.size())
		failed = true
	if not _simulated.is_empty():
		print("FAIL the host simulated the bot on %d ticks without input" % _simulated.size())
		failed = true
	if count <= 0:
		print("FAIL the refusals were not counted for the peer")
		failed = true
	if not failed:
		print("PASS every input was refused, the bot was never simulated and the refusals are counted")
	return failed

# Prints the numbers; returns true when a stale state was sent.
func _report(client_bot: Bot) -> bool:
	if OS.get_cmdline_user_args().has("--expect-silent"):
		return _report_silent(client_bot)
	var sends: Dictionary = {}
	var per_subject: Dictionary = {}
	for row: Dictionary in _recorder.rows:
		var subject_sends: Dictionary = per_subject.get(row["bot"], {}) as Dictionary
		var at_tick: Array = subject_sends.get(row["tick"], []) as Array
		at_tick.append(row)
		subject_sends[row["tick"]] = at_tick
		per_subject[row["bot"]] = subject_sends
		if row["bot"] == client_bot:
			sends[row["tick"]] = at_tick
	# Every subject of the rollback state, bots and world objects: ticks whose first state sent
	# differs from the last one sent, as seen by any peer.
	for subject: Object in per_subject:
		var changed: int = 0
		var subject_sends: Dictionary = per_subject[subject]
		for tick: int in subject_sends:
			var at_tick: Array = subject_sends[tick]
			if (at_tick[0] as Dictionary)["signature"] != (at_tick[at_tick.size() - 1] as Dictionary)["signature"]:
				changed += 1
			if subject is Bot:
				var final_position: Vector2 = (at_tick[at_tick.size() - 1] as Dictionary)["pos"]
				print("TRUTH peer=%d tick=%d x=%.3f y=%.3f" % [(subject as Bot).peer_id, tick, final_position.x, final_position.y])
		print("SUBJECT_REPLACED name=%s peer=%d ticks_sent=%d first_state_replaced_on=%d" % [(subject as Node).name, (subject as Bot).peer_id if subject is Bot else -1, subject_sends.size(), changed])
	var stale: Array[int] = []
	var worst: float = 0.0
	var first_now: int = -1
	var corrected_now: int = -1
	var ticks: Array = sends.keys()
	ticks.sort()
	for tick: int in ticks:
		var list: Array = sends[tick]
		var first: Vector2 = (list[0] as Dictionary)["pos"]
		var last: Vector2 = (list[list.size() - 1] as Dictionary)["pos"]
		# The whole state counts, not only the position: a filled-in input can change the aim
		# or the fuel and leave the position alone.
		if (list[0] as Dictionary)["signature"] != (list[list.size() - 1] as Dictionary)["signature"]:
			stale.append(tick)
			worst = maxf(worst, first.distance_to(last))
			if first_now < 0:
				first_now = (list[0] as Dictionary)["now"] as int
			corrected_now = maxi(corrected_now, (list[list.size() - 1] as Dictionary)["now"] as int)

	# Arrival of each client input, in host ticks after its own tick, and the hole: the tick whose
	# input arrived the most host ticks after the input of the tick after it.
	var lags: Array[int] = []
	var hole_tick: int = -1
	var hole_after: int = 0
	var arrived_ticks: Array = _arrived.keys()
	arrived_ticks.sort()
	for tick: int in arrived_ticks:
		lags.append((_arrived[tick] as int) - tick)
		if _arrived.has(tick + 1) and (_arrived[tick] as int) - (_arrived[tick + 1] as int) > hole_after:
			hole_after = (_arrived[tick] as int) - (_arrived[tick + 1] as int)
			hole_tick = tick
	var sorted_lags: Array[int] = lags.duplicate()
	sorted_lags.sort()
	var typical: int = sorted_lags[sorted_lags.size() / 2] if not sorted_lags.is_empty() else -1
	var worst_lag: int = sorted_lags.back() if not sorted_lags.is_empty() else -1
	print("INPUT_LAG_MAX max=%d host ticks after its own tick, over the %d inputs that were stored (refused inputs never reach this number: see REFUSED)" % [worst_lag, lags.size()])
	print("INPUT_LAG typical=%d host ticks after its own tick; hole_tick=%d arrived %d host ticks after the input of tick %d (at host tick %d)" % [typical, hole_tick, hole_after, hole_tick + 1, _arrived.get(hole_tick, -1)])
	print("STALE_STATES count=%d first_tick=%d max_error_px=%.3f first_sent_at_host_tick=%d last_corrected_at_host_tick=%d ticks=%s" % [stale.size(), stale[0] if not stale.is_empty() else -1, worst, first_now, corrected_now, str(stale)])
	# Ticks between the first and the last input that never arrived: refused as later than the allowance.
	var allowance: int = RollbackSimulationServer._get_hole_allowance()
	var missing: Array[int] = []
	if not arrived_ticks.is_empty():
		for tick: int in range(arrived_ticks[0] as int, (arrived_ticks[arrived_ticks.size() - 1] as int) + 1):
			if not _arrived.has(tick):
				missing.append(tick)
	var simulated_missing: Array[int] = []
	for tick: int in missing:
		if _simulated.has(tick):
			simulated_missing.append(tick)
	print("REFUSED missing_ticks=%s simulated_by_host=%s allowance=%d redundancy=%d" % [str(missing), str(simulated_missing), allowance, NetworkRollback.input_redundancy])
	var hold: int = LaunchArgs.parse(OS.get_cmdline_user_args()).sim_hold_ms
	if OS.get_cmdline_user_args().has("--tick-log"):
		var focus: int = hole_tick if hole_tick >= 0 else (missing[0] if not missing.is_empty() else -1)
		for pass_row: Dictionary in _passes:
			var row_tick: int = pass_row["tick"] as int
			# A pause is looked at where it starts and where it ends.
			var in_window: bool = focus >= 0 and row_tick >= focus - 2 and row_tick <= focus + (allowance + 3 if missing.size() <= allowance else 3)
			if missing.size() > allowance:
				in_window = in_window or (row_tick >= missing[missing.size() - 1] - 2 and row_tick <= missing[missing.size() - 1] + allowance + 3)
			if in_window:
				print("TICKLOG host_tick=%d tick=%d input_here=%d simulated=%d x=%.2f" % [pass_row["now"] as int, pass_row["tick"] as int, 1 if pass_row["input"] else 0, 1 if pass_row["sim"] else 0, pass_row["x"] as float])
	var failed: bool = false
	if OS.get_cmdline_user_args().has("--expect-pause"):
		var moved: Array[int] = []
		for tick: int in missing:
			if sends.has(tick) and sends.has(tick + 1):
				var before: Vector2 = ((sends[tick] as Array).back() as Dictionary)["pos"]
				var after: Vector2 = ((sends[tick + 1] as Array).back() as Dictionary)["pos"]
				if before.distance_to(after) > SAME_PIXELS:
					moved.append(tick)
		print("PAUSE missing_ticks=%d first=%d last=%d bot_moved_across=%s" % [missing.size(), missing[0] if not missing.is_empty() else -1, missing[missing.size() - 1] if not missing.is_empty() else -1, str(moved)])
		if missing.size() < MIN_PAUSE_TICKS:
			print("FAIL the pause left only %d ticks without input (at least %d expected)" % [missing.size(), MIN_PAUSE_TICKS])
			failed = true
		if not simulated_missing.is_empty():
			print("FAIL the host simulated the client's bot on ticks it had no input for: %s" % str(simulated_missing))
			failed = true
		if not moved.is_empty():
			print("FAIL the client's bot moved across ticks it had no input for: %s" % str(moved))
			failed = true
	elif OS.get_cmdline_user_args().has("--expect-refused"):
		if missing.is_empty():
			print("FAIL the hold was meant to pass the allowance of %d ticks but every input arrived" % allowance)
			failed = true
		if not simulated_missing.is_empty():
			print("FAIL the host simulated the client's bot on ticks it had no input for: %s" % str(simulated_missing))
			failed = true
	else:
		if hold > 0 and hole_tick < 0:
			print("FAIL the hold made no hole in the input (the window held fewer than input_redundancy packets); nothing was tested")
			failed = true
		if not missing.is_empty():
			print("FAIL inputs never arrived (refused as later than the allowance of %d ticks): %s" % [allowance, str(missing)])
			failed = true
		if hole_tick >= 0:
			var lateness: int = (_arrived[hole_tick] as int) - hole_tick
			print("HOLE_LATENESS hole_tick=%d arrived_at_host_tick=%d lateness=%d allowance=%d margin=%d" % [hole_tick, _arrived[hole_tick] as int, lateness, allowance, allowance - lateness])
			if allowance - lateness < BOUNDARY_MARGIN_TICKS:
				print("FAIL the straggler arrived %d ticks after its tick, within %d of the allowance of %d: move the hold" % [lateness, BOUNDARY_MARGIN_TICKS, allowance])
				failed = true
	if failed:
		return true
	# Join start: the bot must be simulated on its first input tick, not some ticks after it.
	var first_input: int = arrived_ticks[0] if not arrived_ticks.is_empty() else -1
	print("JOIN_START first_input_tick=%d first_simulated_tick=%d" % [first_input, _first_simulated_tick])
	if _join_refused > 0:
		print("JOIN_REORDERED refused=%d first_input_tick=%d" % [_join_refused, first_input])
	var late_start: bool = _first_simulated_tick < 0 or _first_simulated_tick > first_input
	if late_start:
		print("FAIL the client's bot was first simulated on tick %d, after its first input tick %d" % [_first_simulated_tick, first_input])
	if stale.is_empty():
		print("PASS no state was sent for a tick and later replaced by a different one")
		return late_start
	print("FAIL %d states were sent for a tick and later replaced by a different one (up to %.2f px apart)" % [stale.size(), worst])
	return true
