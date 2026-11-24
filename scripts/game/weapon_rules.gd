class_name WeaponRules
extends RefCounted
## Host-side weapon rules, called by the CombatResolver once per tick (step 1).
## Pure functions of state: they read bots, objects and solids and append Hits and send no
## RPC. Task C launches rockets through WorldObjects.launch and never writes slot state
## itself: it finds bombs, rockets and plates with WorldObjects.targets_along (bullet casts) and
## targets_near (melee arc), knocks bombs and rockets away with WorldObjects.deflect, and
## shoots plates with WorldObjects.destroy. Everything a rocket does after launch (flight,
## contact, blast, hits) is task D's, in GadgetRules. The dummy never fires.
##
## Owner: task C (weapons, melee, pickups). Task A only fixes the signature;
## collect() adds no hits yet.

## Collect this tick's hits from shots and melee (not rocket contacts: those are task D's). bots are sorted by
## peer id. solids are the arena's solid rectangles in pixels.
@warning_ignore("unused_parameter")
static func collect(tick: int, bots: Array[Bot], objects: WorldObjects, solids: Array[Rect2], cfg: TuningConfig, hits: Array[Hit]) -> void:
	pass
