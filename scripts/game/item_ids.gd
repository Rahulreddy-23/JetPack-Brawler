class_name ItemIds
extends RefCounted
## Integer ids shared by state, config and rules. Plain ints on purpose: rollback
## state holds only ints, floats, bools and vectors.

## No item (an empty slot).
const NONE: int = -1

## Weapons. The id is also the index into TuningConfig.weapons.
const RIVET_GUN: int = 0
const BOLT_THROWER: int = 1
const SCRAP_BLASTER: int = 2
const ROCKET_TUBE: int = 3
const WEAPON_COUNT: int = 4

## Gadgets.
const COOKER_BOMB: int = 4
const SPRING_PLATE: int = 5

## Kinds of world object (the "kind" state of an object slot).
const OBJECT_ROCKET: int = 0
const OBJECT_BOMB: int = 1
const OBJECT_PLATE: int = 2
const OBJECT_KIND_COUNT: int = 3

static func is_weapon(id: int) -> bool:
	return id >= 0 and id < WEAPON_COUNT

static func is_gadget(id: int) -> bool:
	return id == COOKER_BOMB or id == SPRING_PLATE
