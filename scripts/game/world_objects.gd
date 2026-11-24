class_name WorldObjects
extends Node2D
## The fixed pool of world-object slots ("Objects" in main.tscn): Obj0 to ObjN-1, created
## in _ready identically on every peer from the config, never freed. The pool holds
## max_players times the per-owner slot counts.
##
## Owner: task D (world objects and gadgets), except launch(), which task C calls for rockets.
## Task A creates the pool and fixes the interface; every function below except slots() and
## slot_range() does nothing yet.
##
## Who writes slot state (ruling 4):
## - A rocket is launched by task C (WeaponRules calls launch). From then on everything a
##   world object does is task D's: motion, wall and bot contact, arming, the fuse, the blast
##   and the hits it produces, for rockets as well as bombs and plates (D reads the rocket's
##   blast numbers from cfg.weapons[ItemIds.ROCKET_TUBE]). Bombs and plates are launched by D.
## - Task C never writes slot state directly. To find objects it calls targets_along and
##   targets_near; to knock one away it calls deflect; to shoot a plate it calls destroy.
##   Those three and launch are the only entry points, and all write state only.
## - The resolver order stays: WeaponRules, GadgetRules, pickups, CombatRules.
##
## Slot layout, with the dummy in mind (ruling 6): slots are grouped by owner slot, and inside
## one owner by kind in the order rocket, bomb, plate, with the per-owner counts from the
## config. The owner slot is the bot's slot index 0 to max_players - 1. The dummy bot's slot
## index is max_players: it has no range and never launches anything; slot_range() gives it
## a count of 0 and launch() must return null for it.

const SLOT_SCENE: PackedScene = preload("res://scenes/world_object.tscn")

var _slots: Array[WorldObject] = []

func _ready() -> void:
	# The pool size is fixed for the life of the process, so it reads the config once.
	var cfg: TuningConfig = MatchSettings.tuning_at(0)
	var per_owner: int = cfg.rocket_slots_per_owner + cfg.bomb_slots_per_owner + cfg.plate_slots_per_owner
	for i: int in cfg.max_players * per_owner:
		var slot: WorldObject = SLOT_SCENE.instantiate() as WorldObject
		slot.name = "Obj%d" % i
		add_child(slot)
		_slots.append(slot)
	# The slots are created once with the main scene, but netfox decides ownership when a
	# synchronizer registers, and re-registers only when this peer joins a game. Without this,
	# a phone that joined a game, left and then hosted would never send its slots' state.
	NetworkEvents.on_server_start.connect(_on_server_start)

func _on_server_start() -> void:
	for slot: WorldObject in _slots:
		(slot.get_node("RollbackSynchronizer") as RollbackSynchronizer).process_settings()

## All slots in index order.
func slots() -> Array[WorldObject]:
	return _slots

## The slots of one owner and kind as (first index, count) in slots(). Count is 0 for an owner
## slot outside 0 to max_players - 1 (the dummy's, or a bad value) and for a bad kind.
func slot_range(kind: int, owner_slot: int, cfg: TuningConfig) -> Vector2i:
	if owner_slot < 0 or owner_slot >= cfg.max_players or kind < 0 or kind >= ItemIds.OBJECT_KIND_COUNT:
		return Vector2i(0, 0)
	var counts: Array[int] = [cfg.rocket_slots_per_owner, cfg.bomb_slots_per_owner, cfg.plate_slots_per_owner]
	var per_owner: int = counts[0] + counts[1] + counts[2]
	var first: int = owner_slot * per_owner
	for earlier: int in kind:
		first += counts[earlier]
	return Vector2i(first, counts[kind])

## Launch an object (ItemIds.OBJECT_*) into the lowest free slot of the owner's range for this
## kind, or replace the slot with the oldest spawn_tick when the range is full. Returns the
## slot, or null if it could not be launched (including for the dummy's owner slot). Called by
## task C for rockets and by task D for bombs and plates. Task D fills it in. Writes state only.
@warning_ignore("unused_parameter")
func launch(kind: int, owner_slot: int, owner_peer: int, pos_px: Vector2, vel_px: Vector2, tick: int, cfg: TuningConfig) -> WorldObject:
	return null

## Every active bomb, rocket and plate whose shape the segment from a to b (global pixels)
## enters, nearest first (smallest t, ties to the lowest slot index). Used by task C's bullet
## cast, which orders the result against bots and walls by t. Round objects are circles of the
## config radius, the plate is a rectangle of the config size. Task D. Reads state only.
@warning_ignore("unused_parameter")
func targets_along(a: Vector2, b: Vector2, cfg: TuningConfig) -> Array[ObjectCast]:
	return []

## Every active object whose shape overlaps the circle (global pixels), in slot index order.
## Used by task C's melee arc, which then filters by angle. Task D. Reads state only.
@warning_ignore("unused_parameter")
func targets_near(center_px: Vector2, radius_px: float, cfg: TuningConfig) -> Array[WorldObject]:
	return []

## A melee swing or a bullet knocks a bomb or rocket away: set its velocity and make
## new_owner_peer (the deflector) its owner for credit and arming. Idempotent for the same
## tick. Ignores a slot that is not an active bomb or rocket. Task D. Writes state only.
@warning_ignore("unused_parameter")
func deflect(slot: WorldObject, new_velocity: Vector2, new_owner_peer: int, tick: int, cfg: TuningConfig) -> void:
	pass

## A bullet destroys a plate: make the slot inactive. Ignores a slot that is not an active
## plate. Task D. Writes state only.
@warning_ignore("unused_parameter")
func destroy(slot: WorldObject, tick: int) -> void:
	pass

## Make every slot inactive (round reset). Task D.
func reset() -> void:
	pass
