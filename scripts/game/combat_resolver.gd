class_name CombatResolver
extends Node
## The one stateless host-side resolver ("Resolver" in main.tscn). It is connected to
## netfox's after_process_tick, so it runs on every tick including re-simulated ones,
## after every bot and object has moved and before the tick is recorded. It returns at
## once on a client. It sends no RPC, spawns and frees nothing, keeps no state between
## ticks, and applies everything in one pass with bots sorted by peer id.
##
## Owner: task A (this wiring); the four rule functions it calls belong to tasks B to D.

@export var objects: WorldObjects
@export var pickups: Pickups
@export var layout: ArenaLayout

var _solids: Array[Rect2] = []

func _ready() -> void:
	_solids = layout.solid_rects_px(MatchSettings.tuning_at(0).bot_height_px)
	NetworkRollback.after_process_tick.connect(_on_after_process_tick)

func _on_after_process_tick(tick: int) -> void:
	if not multiplayer.is_server():
		return
	resolve(tick, _sorted_bots())

## One resolver pass for a tick over the given bots (sorted by peer id). Separate from the
## signal handler so a test can run a pass without a network.
func resolve(tick: int, bots: Array[Bot]) -> void:
	var cfg: TuningConfig = MatchSettings.tuning_at(tick)
	var hits: Array[Hit] = []
	GadgetRules.clear_old_cycle(tick, objects)
	WeaponRules.collect(tick, bots, objects, _solids, cfg, hits)
	GadgetRules.collect(tick, bots, objects, _solids, cfg, hits)
	pickups.resolve(tick, bots, cfg)
	CombatRules.apply(tick, bots, hits, layout, cfg)

func _sorted_bots() -> Array[Bot]:
	var bots: Array[Bot] = []
	for node: Node in get_tree().get_nodes_in_group(&"bots"):
		var bot: Bot = node as Bot
		if bot != null:
			bots.append(bot)
	bots.sort_custom(func(a: Bot, b: Bot) -> bool: return a.peer_id < b.peer_id)
	return bots
