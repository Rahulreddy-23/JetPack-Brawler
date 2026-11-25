extends Node
## The effects director on a client (task E). A client predicts the counters of every bot and
## slot, and the host's real state arrives later; the director must not look at a node until
## real state has been merged for it, and must start its marks from that first real state.
## This process runs as a client (connecting to a port with nothing listening, so its tick stays
## at 0) with the real main scene, and merges snapshots into netfox's history the way the
## handlers do for packets from the host, stamped as authoritative. Run:
##   godot --headless --path . res://tests/test_fx_client.tscn -- --port=N
## Exits 0 when every check passes, 1 otherwise (also on timeout).
##
## What it does not prove: that the host's real packets mark the subjects the director asks about.
## The subject check is on the real query with real nodes, but the snapshots are made here. The
## two-process test tests/net_fx.sh covers the packets.

const BOT_SCENE: PackedScene = preload("res://scenes/bot.tscn")
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const SERVER_PEER: int = 1
const TIMEOUT_SECONDS: float = 60.0

var _failures: int = 0
var _main: Node
var _director: EffectsDirector
var _bot: Bot
var _slot: WorldObject
var _events: Array[Array] = []
var _tick: int = 3
var _health: float = 100.0

func _ready() -> void:
	get_tree().create_timer(TIMEOUT_SECONDS).timeout.connect(_on_timeout)
	_run()

func _on_timeout() -> void:
	print("FAIL timeout, the test did not finish")
	get_tree().quit(1)

func _check(ok: bool, label: String) -> void:
	if ok:
		print("PASS ", label)
	else:
		_failures += 1
		print("FAIL ", label)

func _on_effect(kind: StringName, source: Node) -> void:
	_events.append([kind, source])

func _count(kind: StringName) -> int:
	var total: int = 0
	for event: Array in _events:
		if event[0] == kind:
			total += 1
	return total

func _counts() -> String:
	return "hit %d, knockout %d, shot %d, swing %d, blast %d" % [_count(&"hit"), _count(&"knockout"), _count(&"shot"), _count(&"swing"), _count(&"blast")]

func _all_counts(expected: int) -> bool:
	return _count(&"hit") == expected and _count(&"knockout") == expected and _count(&"shot") == expected and _count(&"swing") == expected and _count(&"blast") == expected

# What the host would send: the values for the subjects that carry the counters, authoritative.
# The live nodes only show them once netfox has restored display state at the end of a rollback
# loop, so this sets them too unless apply_live is false (state merged, loop not finished yet).
func _host_state(hits: int, knockouts: int, shots: int, swings: int, blasts: int, apply_live: bool = true) -> void:
	var snapshot: _Snapshot = _Snapshot.new(_tick)
	_tick += 1
	snapshot.set_property(_bot.vitals, ^"hits_taken", hits)
	snapshot.set_property(_bot.vitals, ^"ko_serial", knockouts)
	snapshot.set_property(_bot.arsenal, ^"shots_fired", shots)
	snapshot.set_property(_bot.arsenal, ^"melee_serial", swings)
	snapshot.set_property(_slot, ^"blasts", blasts)
	snapshot.set_property(_bot.vitals, ^"health", _health)
	for subject: Node in [_bot.vitals, _bot.arsenal, _slot]:
		snapshot.set_auth(subject, true)
	NetworkHistoryServer._merge_rollback_state(snapshot)
	if apply_live:
		_live(hits, knockouts, shots, swings, blasts)

func _live(hits: int, knockouts: int, shots: int, swings: int, blasts: int) -> void:
	_bot.vitals.hits_taken = hits
	_bot.vitals.ko_serial = knockouts
	_bot.arsenal.shots_fired = shots
	_bot.arsenal.melee_serial = swings
	_slot.blasts = blasts
	_bot.vitals.health = _health

