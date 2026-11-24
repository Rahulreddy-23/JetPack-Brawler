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
## Owner: task B (combat core). The host's CombatRules write the state; this node's own
## tick brings a knocked-out bot back (respawn) and restarts the phase 1 test cycle.

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

## Number of the phase 1 hazard cycle this bot has been reset for (0 is the first cycle). A bot
## is reset on the first tick it runs in a later cycle, so a skipped tick cannot lose a reset.
var cycle_index: int = 0

## Where this bot returns to on a respawn, global pixels. Set once by the spawner; not state.
var spawn_position: Vector2 = Vector2.ZERO

@onready var _bot: Bot = get_parent() as Bot

# Runs on the network tick after the bot's own movement (children run after the root, and
# the bot's early return while knocked out leaves its movement state alone). Brings the bot
# back at its respawn tick, and resets every bot on the first tick it runs in a later phase 1
# hazard cycle. Writes only registered state, reads the config through
# MatchSettings.tuning_at(tick).
@warning_ignore("unused_parameter")
func _rollback_tick(delta: float, tick: int, is_fresh: bool) -> void:
	var cfg: TuningConfig = MatchSettings.tuning_at(tick)
	var cycle: int = _cycle_number(tick, cfg)
	var cycle_behind: bool = cycle > cycle_index
	if cycle_behind:
		cycle_index = cycle
	if cycle_behind or (knocked_out and tick >= respawn_tick):
		_respawn(cfg)

# Which hazard cycle a tick is in (0 for the first), or -1 before a round has started.
func _cycle_number(tick: int, cfg: TuningConfig) -> int:
	var length: int = roundi(cfg.hazard_cycle_time * float(cfg.tick_rate))
	if MatchSettings.round_start_tick < 0 or tick < MatchSettings.round_start_tick or length <= 0:
		return -1
	@warning_ignore("integer_division")
	return (tick - MatchSettings.round_start_tick) / length

# Back at the spawn point with full health, fuel and no movement state; weapons and gadgets
# go back to their starting kit.
func _respawn(cfg: TuningConfig) -> void:
	_bot.global_position = spawn_position
	_bot.velocity = Vector2.ZERO
	_bot.fuel = cfg.fuel_capacity
	_bot.thrust_level = 0.0
	_bot.dash_left = 0.0
	_bot.dash_cooldown_left = 0.0
	_bot.dash_dir = Vector2.ZERO
	_bot.jet_buffer = 0.0
	_bot.jet_held_prev = false
	_bot.dash_buffer = 0.0
	_bot.wall_grace_left = 0.0
	_bot.wall_nx = 0
	_bot.facing = 1
	_bot.drop_left = 0.0
	_bot.aim_dir = Vector2.RIGHT
	reset_for_spawn(cfg)
	_bot.arsenal.reset_for_spawn(cfg)
	_bot.gadgets.reset_for_spawn(cfg)

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
