extends Node
## An input that is lost for good: every packet that carries the input of one tick is dropped
## (--sim-drop-ms), so the host never gets it. The host must not hold the client's bot back
## for ever: once the host's tick is more than the input allowance past the hole it stops
## waiting, the tick stands as one where the bot did not act, and the bot goes on from the
## inputs after it. This hosts the real game and watches the
## client's bot on the host, tick by tick as the host lives them: the longest run of ticks on
## which its position did not change around the hole, and the ticks whose input never
## arrived. The bot is moving at that time (the autopilot's jetpack segment), so a held-back
## bot shows as a run of identical positions. Exits 0 when the run is at most the input
## allowance + the number of lost inputs + SLACK_TICKS, 1 otherwise (a bot that never moves again gives a run of
## about a hundred). Used by tests/net_lost_input.sh, which starts the client and then compares
## the settled ticks of host and client:
##   godot --headless --path . res://tests/test_host_lost_input.tscn -- --host --port=N --trace
##     --quit-after=S --sim-drop-ms=N --sim-hold-at-ms=N

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_SECONDS: float = 60.0
const WAIT_FOR_CLIENT_SECONDS: float = 25.0
const PLAY_SECONDS: float = 9.0
## The hole expires when the host's tick is past the allowance, and the loop after it
## simulates the next tick: one tick for the expiry and one for that loop.
const SLACK_TICKS: int = 2
## Ticks around the hole that are looked at (the watch ends before the autopilot lands and stands still).
const WATCH_BEFORE: int = 3
## Past the expiry (the allowance after the hole), with room to see the bot move again.
const WATCH_AFTER_EXPIRY: int = 8

var _main: Main = null
var _client_input: Node = null
var _arrived: Dictionary = {}
var _positions: Dictionary = {}
var _last_tick: int = -1

func _ready() -> void:
	get_tree().create_timer(TIMEOUT_SECONDS).timeout.connect(_on_timeout)
	NetworkSynchronizationServer._on_input.connect(_on_input)
	_run()

func _on_timeout() -> void:
	print("FAIL timeout, test did not finish")
	get_tree().quit(1)

func _on_input(snapshot: _Snapshot) -> void:
	if _client_input != null and snapshot.has_subject(_client_input) and not _arrived.has(snapshot.tick):
		_arrived[snapshot.tick] = NetworkTime.tick

func _client_bot() -> Bot:
	if _main == null:
		return null
	for bot: Bot in _main.get_node("Bots").get_children():
		if bot.peer_id > 1:
			return bot
	return null

# The client's bot as it is shown on the host after each tick loop.
func _process(_delta: float) -> void:
	var bot: Bot = _client_bot()
	if bot != null and NetworkTime.tick != _last_tick:
		_last_tick = NetworkTime.tick
		_positions[_last_tick] = bot.global_position

func _run() -> void:
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
	_client_input = _client_bot().input
	await get_tree().create_timer(PLAY_SECONDS).timeout

	var failed: bool = _report()
	_main._finish()
	get_tree().quit(1 if failed else 0)

func _report() -> bool:
	var arrived_ticks: Array = _arrived.keys()
	arrived_ticks.sort()
	var lost: Array[int] = []
	for tick: int in range(arrived_ticks[0], arrived_ticks[-1] + 1):
		if not _arrived.has(tick):
			lost.append(tick)
	print("LOST_INPUTS ticks=%s" % str(lost))
	if lost.is_empty():
		print("FAIL no input was lost, the drop window did not hit the input stream")
		return true

	# The longest run of ticks without a change of position, from just before the hole.
	var first: int = lost[0] - WATCH_BEFORE
	var last: int = lost[lost.size() - 1] + RollbackSimulationServer._get_hole_allowance() + WATCH_AFTER_EXPIRY
	var longest: int = 0
	var run: int = 0
	var run_start: int = -1
	var longest_start: int = -1
	for tick: int in range(first, last + 1):
		if _positions.has(tick) and _positions.has(tick - 1) and (_positions[tick] as Vector2).distance_to(_positions[tick - 1]) < 0.001:
			run += 1
			if run == 1:
				run_start = tick
			if run > longest:
				longest = run
				longest_start = run_start
		else:
			run = 0
	var allowed: int = RollbackSimulationServer._get_hole_allowance() + lost.size() + SLACK_TICKS
	print("HELD_BACK longest_run_of_ticks_without_movement=%d starting_at=%d allowed=%d (input allowance %d, %d lost inputs)" % [longest, longest_start, allowed, RollbackSimulationServer._get_hole_allowance(), lost.size()])
	if longest > allowed:
		print("FAIL the client's bot stood still on the host for %d ticks, more than %d" % [longest, allowed])
		return true
	print("PASS the client's bot was held back for %d ticks at most and then went on" % longest)
	return false
