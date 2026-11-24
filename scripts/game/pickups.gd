class_name Pickups
extends Node2D
## The fixed pickup spots of the arena ("Pickups" in main.tscn): Spot0 to SpotN-1, created
## in _ready identically on every peer from the layout, never freed. Three weapons and the
## Spring Plate in phase 1 (no crates).
##
## Owner: task C (weapons, melee, pickups). Task A creates the spots and declares the
## interface; resolve() does nothing yet, so nothing is ever picked up.

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

func _on_server_start() -> void:
	for spot: PickupSpot in _spots:
		(spot.get_node("RollbackSynchronizer") as RollbackSynchronizer).process_settings()

## All spots in index order.
func spots() -> Array[PickupSpot]:
	return _spots

## Host only, called by the resolver once per tick after bots and objects have moved:
## give each spot's item to a bot standing on it and set the spot's ready_tick. Task C.
## bots are sorted by peer id. Writes state only.
@warning_ignore("unused_parameter")
func resolve(tick: int, bots: Array[Bot], cfg: TuningConfig) -> void:
	pass
