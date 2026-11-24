extends Node
## With diff states on, every subject a host sends state for must get a full state
## at least once per full_state_interval ticks, so that a client that lost a diff
## is repaired. This hosts the real game scene with diff states switched on in
## this process (the project setting is not touched), records every full state the
## host writes for the rollback state of each bot, and checks the gaps between
## them for the host's own bot and for a client's bot, whose input arrives late and
## which is therefore often missing from a tick's first pass. Used by
## tests/net_diffs.sh, which starts the client:
##   godot --headless --path . res://tests/test_host_diffs.tscn -- --host --port=N --quit-after=S
## Exits 0 when no gap is longer than the interval plus the slack below. The client's
## own positions are not compared: with diff states on, a diff packet lost on the way
## leaves the client's state wrong until the next full state, which a loopback run
## sometimes shows.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_SECONDS: float = 60.0
const WAIT_FOR_CLIENT_SECONDS: float = 25.0
const PLAY_SECONDS: float = 7.0
## A subject can be missing from the pass at which its interval ends (a client
## bot with no input yet); it gets its full state at the next pass it is in.
const SLACK_TICKS: int = 4

## Writes like the real dense serializer and notes which subjects of the rollback
## state it was asked to write, and for which tick.
class Recorder extends _DenseSnapshotSerializer:
	var rows: Array[Dictionary] = []
	var watched: _PropertyPool = null

	func write_for(peer: int, snapshot: _Snapshot, properties: _PropertyPool, filter: Callable = _default_filter) -> Array[PackedByteArray]:
		if properties == watched:
			for subject: Object in properties.get_subjects():
				if filter.call(subject) and snapshot.is_auth(subject):
					rows.append({"peer": peer, "subject": subject, "tick": snapshot.tick})
		return super.write_for(peer, snapshot, properties, filter)

var _main: Main = null
var _recorder: Recorder = null
var _failures: int = 0

func _ready() -> void:
	get_tree().create_timer(TIMEOUT_SECONDS).timeout.connect(_on_timeout)
	_run()

func _on_timeout() -> void:
	print("FAIL timeout, test did not finish")
	get_tree().quit(1)

func _check(ok: bool, label: String) -> void:
	if ok:
		print("PASS ", label)
	else:
		_failures += 1
		print("FAIL ", label)

func _client_bot() -> Bot:
	for bot: Bot in _main.get_node("Bots").get_children():
		if bot.peer_id > 1:
			return bot
	return null

# Ticks at which a full state was written for this bot, in order, without repeats.
func _full_ticks(bot: Bot) -> Array[int]:
	var result: Array[int] = []
	for row: Dictionary in _recorder.rows:
		if row["subject"] == bot and not result.has(row["tick"] as int):
			result.append(row["tick"] as int)
	result.sort()
	return result

func _check_gaps(bot: Bot, label: String, first_tick: int, last_tick: int) -> void:
	var ticks: Array[int] = _full_ticks(bot)
	var interval: int = NetworkSynchronizationServer._rb_full_interval
	var worst: int = 0
	var previous: int = first_tick
	for tick: int in ticks:
		if tick < first_tick:
			continue
		worst = maxi(worst, tick - previous)
		previous = tick
	worst = maxi(worst, last_tick - previous)
	_check(not ticks.is_empty() and worst <= interval + SLACK_TICKS, "%s: %d full states in %d ticks, longest gap %d (interval %d, slack %d)" % [label, ticks.size(), last_tick - first_tick, worst, interval, SLACK_TICKS])

func _run() -> void:
	NetworkSynchronizationServer._rb_enable_diffs = true
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
	var host_bot: Bot = null
	for bot: Bot in _main.get_node("Bots").get_children():
		if bot.peer_id == multiplayer.get_unique_id():
			host_bot = bot
	# Give both bots their first full state, then watch from there.
	await get_tree().create_timer(1.0).timeout
	var first_tick: int = NetworkTime.tick
	await get_tree().create_timer(PLAY_SECONDS).timeout
	var last_tick: int = NetworkTime.tick - 2

	_check_gaps(host_bot, "host bot", first_tick, last_tick)
	_check_gaps(client_bot, "client bot", first_tick, last_tick)
	print("%d failures" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)
