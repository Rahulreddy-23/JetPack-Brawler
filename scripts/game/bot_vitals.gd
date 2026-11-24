class_name BotVitals
extends Node
## Health and knockout state of one bot (child "Vitals"). All of these are rollback
## state properties (see bot.tscn), written only by the host's CombatResolver
## (CombatRules, task B) and read by the bot and by presentation.
##
## The phase 1 dummy bot is a normal bot with peer_id Bot.DUMMY_PEER (0, never -1 which is
## Bot.NO_PEER), slot index TuningConfig.max_players (never given to a player, grey, not counted
## against max_players) and input.dummy set; task B spawns it, with the server as the input
## authority. Task A does not spawn it.
##
## Owner: task B (combat core). Task A only declares the state and the interface;
## the values never change yet, so the game plays as before.

## Current health. GDD: 100, no regeneration.
var health: float = 0.0
## True from the knockout until the respawn.
var knocked_out: bool = false
## Tick at which the bot respawns (absolute).
var respawn_tick: int = 0
## Counts knockouts of this bot. Never reset; effects compare it with the highest value seen.
var ko_serial: int = 0
## Counts hits taken. Never reset; effects compare it with the highest value seen.
var hits_taken: int = 0
## Push of the last hit, bh/s, after scaling.
var last_hit_push: Vector2 = Vector2.ZERO
## Damage of the last hit.
var last_hit_damage: float = 0.0
## Peer id of the last attacker, or Bot.NO_PEER.
var last_attacker: int = Bot.NO_PEER
## Tick of the last hit or push; the credit window counts from here.
var last_attack_tick: int = -1
## Knockouts this bot has scored.
var knockouts: int = 0
## Until this tick (absolute) a pushed bot keeps its push: ground braking and steering
## are reduced (push window). Set by task B when a push lands; the movement side is in Bot.
var push_until_tick: int = 0

## True while the bot is knocked out.
func is_out() -> bool:
	return knocked_out

## Put the bot in its starting condition: full health, not knocked out, no push window.
## The counters (ko_serial, hits_taken, knockouts) keep counting.
func reset_for_spawn(cfg: TuningConfig) -> void:
	health = cfg.max_health
	knocked_out = false
	push_until_tick = 0
	last_attacker = Bot.NO_PEER
	last_attack_tick = -1
