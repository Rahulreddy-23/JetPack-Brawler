class_name SmokeProbe
extends Node
## Test support for the two-process network smoke test (debug builds only).
## For every bot and every simulated tick it records the resulting position,
## the input values the simulation used, whether the tick was really simulated
## (not just carried over), and whether the state it started from was received
## from the server. A later re-simulation of the same tick overwrites the row,
## except that a row that started from a received server state is not replaced
## by one that chained from the client's own predictions. The memory used is
## bounded.
##
## It also records each bot's health, hit count and knockout serial for the tick, counts
## how many times the host processed each tick in which a bot fired (so a test can assert
## that a fire tick was re-simulated), and measures the connection's bandwidth.

## Rows kept per bot; older ticks are dropped.
const MAX_ROWS_PER_BOT: int = 4096

## peer id -> {tick: row Dictionary}
var _rows: Dictionary = {}
## peer id -> data captured when the tick was prepared
var _prepared: Dictionary = {}
var _stalled_frames: int = 0
## netfox raises its history floor when it skips ticks after a stall. The first
## value seen (the clock sync at start-up) is the baseline.
var _floor_seen: int = -1
var _floor_jumps: int = 0

## peer id -> {tick: number of passes in which the bot fired at that tick}
var _fire_passes: Dictionary = {}

## Bandwidth window: starts when two bots exist, ends when fewer than two remain.
var _bw_started_msec: int = -1
var _bw_ended_msec: int = -1
var _bw_sent: int = 0
var _bw_received: int = 0

## ENet packet peer (by remote port) -> {min throttle seen, last throttle, highest loss seen}.
## Throttle 32 is ENet's maximum; below it ENet drops that share of unreliable packets.
var _throttle: Dictionary = {}

## How far ahead of this process's own tick the received input and state
## snapshots were stamped, at most (first arrivals only).
var _max_input_lead: int = -1000000
var _max_state_lead: int = -1000000

func _ready() -> void:
	NetworkRollback.after_prepare_tick.connect(_on_after_prepare_tick)
	NetworkRollback.on_record_tick.connect(_on_record_tick)
	NetworkSynchronizationServer._on_input.connect(func(snapshot: _Snapshot) -> void:
		_max_input_lead = maxi(_max_input_lead, snapshot.tick - NetworkTime.tick))
	NetworkSynchronizationServer._on_state.connect(func(snapshot: _Snapshot) -> void:
		_max_state_lead = maxi(_max_state_lead, snapshot.tick - NetworkTime.tick))

func _process(delta: float) -> void:
	if delta > NetworkTime.stall_threshold:
		_stalled_frames += 1
	_track_bandwidth()
	_track_throttle()

func _track_throttle() -> void:
	var connection: ENetConnection = _connection()
	if connection == null:
		return
	for peer: ENetPacketPeer in connection.get_peers():
		if peer.get_state() != ENetPacketPeer.STATE_CONNECTED:
			continue
		var value: int = int(peer.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE))
		var loss: int = int(peer.get_statistic(ENetPacketPeer.PEER_PACKET_LOSS))
		var row: Dictionary = _throttle.get_or_add(peer.get_remote_port(), {"min": value, "last": value, "loss": 0, "limit": int(peer.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE_LIMIT))}) as Dictionary
		row["min"] = mini(row["min"] as int, value)
		row["last"] = value
		row["loss"] = maxi(row["loss"] as int, loss)

## Per-tick passes in which a bot fired: peer id -> {tick: passes}.
func fire_passes() -> Dictionary:
	return _fire_passes

func _connection() -> ENetConnection:
	var peer: ENetMultiplayerPeer = multiplayer.multiplayer_peer as ENetMultiplayerPeer
	return peer.host if peer != null else null