func _run() -> void:
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	peer.create_client("127.0.0.1", LaunchArgs.parse(OS.get_cmdline_user_args()).port)
	multiplayer.multiplayer_peer = peer
	_check(not multiplayer.is_server(), "running as a client")
	_main = MAIN_SCENE.instantiate()
	add_child(_main)
	_bot = BOT_SCENE.instantiate() as Bot
	_bot.peer_id = 2
	_bot.slot = 1
	_bot.set_multiplayer_authority(SERVER_PEER)
	_main.add_child(_bot)
	await get_tree().process_frame
	await get_tree().process_frame
	_slot = (_main.get_node("Objects") as WorldObjects).slots()[3]
	_director = _main.get_node("Effects") as EffectsDirector
	_director.set_process(false)
	_director.effect_triggered.connect(_on_effect)

	_check(not _bot.is_multiplayer_authority() and not _slot.is_multiplayer_authority(), "the bot and the slot belong to the host, not to this client")
	_check(not NetworkHistoryServer.has_authoritative_state(_bot.vitals) and not NetworkHistoryServer.has_authoritative_state(_bot.arsenal) and not NetworkHistoryServer.has_authoritative_state(_slot), "no authoritative state yet for the Vitals, the Arsenal or the slot")

	# Predicted counters (the zeros of a fresh copy, then whatever this phone's own simulation makes).
	_director.scan()
	_live(2, 1, 3, 1, 2)
	NetworkRollback.after_loop.emit()
	_director.scan()
	_live(3, 2, 4, 2, 3)
	NetworkRollback.after_loop.emit()
	_director.scan()
	_health = 60.0
	_live(4, 3, 5, 3, 4)
	NetworkRollback.after_loop.emit()
	_director.scan()
	_health = 50.0
	_live(4, 3, 5, 3, 4)
	_director.scan()
	_check(not _bot.visual.health_bar.showing(), "a predicted health change does not show the bar before the host's state has arrived")
	_health = 100.0
	_check(_events.is_empty(), "predicted counter changes trigger nothing while the host's state has not arrived, loops or not (%s)" % _counts())

	# State for the Vitals only: the bot is not real until its Arsenal has state too.
	var vitals_only: _Snapshot = _Snapshot.new(2)
	vitals_only.set_property(_bot.vitals, ^"hits_taken", 7)
	vitals_only.set_auth(_bot.vitals, true)
	NetworkHistoryServer._merge_rollback_state(vitals_only)
	_check(NetworkHistoryServer.has_authoritative_state(_bot.vitals) and not NetworkHistoryServer.has_authoritative_state(_bot.arsenal), "state for the Vitals only is not state for the Arsenal")
	_live(7, 3, 6, 3, 4)
	_director.scan()
	NetworkRollback.after_loop.emit()
	_live(7, 3, 7, 3, 4)
	_director.scan()
	_check(_events.is_empty(), "a bot whose Arsenal has no state yet is not looked at (%s)" % _counts())

	# And the other way round: state for the Arsenal only, on a second bot.
	var other: Bot = BOT_SCENE.instantiate() as Bot
	other.peer_id = 3
	other.slot = 2
	other.set_multiplayer_authority(SERVER_PEER)
	_main.add_child(other)
	await get_tree().process_frame
	_director.scan()
	var arsenal_only: _Snapshot = _Snapshot.new(2)
	arsenal_only.set_property(other.arsenal, ^"shots_fired", 3)
	arsenal_only.set_auth(other.arsenal, true)
	NetworkHistoryServer._merge_rollback_state(arsenal_only)
	other.arsenal.shots_fired = 3
	_director.scan()
	NetworkRollback.after_loop.emit()
	other.arsenal.shots_fired = 4
	_director.scan()
	other.arsenal.shots_fired = 5
	_director.scan()
	_check(_events.is_empty(), "a bot whose Vitals have no state yet is not looked at either (%s)" % _counts())
	other.free()
	await get_tree().process_frame

	# The first real state. It carries numbers that are far from the predicted ones.
	_host_state(7, 5, 9, 4, 6, false)
	_check(NetworkHistoryServer.has_authoritative_state(_bot.vitals) and NetworkHistoryServer.has_authoritative_state(_bot.arsenal) and NetworkHistoryServer.has_authoritative_state(_slot), "after a snapshot from the host, the Vitals, the Arsenal and the slot have authoritative state")
	_check(not NetworkHistoryServer.has_authoritative_state(_bot), "and only the subjects the snapshot named (the bot root has none)")
	# The snapshot is merged but no rollback loop has finished, so the live nodes still hold the
	# predictions: the director must not take them for the first real values.
	_director.scan()
	_director.scan()
	_check(_events.is_empty(), "state merged but the live nodes not yet restored: nothing is recorded or shown (%s)" % _counts())
	_live(7, 5, 9, 4, 6)
	NetworkRollback.after_loop.emit()
	_director.scan()
	_check(_events.is_empty(), "the first frame with restored real state sets the marks and triggers nothing, whatever the predictions were (%s)" % _counts())

	_check(not _bot.visual.health_bar.showing(), "the bar did not show for the predictions or for the first real state")
	_health = 80.0
	_host_state(7, 5, 9, 4, 6)
	_director.scan()
	_check(_bot.visual.health_bar.showing(), "the bar shows when real health changes")
	_bot.visual.health_bar.reset()

	# The next real state, one more of each.
	_host_state(8, 6, 10, 5, 7)
	_director.scan()
	_check(_all_counts(1), "the next real increase triggers once for each counter (%s)" % _counts())

	# A prediction that runs ahead and is then corrected back down does not trigger either.
	_events.clear()
	_live(9, 7, 11, 6, 8)
	_director.scan()
	_check(_all_counts(1), "a predicted rise on top of real state still shows (the known cosmetic imperfection: %s)" % _counts())
	_live(8, 6, 10, 5, 7)
	_director.scan()
	_events.clear()
	_host_state(8, 6, 10, 5, 7)
	_director.scan()
	_check(_events.is_empty(), "the correction back to the real values triggers nothing")

	# The session ends and a new one starts: no state, then low numbers again.
	NetworkTime.stop()
	NetworkEvents.on_client_stop.emit()
	_check(not NetworkHistoryServer.has_authoritative_state(_bot.vitals) and not NetworkHistoryServer.has_authoritative_state(_slot), "after the session stops there is no authoritative state again")
	_events.clear()
	_live(0, 0, 0, 0, 0)
	_director.scan()
	_live(1, 1, 1, 1, 1)
	_director.scan()
	_check(_events.is_empty(), "nothing triggers between sessions")
	_tick = 3
	_host_state(1, 1, 2, 1, 1, false)
	_director.scan()
	_live(1, 1, 2, 1, 1)
	NetworkRollback.after_loop.emit()
	_director.scan()
	_check(_events.is_empty(), "the first real state of the new session, below the old marks, triggers nothing")
	_host_state(2, 2, 3, 2, 2)
	_director.scan()
	_check(_all_counts(1), "and its first real increase triggers although it is below the old marks (%s)" % _counts())

	print("%d failures" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)
