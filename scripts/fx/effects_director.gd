class_name EffectsDirector
extends Node
## Turns the state counters of bots and objects into one-shot effects on this phone
## ("Effects" in main.tscn). For each counter (hits_taken, ko_serial, shots_fired,
## melee_serial, gadget_serial, launches, blasts) it keeps the highest value seen per
## node, triggers once per increase, and records without triggering the first time it
## sees a node (architecture D7). It never writes a simulation property.
##
## Owner: task E (presentation). Task A only creates the node and its references, so
## the scene wiring is in place; the director does nothing yet.

## Where parts fly. Show physics only; it is not under a bot, so the parts outlive it.
@export var burst: PartsBurst
## Screen shake on the camera.
@export var shake: ScreenShake
## The rising metal; task E drives it from MatchSettings.hazard_ticks.
@export var hazard_visual: HazardVisual
## The arena layout: floor (bounds.end.y), width and x position of the metal, and hazard_top.
@export var layout: ArenaLayout
## The pool of world objects, for rocket and blast effects.
@export var objects: WorldObjects
## Effect numbers (debris, shake, hit freeze and flash) are in TuningConfig, group
## "Effects"; task E applies them to burst and shake here.
