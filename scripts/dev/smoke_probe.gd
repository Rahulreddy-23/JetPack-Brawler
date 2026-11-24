class_name SmokeProbe
extends Node
## Test support for the two-process network smoke test (debug builds only).
## For every bot and every simulated tick it records the resulting position,
## the input values the simulation used, whether the tick was really simulated
## (not just carried over), and whether the state it started from was received
## from the server. A later re-simulation of the same tick overwrites the row,
## so the final row is the reconciled one. The memory used is bounded.

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

func _ready() -> void:
	NetworkRollback.after_prepare_tick.connect(_on_after_prepare_tick)
	NetworkRollback.on_record_tick.connect(_on_record_tick)

func _process(delta: float) -> void:
	if delta > NetworkTime.stall_threshold:
		_stalled_frames += 1

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
		_prepared[bot.peer_id] = {
			"tick": tick,
			"auth": snapshot != null and snapshot.is_auth(bot),
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
		var prepared: Dictionary = _prepared.get(bot.peer_id, {}) as Dictionary
		if prepared.is_empty() or (prepared["tick"] as int) != tick - 1:
			continue
		if not _rows.has(bot.peer_id):
			_rows[bot.peer_id] = {}
		var rows: Dictionary = _rows[bot.peer_id]
		var row: Dictionary = prepared.duplicate()
		row["pos"] = bot.global_position
		row["sim"] = bot.last_sim_tick == tick - 1
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
			print("TRACE peer=%d tick=%d x=%.3f y=%.3f sim=%d auth=%d mx=%.4f my=%.4f ax=%.4f ay=%.4f jet=%d dash=%d" % [
				peer_id, tick, pos.x, pos.y, int(row["sim"] as bool), int(row["auth"] as bool),
				move.x, move.y, aim.x, aim.y, row["jet"] as int, row["dash"] as int])
		var last: int = ticks.back() as int
		var last_pos: Vector2 = (rows[last] as Dictionary)["pos"]
		print("FINAL role=%s peer=%d last_tick=%d x=%.3f y=%.3f now_tick=%d" % [role, peer_id, last, last_pos.x, last_pos.y, NetworkTime.tick])
	print("STALL role=%s frames=%d floor_jumps=%d" % [role, _stalled_frames, _floor_jumps])
