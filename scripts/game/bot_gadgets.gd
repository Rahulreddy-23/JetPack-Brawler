class_name BotGadgets
extends Node
## Gadget inventory of one bot (child "Gadgets"). Rollback state, written by the bot's
## own tick on the client and on the host, like BotArsenal.
##
## Owner: task D (world objects and gadgets). The thrown object itself is made by
## GadgetRules (used_at) on the host.

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
# out does NOT stop this tick, so it checks itself: while the bot's vitals.knocked_out is true
# there is no use and no state change. The gadget input is a one-tick pulse (task F latches
# it), and gadget_ready_tick keeps a pulse that netfox repeats for a late input from
# throwing twice.
func _rollback_tick(_delta: float, tick: int, _is_fresh: bool) -> void:
	var bot: Bot = get_parent() as Bot
	if bot.vitals.knocked_out or not Bot.clean_bool(bot.input.gadget):
		return
	if gadget_a == ItemIds.NONE or tick < gadget_ready_tick:
		return
	var cfg: TuningConfig = MatchSettings.tuning_at(tick)
	var aim: Vector2 = Bot.clean_vector(bot.input.aim)
	last_gadget_id = gadget_a
	last_gadget_tick = tick
	gadget_dir = aim.normalized() if aim.length() > cfg.stick_deadzone else Vector2(bot.facing, 0.0)
	gadget_serial += 1
	gadget_ready_tick = tick + WorldObjects.seconds_to_ticks(cfg.gadget_cooldown, cfg)
	gadget_a = gadget_b
	gadget_b = ItemIds.NONE

## True if a gadget was used at this tick.
func used_at(tick: int) -> bool:
	return last_gadget_tick == tick

## ItemIds gadget id used at the last use.
func used_id() -> int:
	return last_gadget_id

## Put a gadget into the first free slot. False when both slots are full or id is not a gadget.
func give(id: int) -> bool:
	if not ItemIds.is_gadget(id):
		return false
	if gadget_a == ItemIds.NONE:
		gadget_a = id
	elif gadget_b == ItemIds.NONE:
		gadget_b = id
	else:
		return false
	return true

## Start of a life: one Cooker Bomb, ready to throw.
func reset_for_spawn(_cfg: TuningConfig) -> void:
	gadget_a = ItemIds.COOKER_BOMB
	gadget_b = ItemIds.NONE
	gadget_ready_tick = 0
