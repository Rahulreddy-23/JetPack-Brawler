class_name PickupSpot
extends Node2D
## One fixed pickup spot (Pickups/SpotN, scenes/pickup_spot.tscn): created once on every
## peer, owned by the host, never freed. Which item it offers comes from the arena layout
## (item), which never changes; whether it is on offer is the state ready_tick.
##
## Owner: task C (weapons, melee, pickups). Task A only declares the state and the scene.

## ItemIds value offered here. Set once when the spot is created, from the layout.
var item: int = ItemIds.NONE
## Tick (absolute) from which the item is on offer; a bot takes it when tick >= ready_tick.
var ready_tick: int = 0