# ENet counts bytes since the last pop; the window opens with a pop and closes with another.
func _track_bandwidth() -> void:
	var connection: ENetConnection = _connection()
	if connection == null:
		return
	var running: bool = _bw_started_msec >= 0 and _bw_ended_msec < 0
	if _bw_started_msec < 0 and _bots().size() >= 2:
		connection.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA)
		connection.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA)
		_bw_started_msec = Time.get_ticks_msec()
	elif running and _bots().size() < 2:
		_close_bandwidth(connection)

func _close_bandwidth(connection: ENetConnection) -> void:
	_bw_ended_msec = Time.get_ticks_msec()
	_bw_sent = int(connection.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA))
	_bw_received = int(connection.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA))

func _bots() -> Array[Bot]:
	var result: Array[Bot] = []
	for node: Node in get_tree().get_nodes_in_group(&"bots"):
		var bot: Bot = node as Bot
		if bot != null:
			result.append(bot)
	return result

static func _vec(value: Variant) -> Vector2:
	return value as Vector2 if typeof(value) == TYPE_VECTOR2 else Vector2.INF

static func _flag(value: Variant) -> int:
	return int(value == true) if typeof(value) == TYPE_BOOL else -1

func _on_after_prepare_tick(tick: int) -> void:
	var snapshot: _Snapshot = NetworkHistoryServer._get_rollback_state_snapshot(tick)
	for bot: Bot in _bots():
		bot.last_sim_tick = -1
		var auth: bool = snapshot != null and snapshot.is_auth(bot)
		# Tick the current run of consecutive simulated ticks started from a
		# received server state; -1 if it did not start from one.
		var previous: Dictionary = _prepared.get(bot.peer_id, {}) as Dictionary
		var root: int = -1
		if auth:
			root = tick
		elif not previous.is_empty() and (previous["tick"] as int) == tick - 1:
			root = previous["root"] as int
		_prepared[bot.peer_id] = {
			"tick": tick,
			"root": root,
			"auth": auth,
			"move": _vec(bot.input.move),
			"aim": _vec(bot.input.aim),
			"jet": _flag(bot.input.jet),
			"dash": _flag(bot.input.dash),
		}

func _on_record_tick(tick: int) -> void:
	var floor_now: int = NetworkRollback._history_floor
	if _floor_seen >= 0 and floor_now != _floor_seen:
		_floor_jumps += 1
	_floor_seen = floor_now
	for bot: Bot in _bots():
		# One pass of tick - 1 just ended; count it if the bot fired in it.
		if bot.last_sim_tick == tick - 1 and bot.arsenal.fired_at(tick - 1):
			var passes: Dictionary = _fire_passes.get_or_add(bot.peer_id, {}) as Dictionary
			passes[tick - 1] = (passes.get(tick - 1, 0) as int) + 1
		var prepared: Dictionary = _prepared.get(bot.peer_id, {}) as Dictionary
		if prepared.is_empty() or (prepared["tick"] as int) != tick - 1:
			continue
		if not _rows.has(bot.peer_id):
			_rows[bot.peer_id] = {}
		var rows: Dictionary = _rows[bot.peer_id]
		var row: Dictionary = prepared.duplicate()
		row["pos"] = bot.global_position
		row["sim"] = bot.last_sim_tick == tick - 1
		row["hp"] = bot.vitals.health
		row["hits"] = bot.vitals.hits_taken
		row["ko"] = bot.vitals.ko_serial
		# The latest one-step re-simulation from a received server state is kept
		# over later passes that chained from the client's own predictions.
		var existing: Dictionary = rows.get(tick, {}) as Dictionary
		if existing.is_empty() or (row["auth"] as bool) or not (existing["auth"] as bool):
			rows[tick] = row
		if rows.size() > MAX_ROWS_PER_BOT:
			for old: int in rows.keys():
				if old < tick - MAX_ROWS_PER_BOT:
					rows.erase(old)

