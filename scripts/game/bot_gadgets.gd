class_name BotGadgets
extends Node
## Gadget inventory of one bot (child "Gadgets"). Rollback state, written by the bot's
## own tick on the client and on the host, like BotArsenal.
##
## Owner: task D (world objects and gadgets). Task A only declares the state and the
## interface. _rollback_tick does nothing yet, so no gadget is ever used.

## ItemIds gadget id in the first slot, or ItemIds.NONE. This is the one thrown next.
var gadget_a: int = ItemIds.NONE
## ItemIds gadget id in the second slot, or ItemIds.NONE.
var gadget_b: int = ItemIds.NONE
## Tick (absolute) at which the next gadget use is allowed.
var gadget_ready_tick: int = 0
## Tick at which a gadget was last used, or -1.
var last_gadget_tick: int = -1
## ItemIds gadget id used at last_gadget_tick, or ItemIds.NONE. Not in the architecture's
## state table: used_id() needs it, because the gadget is consumed in the same tick.
var last_gadget_id: int = ItemIds.NONE
## Throw or placement direction of the last use.
var gadget_dir: Vector2 = Vector2.ZERO
## Counts uses. Never reset; effects compare it with the highest value seen.
var gadget_serial: int = 0

# Runs on the network tick after the bot's own movement. The bot's early return while knocked
# out does NOT stop this tick: it must do nothing while the bot's vitals.knocked_out is true
# (no use, no state change). Task D: the bot is
# get_parent() as Bot; read its input.gadget (clean it with Bot.clean_bool), write only
# the state above, read the config from MatchSettings.tuning_at(tick).
@warning_ignore("unused_parameter")
func _rollback_tick(delta: float, tick: int, is_fresh: bool) -> void:
	pass

## True if a gadget was used at this tick.
func used_at(tick: int) -> bool:
	return last_gadget_tick == tick

## ItemIds gadget id used at the last use.
func used_id() -> int:
	return last_gadget_id

## Put a gadget into the first free slot. False when both slots are full. Task D.
@warning_ignore("unused_parameter")
func give(id: int) -> bool:
	return false

## Empty hands. Task D gives the starting Cooker Bomb here.
func reset_for_spawn(_cfg: TuningConfig) -> void:
	gadget_a = ItemIds.NONE
	gadget_b = ItemIds.NONE
