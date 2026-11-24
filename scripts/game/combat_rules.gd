class_name CombatRules
extends RefCounted
## Host-side damage rules, called by the CombatResolver once per tick (step 4): apply the
## collected hits to the bots' Vitals (health, push, credit, knockout, repair, respawn)
## and the hazard knockouts, all idempotently from the restored state of the tick.
##
## Owner: task B (combat core). Task A only fixes the signature; apply() changes nothing yet.

## Rules fixed by task A for task B:
## - Credit: a knockout is credited to vitals.last_attacker only when
##   0 <= tick - last_attack_tick <= credit window in ticks (cfg.credit_window x tick_rate);
##   a negative difference (an attack stamped after this tick, seen on a re-run) never credits.
## - The dummy (Bot.DUMMY_PEER, slot cfg.max_players) takes hits and is knocked out like any bot;
##   it never fires, throws or picks up. Never use -1 (Bot.NO_PEER) for it.
## - A push is a velocity change of push x cfg.push_speed_scale bh/s (recoil too), then the
##   low-health multiplier on the victim's side.

## Apply this tick's hits. bots are sorted by peer id, never tree order, so the result
## does not depend on which hit was found first.
@warning_ignore("unused_parameter")
static func apply(tick: int, bots: Array[Bot], hits: Array[Hit], layout: ArenaLayout, cfg: TuningConfig) -> void:
	pass
