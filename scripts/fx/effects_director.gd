class_name EffectsDirector
extends Node
## Turns the state counters of bots and objects into one-shot effects on this phone
## ("Effects" in main.tscn). For each counter it keeps the highest value seen per node
## (CounterWatch), triggers once per increase above it, and records without triggering the
## first time it sees a node (architecture D7). It runs in _process after netfox has restored
## the display state for the frame, and it only reads: it never writes a property of a bot,
## its Vitals, Arsenal or Gadgets, a world-object slot, a pickup spot or MatchSettings, never
## pauses or slows anything, and never uses the global random generator.
##
## Counters watched: vitals.hits_taken, vitals.ko_serial, arsenal.shots_fired,
## arsenal.melee_serial on each bot, and blasts on each world-object slot. The other counters
## of D7 (gadget_serial, launches) have no effect of their own yet and are not watched.
##
## When one frame sees a counter rise by more than one: shots and swings trigger once per
## increase (each is a drawn shape of its own, bounded by the pool); hits, knockouts and blasts
## trigger once (a second flash, freeze, shake or burst in the same frame looks the same, and a
## burst allocates).
##
## First sight and sessions: a node's counters are first recorded, silently, on the first frame
## they come from real state. On the host that is at once (the host's own values are the
## simulation). On a client it is the first frame after (1) NetworkHistoryServer.has_authoritative_state
## is true for the nodes that carry the counters, meaning a snapshot from the host has been merged
## for them, and (2) a rollback loop has finished since the director saw that, because netfox puts
## merged state on the live nodes only at the end of a loop and a frame can pass without one.
## Until then the node is not looked at, so a predicted value, or the zeros of a bot that has only
## just spawned, are never taken for events or for history. All marks are cleared when a session
## starts or stops, because the slots live as long as the process and a new host counts from 0 again.
##
## Owner: task E (presentation).

## An effect fired. kind is &"hit", &"knockout", &"shot", &"swing" or &"blast"; source is the
## bot or the object slot. For tests and later sound; nothing in the game needs it.
signal effect_triggered(kind: StringName, source: Node)

const HazardMath: GDScript = preload("res://hazard/hazard_math.gd")
## Parts of a blast.
const BLAST_COLOR: Color = Color(0.95, 0.6, 0.2)

enum BotCounter { HITS, KNOCKOUTS, SHOTS, SWINGS, COUNT }
enum SlotCounter { BLASTS, COUNT }

## Where parts fly. Show physics only; it is not under a bot, so the parts outlive it.
@export var burst: PartsBurst
## Screen shake on the camera.
@export var shake: ScreenShake
## The rising metal, driven here from MatchSettings.hazard_ticks and HazardMath.
@export var hazard_visual: HazardVisual
## The arena layout: floor (bounds.end.y), width and x position of the metal, hazard_top, and
## the solid rectangles a tracer stops at.
@export var layout: ArenaLayout
## The pool of world objects, for blast effects.
@export var objects: WorldObjects

var _loops: int = 0
var _bots: Dictionary[Bot, CounterWatch] = {}
var _slot_watches: Array[CounterWatch] = []
var _solids: Array[Rect2] = []
var _fx: ShotFx

func _ready() -> void:
	# After every node at the default priority, so after interpolation has set the bots' places.
	process_priority = 10
	var cfg: TuningConfig = _display_config()
	_apply_config(cfg)
	_fx = ShotFx.new()
	add_child(_fx)
	_fx.configure(cfg)
	if layout != null:
		_solids = layout.solid_rects_px(cfg.bot_height_px)
	_setup_hazard(cfg)
	NetworkRollback.after_loop.connect(_on_after_loop)
	NetworkEvents.on_server_start.connect(forget_marks)
	NetworkEvents.on_server_stop.connect(forget_marks)
	NetworkEvents.on_client_start.connect(_on_client_start)
	NetworkEvents.on_client_stop.connect(forget_marks)
	get_tree().node_added.connect(_on_node_added)
	get_tree().node_removed.connect(_on_node_removed)
	for node: Node in get_tree().get_nodes_in_group(&"bots"):
		_on_node_added(node)

func _process(_delta: float) -> void:
	scan()

## One pass over everything watched, as _process does it each frame. Public so a test can drive it.
func scan() -> void:
	var cfg: TuningConfig = _display_config()
	for bot: Bot in _bots:
		if is_instance_valid(bot) and bot.is_node_ready() and _has_real_state(bot, _bots[bot]):
			_watch_bot(bot, _bots[bot], cfg)
	_watch_slots(cfg)
	update_hazard(NetworkRollback.display_tick)