## Print one TRACE line per recorded tick of every bot, a FINAL line per bot
## with its last recorded tick (the host's copy of a client bot stops when that
## client leaves), and a STALL line.
func dump(role: String) -> void:
	for peer_id: int in _rows:
		var rows: Dictionary = _rows[peer_id]
		var ticks: Array = rows.keys()
		ticks.sort()
		for tick: int in ticks:
			var row: Dictionary = rows[tick]
			var pos: Vector2 = row["pos"]
			var move: Vector2 = row["move"]
			var aim: Vector2 = row["aim"]
			print("TRACE peer=%d tick=%d x=%.3f y=%.3f sim=%d auth=%d root=%d mx=%.4f my=%.4f ax=%.4f ay=%.4f jet=%d dash=%d hp=%.3f hits=%d ko=%d" % [
				peer_id, tick, pos.x, pos.y, int(row["sim"] as bool), int(row["auth"] as bool), row["root"] as int,
				move.x, move.y, aim.x, aim.y, row["jet"] as int, row["dash"] as int,
				row["hp"] as float, row["hits"] as int, row["ko"] as int])
		var last: int = ticks.back() as int
		var last_pos: Vector2 = (rows[last] as Dictionary)["pos"]
		print("FINAL role=%s peer=%d last_tick=%d x=%.3f y=%.3f now_tick=%d" % [role, peer_id, last, last_pos.x, last_pos.y, NetworkTime.tick])
	if role == "host":
		for peer_id: int in _fire_passes:
			var passes: Dictionary = _fire_passes[peer_id]
			var fire_ticks: Array = passes.keys()
			fire_ticks.sort()
			for fire_tick: int in fire_ticks:
				print("FIRE peer=%d tick=%d passes=%d" % [peer_id, fire_tick, passes[fire_tick] as int])
	_print_bandwidth(role)
	_print_throttle(role)
	_print_pool()
	print("CLOCK role=%s rtt_ms=%.2f jitter_ms=%.2f unresolved_offset_ms=%.2f" % [role, NetworkTimeSynchronizer.rtt * 1000.0, NetworkTimeSynchronizer.rtt_jitter * 1000.0, NetworkTimeSynchronizer._offset * 1000.0])
	print("LEAD role=%s max_input_lead=%d max_state_lead=%d" % [role, _max_input_lead, _max_state_lead])
	print("STALL role=%s frames=%d floor_jumps=%d" % [role, _stalled_frames, _floor_jumps])

# Loss is ENet's own measure, scaled by 65536. limit is the throttle's maximum.
func _print_throttle(role: String) -> void:
	for port: int in _throttle:
		var row: Dictionary = _throttle[port]
		print("THROTTLE role=%s peer_port=%d min=%d last=%d limit=%d loss_max=%.4f" % [
			role, port, row["min"] as int, row["last"] as int, row["limit"] as int, float(row["loss"] as int) / 65536.0])

func _print_bandwidth(role: String) -> void:
	var connection: ENetConnection = _connection()
	if connection == null or _bw_started_msec < 0:
		print("BANDWIDTH role=%s seconds=0 sent_bytes=0 received_bytes=0 sent_bps=0 received_bps=0" % role)
		return
	if _bw_ended_msec < 0:
		_close_bandwidth(connection)
	var seconds: float = float(_bw_ended_msec - _bw_started_msec) / 1000.0
	print("BANDWIDTH role=%s seconds=%.2f sent_bytes=%d received_bytes=%d sent_bps=%.0f received_bps=%.0f" % [
		role, seconds, _bw_sent, _bw_received, float(_bw_sent) / seconds, float(_bw_received) / seconds])

# The names of the object slots and pickup spots, so a test can compare host and client.
func _print_pool() -> void:
	var names: PackedStringArray = PackedStringArray()
	for node: Node in get_parent().get_node("Objects").get_children():
		names.append(String(node.name))
	var spots: PackedStringArray = PackedStringArray()
	for node: Node in get_parent().get_node("Pickups").get_children():
		spots.append(String(node.name))
	print("POOL objects=%d names=%s spots=%d spot_names=%s" % [names.size(), ",".join(names), spots.size(), ",".join(spots)])
