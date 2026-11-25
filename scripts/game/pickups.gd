class_name Pickups
extends Node2D
## The fixed pickup spots of the arena ("Pickups" in main.tscn): Spot0 to SpotN-1, created
## in _ready identically on every peer from the layout, never freed. Three weapons and the
## Spring Plate in phase 1 (no crates).
##
## Owner: task C (weapons, melee, pickups).

const SPOT_SCENE: PackedScene = preload("res://scenes/pickup_spot.tscn")

@export var layout: ArenaLayout

var _spots: Array[PickupSpot] = []

func _ready() -> void:
	var px: float = MatchSettings.tuning_at(0).bot_height_px
	for i: int in layout.pickup_spots.size():
		var spot: PickupSpot = SPOT_SCENE.instantiate() as PickupSpot
		spot.name = "Spot%d" % i
		spot.position = layout.pickup_spots[i] * px
		spot.item = layout.pickup_items[i]
		add_child(spot)
		_spots.append(spot)
	# See WorldObjects: netfox fixes ownership at registration and re-registers only when this
	# peer joins a game, so a phone that joined, left and then hosted needs it done again.
	NetworkEvents.on_server_start.connect(_on_server_start)
	# The main scene stays loaded between sessions, and a new session starts its tick count
	# again, so pickup cooldowns of the old session must not carry into the new one.
	NetworkEvents.on_server_start.connect(reset_session)
	NetworkEvents.on_server_stop.connect(reset_session)
	NetworkEvents.on_client_start.connect(_on_client_start)
	NetworkEvents.on_client_stop.connect(reset_session)

func _on_server_start() -> void:
	for spot: PickupSpot in _spots:
		(spot.get_node("RollbackSynchronizer") as RollbackSynchronizer).process_settings()

func _on_client_start(_id: int) -> void:
	reset_session()

## Make every pickup spot ready again (a session started or stopped).
func reset_session() -> void:
	for spot: PickupSpot in _spots:
		spot.ready_tick = 0

## All spots in index order.
func spots() -> Array[PickupSpot]:
	return _spots

## Host only, called by the resolver once per tick after bots and objects have moved:
## offer each ready spot's item to the live bots standing on it in peer id order, until one
## takes it, and set the spot's ready_tick. bots are not assumed to be sorted. Writes state
## only. The dummy never picks anything up.
func resolve(tick: int, bots: Array[Bot], cfg: TuningConfig) -> void:
	# Phase 1 test scaffolding: every spot taken in an earlier hazard cycle is on offer again,
	# even if a stall skipped the exact cycle-boundary tick. The take tick is inferred as
	# ready_tick - respawn_ticks so no extra state is needed.
	# shortcut: the inference is wrong if a Chaos Card changes pickup_respawn_time while a spot
	# is on cooldown. A longer time moves the inferred take tick earlier, so a spot taken this
	# cycle can be reset at once. A shorter time moves it later, so a spot taken late in the
	# previous cycle is not reset when the boundary tick was skipped. Upgrade to a synced
	# per-spot take cycle when that card exists and the scaffolding is still in.
	var into_cycle: int = MatchSettings.hazard_ticks(tick)
	if into_cycle >= 0:
		var cycle_start: int = tick - into_cycle
		if cycle_start > MatchSettings.round_start_tick:
			var respawn_ticks: int = WeaponRules.seconds_to_ticks(cfg.pickup_respawn_time, cfg)
			for spot: PickupSpot in _spots:
				if into_cycle == 0 or spot.ready_tick - respawn_ticks < cycle_start:
					spot.ready_tick = mini(spot.ready_tick, cycle_start)
	var radius: float = cfg.pickup_radius * cfg.bot_height_px
	for spot: PickupSpot in _spots:
		if tick < spot.ready_tick:
			continue
		var standing: Array[Bot] = []
		for bot: Bot in bots:
			if not bot.vitals.knocked_out and bot.peer_id != Bot.DUMMY_PEER and CombatGeometry.circle_rect(spot.global_position, radius, bot.body_rect()):
				standing.append(bot)
		standing.sort_custom(_lower_peer)
		# A bot that cannot take the item (full gadget slots) does not block the others.
		for bot: Bot in standing:
			if _give(bot, spot.item, cfg):
				spot.ready_tick = tick + WeaponRules.seconds_to_ticks(cfg.pickup_respawn_time, cfg)
				break

func _lower_peer(a: Bot, b: Bot) -> bool:
	return a.peer_id < b.peer_id

# True when the bot took the item: a weapon always, a gadget only if it has room.
func _give(bot: Bot, item: int, cfg: TuningConfig) -> bool:
	if ItemIds.is_gadget(item):
		return bot.gadgets.give(item)
	if ItemIds.is_weapon(item) and item != ItemIds.RIVET_GUN:
		bot.arsenal.give_weapon(item, cfg)
		return true
	return false
