extends Node
## One process of the late-joiner test (tests/net_world_objects_join.sh). It instances
## scenes/main.tscn directly under the root and only watches and drives:
##   -- --host --port=P ...   the host: its own bot tosses a Spring Plate, which stays on the
##                            map; it quits when the joiner has left, then prints its view
##   -- --join=127.0.0.1 ...  the joiner: connects after the plate is down, waits until it
##                            sees the plate, prints its view and quits
## Both print one JOINRESULT line with the plate slot's state. The plate is thrown by giving
## the host's bot a plate and setting its gadget and aim inputs after BotInput has gathered
## them, so no shared file is touched.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_SECONDS: float = 60.0
const GIVE_AFTER_TICKS: int = 10
const BOMB_AFTER_TICKS: int = 40
const PLATE_AFTER_TICKS: int = 90
const JOINER_SETTLE_TICKS: int = 45

var _main: Main = null
var _role: String = ""
var _pool: WorldObjects = null
var _watch: WorldObject = null
var _first_tick: int = -1
var _seen_tick: int = -1
var _max_peers: int = 0
var _launch_rises: int = 0
var _high_launches: int = 0

func _ready() -> void:
	get_tree().create_timer(TIMEOUT_SECONDS).timeout.connect(_fail.bind("timeout"))
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--host":
			_role = "host"
		elif arg.begins_with("--join"):
			_role = "joiner"
	_main = MAIN_SCENE.instantiate() as Main
	# The spawner's node path must match the host's, so Main goes directly under root.
	get_tree().root.add_child.call_deferred(_main)

func _fail(reason: String) -> void:
	print("FAIL ", reason)
	get_tree().quit(1)

func _host_bot() -> Bot:
	var bots: Node = _main.get_node_or_null("Bots")
	if bots == null:
		return null
	for child: Node in bots.get_children():
		var bot: Bot = child as Bot
		if bot != null and bot.peer_id == 1:
			return bot
	return null

func _process(_delta: float) -> void:
	if _main == null or not _main.is_inside_tree():
		return
	if _pool == null:
		var bot: Bot = _host_bot()
		if bot == null:
			return
		_pool = _main.get_node("Objects") as WorldObjects
		_watch = _pool.slots()[_pool.slot_range(ItemIds.OBJECT_PLATE, bot.slot, MatchSettings.tuning_at(0)).x]
		_first_tick = NetworkTime.tick
		if _role == "host":
			# Connected after the bot's own input node, so this runs after it has gathered.
			NetworkTime.after_tick.connect(_after_gather.bind(bot))
			bot.gadgets.give(ItemIds.SPRING_PLATE)
	if _watch.launches > _high_launches:
		_launch_rises += 1
		_high_launches = _watch.launches
	if _role == "host":
		_max_peers = maxi(_max_peers, multiplayer.get_peers().size())
		if _seen_tick < 0 and _watch.active:
			_seen_tick = NetworkTime.tick
			print("PLATE_THROWN tick=%d" % _watch.spawn_tick)
		if _max_peers > 0 and multiplayer.get_peers().is_empty():
			_dump()
			get_tree().quit(0)
	else:
		if _seen_tick < 0 and _watch.active and _watch.landed:
			_seen_tick = NetworkTime.tick
		if _seen_tick >= 0 and NetworkTime.tick >= _seen_tick + JOINER_SETTLE_TICKS:
			_dump()
			get_tree().quit(0)

# A bomb first (it uses the bot's own bomb), then the plate, both thrown straight down.
func _after_gather(_delta: float, tick: int, bot: Bot) -> void:
	bot.input.aim = Vector2(0.0, 1.0)
	var since: int = tick - _first_tick
	bot.input.gadget = since == BOMB_AFTER_TICKS or since == PLATE_AFTER_TICKS

func _dump() -> void:
	var pos: Vector2 = _watch.global_position
	print("JOINRESULT role=%s active=%d kind=%d landed=%d launches=%d spawn_tick=%d arm_tick=%d owner=%d x=%.3f y=%.3f launch_rises=%d" % [
		_role, int(_watch.active), _watch.kind, int(_watch.landed), _watch.launches, _watch.spawn_tick, _watch.arm_tick, _watch.owner_peer, pos.x, pos.y, _launch_rises])