## Puts the metal on screen where the host's HazardMath puts it for this tick.
func update_hazard(tick: int) -> void:
	if hazard_visual == null or layout == null:
		return
	var cfg: TuningConfig = MatchSettings.tuning_at(tick)
	var px: float = cfg.bot_height_px
	hazard_visual.set_surface_y(HazardMath.surface_y(
			MatchSettings.hazard_ticks(tick), cfg.tick_rate, cfg.hazard_start_time, cfg.hazard_cap_time,
			layout.hazard_floor_px(px), layout.hazard_top_px(px)))

## Forgets every high-water mark, for bots and slots, and hides the health bars: the next real value
## of each is a first sight.
## Called when a session starts or stops.
func forget_marks() -> void:
	for bot: Bot in _bots:
		_bots[bot] = CounterWatch.new(BotCounter.COUNT)
		if bot.is_node_ready():
			bot.visual.health_bar.reset()
	_slot_watches.clear()

## Number of bots being watched.
func watched_bot_count() -> int:
	return _bots.size()

## The shapes layer, for tests.
func shot_fx() -> ShotFx:
	return _fx

func _display_config() -> TuningConfig:
	return MatchSettings.tuning_at(NetworkRollback.display_tick)

# The kit's numbers come from the config once, at start.
func _apply_config(cfg: TuningConfig) -> void:
	if burst != null:
		burst.piece_count = cfg.debris_piece_count
		burst.lifetime = cfg.debris_lifetime
		burst.fade_time = cfg.debris_fade_time
		burst.impulse = cfg.debris_impulse_px
		burst.impulse_variation = cfg.debris_impulse_variation
		burst.spread_degrees = cfg.debris_spread_degrees
		burst.spin = cfg.debris_spin
		burst.piece_size_min = cfg.debris_size_min_px
		burst.piece_size_max = cfg.debris_size_max_px
		burst.bounce = cfg.debris_bounce
		burst.max_debris = cfg.debris_max
	if shake != null:
		shake.decay_per_second = cfg.shake_decay_per_second

func _setup_hazard(cfg: TuningConfig) -> void:
	if hazard_visual == null or layout == null:
		return
	var px: float = cfg.bot_height_px
	var floor_y: float = layout.hazard_floor_px(px)
	if not HazardMath.is_config_valid(cfg.tick_rate, cfg.hazard_start_time, cfg.hazard_cap_time, floor_y, layout.hazard_top_px(px)):
		push_error("EffectsDirector: the hazard numbers in the config or layout are not usable")
	hazard_visual.floor_y = floor_y
	hazard_visual.arena_width = layout.bounds.size.x * px
	hazard_visual.position.x = layout.bounds.position.x * px

func _on_client_start(_peer: int) -> void:
	forget_marks()

func _on_after_loop() -> void:
	_loops += 1

# True once the counters of a bot or slot are real and may be recorded as first sight or stepped.
# The host's own nodes are real at once. On a client see the header: the query is per subject, and
# the subject is the node a counter is registered on in the RollbackSynchronizer (Vitals for
# hits_taken and ko_serial, Arsenal for shots_fired and melee_serial, the slot itself for blasts),
# then one rollback loop has to finish so the live nodes hold the merged state.
#
# Known limits (reviewed, accepted for now):
# - If the frame that merges a subject's first state also runs a loop, this still waits for the next
#   loop, so first sight comes one loop later than it could, and a counter that rises in that loop
#   is recorded silently. In practice only a rocket fired into a never-sent slot within a second of
#   a late join, hitting a wall on the next tick, loses its blast effect once.
# - The gate is per subject, not per tick. If a subject's first state from the host is stamped later
#   than this client's display tick, first sight records predicted values, and the old history can
#   replay once when the display reaches it. That needs a clock offset between host and client and
#   has not been reproduced.
func _has_real_state(node: Node, watch: CounterWatch) -> bool:
	if node.is_multiplayer_authority():
		return true
	var bot: Bot = node as Bot
	var known: bool = (_is_authoritative(bot.vitals) and _is_authoritative(bot.arsenal)) if bot != null else _is_authoritative(node)
	if not known:
		return false
	if watch.armed_at_loop < 0:
		watch.armed_at_loop = _loops
	return _loops > watch.armed_at_loop

func _is_authoritative(subject: Node) -> bool:
	return is_instance_valid(subject) and NetworkHistoryServer.has_authoritative_state(subject)

func _on_node_added(node: Node) -> void:
	var bot: Bot = node as Bot
	if bot != null and not _bots.has(bot):
		_bots[bot] = CounterWatch.new(BotCounter.COUNT)

func _on_node_removed(node: Node) -> void:
	var bot: Bot = node as Bot
	if bot != null:
		_bots.erase(bot)

