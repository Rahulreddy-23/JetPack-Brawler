class_name GadgetRules
extends RefCounted
## Host-side gadget and world-object rules, called by the CombatResolver once per tick
## (step 2): launches from gadget use, and everything every object does after launch: motion,
## wall and bot contact, arming, fuses, blasts and plate launches, for rockets as well as bombs
## and plates (a rocket's blast numbers come from cfg.weapons[ItemIds.ROCKET_TUBE]). Pure
## functions of state; they write only the state of world objects and append Hits. The slot
## range arithmetic is WorldObjects.slot_range; the dummy has none and never throws.
##
## Owner: task D (world objects and gadgets). Task A only fixes the signature;
## collect() adds no hits yet.

## Collect this tick's hits from bombs, blasts and plates. bots are sorted by peer id.
## solids are the arena's solid rectangles in pixels.
@warning_ignore("unused_parameter")
static func collect(tick: int, bots: Array[Bot], objects: WorldObjects, solids: Array[Rect2], cfg: TuningConfig, hits: Array[Hit]) -> void:
	pass
