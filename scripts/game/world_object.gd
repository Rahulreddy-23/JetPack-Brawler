class_name WorldObject
extends Node2D
## One slot of the world-object pool: a rocket, a Cooker Bomb or a Spring Plate
## (scenes/world_object.tscn). The slot is created once on every peer, owned by the host,
## never freed, reparented or queue-freed; an unused slot is state (active = false), not
## absence. Objects move on the host only; clients display the host's state.
##
## Owner: task D (world objects and gadgets). Task A only declares the state and the
## scene. _rollback_tick does nothing yet, so every slot stays inactive.
## Shapes (task D): a bomb and a rocket are circles (bomb_radius, the rocket's projectile_radius,
## both in bot heights); a plate is the rectangle plate_size centred on global_position.

## True while the slot holds a live object.
var active: bool = false
## ItemIds.OBJECT_ROCKET, OBJECT_BOMB or OBJECT_PLATE; meaningful while active.
var kind: int = ItemIds.NONE
## Peer id of the owner (credit and arming), or Bot.NO_PEER.
var owner_peer: int = Bot.NO_PEER
## Velocity in pixels per second.
var velocity: Vector2 = Vector2.ZERO
## Tick (absolute) at which the object was launched. The oldest spawn_tick is replaced
## when no slot is free.
var spawn_tick: int = 0
## Tick (absolute) from which a plate or mine can trigger.
var arm_tick: int = 0
## Tick (absolute) at which a bomb's fuse ends.
var fuse_tick: int = 0
## Tick (absolute) at which the object exploded, or -1.
var explode_tick: int = -1
## True once the object has come to rest on a surface.
var landed: bool = false
## Counts launches into this slot. Never reset; effects compare it with the highest value seen.
var launches: int = 0
## Counts blasts of this slot. Never reset; effects compare it with the highest value seen.
var blasts: int = 0

# netfox runs this on EVERY peer for this inputless slot, not only on its owner. Rule for
# task D: move and change state only where is_multiplayer_authority() is true (the host), and
# leave an inactive slot (active == false) completely unchanged on every peer. Clients get
# the host's state by synchronization. Write only the state above, read the config from
# MatchSettings.tuning_at(tick). Everything a slot does is task D's, rockets included; task C
# only launches rockets and reaches slots through WorldObjects (launch, targets_along,
# targets_near, deflect, destroy).
@warning_ignore("unused_parameter")
func _rollback_tick(delta: float, tick: int, is_fresh: bool) -> void:
	pass
