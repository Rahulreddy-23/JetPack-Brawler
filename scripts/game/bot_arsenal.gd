class_name BotArsenal
extends Node
## Weapons and melee of one bot (child "Arsenal"). Rollback state, written by the
## bot's own tick on the client and on the host: whether the bot fires or swings at
## tick T is decided here from the fire and melee inputs, the ready ticks and ammo
## (architecture D5). The resolver only reads it.
##
## Owner: task C (weapons, melee, pickups).

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

# Runs on the network tick after the bot's own movement (children run after the root), on the
# shooter's phone and on the host. Does nothing while the bot is knocked out. Swap and melee
# are read as the one-tick pulses the input node documents; a stale input repeated on the host
# is corrected by the rollback when the real input arrives. Writes only the state above and the
# shooter's own velocity and push window (recoil).
func _rollback_tick(_delta: float, tick: int, _is_fresh: bool) -> void:
	var bot: Bot = get_parent() as Bot
	if bot.vitals.knocked_out:
		return
	var cfg: TuningConfig = MatchSettings.tuning_at(tick)
	# A picked weapon that ran dry is dropped one tick after its last shot, so the resolver
	# still sees which weapon fired.
	if picked_weapon != ItemIds.NONE and picked_ammo <= 0:
		picked_weapon = ItemIds.NONE
		active_slot = 0
	var dir: Vector2 = bot.input_aim_direction(cfg)
	if Bot.clean_bool(bot.input.swap) and picked_weapon != ItemIds.NONE:
		active_slot = 1 - active_slot
	# There is no separate melee direction in the state: the swing uses shot_dir, which a shot
	# on the same tick sets to the same value.
	if Bot.clean_bool(bot.input.melee) and tick >= melee_ready_tick:
		last_melee_tick = tick
		melee_serial += 1
		melee_ready_tick = tick + WeaponRules.seconds_to_ticks(cfg.melee_cooldown, cfg)
		shot_dir = dir
	if Bot.clean_bool(bot.input.fire) and tick >= fire_ready_tick:
		_fire(bot, dir, tick, cfg)

func _fire(bot: Bot, dir: Vector2, tick: int, cfg: TuningConfig) -> void:
	var stats: WeaponStats = cfg.weapon_stats(active_weapon())
	if stats == null or (not stats.infinite_ammo and picked_ammo <= 0):
		return
	last_shot_tick = tick
	shots_fired += 1
	shot_dir = dir
	fire_ready_tick = tick + WeaponRules.seconds_to_ticks(stats.fire_interval, cfg)
	if not stats.infinite_ammo:
		picked_ammo -= 1
	# Recoil is the shooter's own predicted movement, like every other push, so it also opens
	# the push window (otherwise ground braking removes it before the bot has moved).
	if stats.recoil > 0.0:
		if bot.dash_left > 0.0:
			bot.finish_dash(cfg)
		bot.velocity -= dir * stats.recoil * cfg.push_speed_scale * cfg.bot_height_px
		bot.vitals.push_until_tick = maxi(bot.vitals.push_until_tick, tick + 1 + WeaponRules.seconds_to_ticks(cfg.push_window_time, cfg))

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

## Put a weapon into slot 1 with a full magazine and equip it, replacing any picked weapon.
## The rivet gun and anything that is not a weapon are ignored.
func give_weapon(id: int, cfg: TuningConfig) -> void:
	var stats: WeaponStats = cfg.weapon_stats(id)
	if id == ItemIds.RIVET_GUN or stats == null:
		return
	picked_weapon = id
	picked_ammo = stats.ammo
	active_slot = 1

## Back to the rivet gun only, everything ready.
func reset_for_spawn(_cfg: TuningConfig) -> void:
	active_slot = 0
	picked_weapon = ItemIds.NONE
	picked_ammo = 0
	fire_ready_tick = 0
	last_shot_tick = -1
	melee_ready_tick = 0
	last_melee_tick = -1
