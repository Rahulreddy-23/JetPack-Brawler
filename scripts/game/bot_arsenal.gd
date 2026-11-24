class_name BotArsenal
extends Node
## Weapons and melee of one bot (child "Arsenal"). Rollback state, written by the
## bot's own tick on the client and on the host: whether the bot fires or swings at
## tick T is decided here from the fire and melee inputs, the ready ticks and ammo
## (architecture D5). The resolver only reads it.
##
## Owner: task C (weapons, melee, pickups). Task A only declares the state and the
## interface. _rollback_tick does nothing yet, so the bot never fires.

## Weapon slot in use: 0 is the rivet gun, 1 is the picked-up weapon.
var active_slot: int = 0
## ItemIds weapon id in slot 1, or ItemIds.NONE.
var picked_weapon: int = ItemIds.NONE
## Shots left in the picked-up weapon.
var picked_ammo: int = 0
## Tick (absolute) at which the next shot is allowed.
var fire_ready_tick: int = 0
## Tick at which the bot last fired, or -1.
var last_shot_tick: int = -1
## Counts shots. Never reset; effects compare it with the highest value seen.
var shots_fired: int = 0
## Aim direction of the last shot.
var shot_dir: Vector2 = Vector2.ZERO
## Tick (absolute) at which the next melee swing is allowed.
var melee_ready_tick: int = 0
## Tick of the last melee swing, or -1.
var last_melee_tick: int = -1
## Counts swings. Never reset; effects compare it with the highest value seen.
var melee_serial: int = 0

# Runs on the network tick after the bot's own movement (children run after the root). The
# bot's early return while knocked out does NOT stop this tick: it must do nothing while
# the bot's vitals.knocked_out is true (no firing, no swing, no swap, no state change).
# Task C: the bot is get_parent() as Bot; read its input.fire / melee / swap (clean them
# with Bot.clean_bool), write only the state above, read the config from
# MatchSettings.tuning_at(tick).
@warning_ignore("unused_parameter")
func _rollback_tick(delta: float, tick: int, is_fresh: bool) -> void:
	pass

## True if the bot fired at this tick.
func fired_at(tick: int) -> bool:
	return last_shot_tick == tick

## True if the bot swung at this tick.
func meleed_at(tick: int) -> bool:
	return last_melee_tick == tick

## ItemIds weapon id in use: the rivet gun in slot 0, otherwise the picked-up weapon.
func active_weapon() -> int:
	if active_slot == 0 or picked_weapon == ItemIds.NONE:
		return ItemIds.RIVET_GUN
	return picked_weapon

## Put a weapon into slot 1 with a full magazine. Task C.
@warning_ignore("unused_parameter")
func give_weapon(id: int, cfg: TuningConfig) -> void:
	pass

## Back to the rivet gun only, ready to fire. Task C fills in the ready ticks.
func reset_for_spawn(_cfg: TuningConfig) -> void:
	active_slot = 0
	picked_weapon = ItemIds.NONE
	picked_ammo = 0