func _watch_bot(bot: Bot, watch: CounterWatch, cfg: TuningConfig) -> void:
	bot.visual.health_bar.observe(bot.vitals.health, cfg.health_bar_hold_seconds, bot.vitals.knocked_out)
	if watch.step(BotCounter.HITS, bot.vitals.hits_taken) > 0:
		_on_hit(bot, cfg)
	if watch.step(BotCounter.KNOCKOUTS, bot.vitals.ko_serial) > 0:
		_on_knockout(bot, cfg)
	for i: int in watch.step(BotCounter.SHOTS, bot.arsenal.shots_fired):
		_on_shot(bot, cfg)
	for i: int in watch.step(BotCounter.SWINGS, bot.arsenal.melee_serial):
		_on_swing(bot, cfg)

func _watch_slots(cfg: TuningConfig) -> void:
	if objects == null:
		return
	var slots: Array[WorldObject] = objects.slots()
	while _slot_watches.size() < slots.size():
		_slot_watches.append(CounterWatch.new(SlotCounter.COUNT))
	for i: int in slots.size():
		if not _has_real_state(slots[i], _slot_watches[i]):
			continue
		if _slot_watches[i].step(SlotCounter.BLASTS, slots[i].blasts) > 0:
			_on_blast(slots[i], cfg)

func _on_hit(bot: Bot, cfg: TuningConfig) -> void:
	bot.visual.hit_flash.flash(cfg.hit_flash_seconds)
	# Light rapid fire stays below the threshold and gets no freeze.
	if bot.vitals.last_hit_push.length() >= cfg.hit_freeze_min_push:
		bot.visual.hit_freeze.freeze(cfg.hit_freeze_frames)
	if shake != null and _is_local(bot):
		shake.shake(cfg.shake_strength_hit_px)
	effect_triggered.emit(&"hit", bot)

func _on_knockout(bot: Bot, cfg: TuningConfig) -> void:
	if burst != null:
		burst.burst(bot.center(), BotVisual.body_color(bot.slot, cfg), bot.vitals.last_hit_push)
	if shake != null:
		shake.shake(cfg.shake_strength_knockout_px)
	effect_triggered.emit(&"knockout", bot)

# Every shot gets a muzzle flash. Only the rivet gun and the bolt thrower, which fire one instant
# line, also get a tracer, from the muzzle to the first wall or the weapon's range. A tracer for
# the rocket tube would cross the arena while the rocket is still at the muzzle and read as a hit,
# and one centre line would misrepresent the scrap blaster's pellets. Use the weapon that fired,
# since a pickup or swap can change what the bot holds before the shot is drawn.
func _on_shot(bot: Bot, cfg: TuningConfig) -> void:
	var dir: Vector2 = _direction(bot.arsenal.shot_dir, bot.aim_dir)
	var from: Vector2 = bot.center()
	var weapon: int = bot.arsenal.last_shot_weapon
	var stats: WeaponStats = cfg.weapon_stats(weapon)
	var offset: float = cfg.muzzle_offset_bh * cfg.bot_height_px
	var color: Color = BotVisual.body_color(bot.slot, cfg)
	if stats == null or not (weapon == ItemIds.RIVET_GUN or weapon == ItemIds.BOLT_THROWER):
		_fx.add_shot(from + dir * offset, from + dir * offset, color, false)
	else:
		var reach: float = stats.range_bh * cfg.bot_height_px
		var end: Vector2 = from + dir * reach
		var wall: CastResult = CombatGeometry.cast(from, end, _solids)
		if wall.index >= 0:
			end = from + dir * reach * wall.t
		_fx.add_shot(from + dir * minf(offset, from.distance_to(end)), end, color, true)
	effect_triggered.emit(&"shot", bot)

# A usable unit direction: first if it is finite and not zero, otherwise fallback.
func _direction(first: Vector2, fallback: Vector2) -> Vector2:
	if first.is_finite() and first != Vector2.ZERO:
		return first.normalized()
	return fallback.normalized()

func _on_swing(bot: Bot, cfg: TuningConfig) -> void:
	# The weapons task stores the swing direction in shot_dir; aim_dir is the fallback.
	_fx.add_swing(bot.center(), _direction(bot.arsenal.shot_dir, bot.aim_dir), BotVisual.body_color(bot.slot, cfg))
	effect_triggered.emit(&"swing", bot)

func _on_blast(slot: WorldObject, cfg: TuningConfig) -> void:
	if burst != null:
		burst.burst(slot.global_position, BLAST_COLOR, Vector2.ZERO)
	var local: Bot = _local_bot()
	if shake != null and local != null:
		var range_px: float = cfg.blast_shake_range_bh * cfg.bot_height_px
		var closeness: float = clampf(1.0 - local.center().distance_to(slot.global_position) / range_px, 0.0, 1.0)
		if closeness > 0.0:
			shake.shake(cfg.shake_strength_knockout_px * closeness)
	effect_triggered.emit(&"blast", slot)

func _is_local(bot: Bot) -> bool:
	return bot.peer_id == multiplayer.get_unique_id()

func _local_bot() -> Bot:
	for bot: Bot in _bots:
		if _is_local(bot):
			return bot
	return null
