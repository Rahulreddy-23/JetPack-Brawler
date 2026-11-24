class_name CombatRules
extends RefCounted
## Host-side damage rules, called by the CombatResolver once per tick (step 4): apply the
## collected hits to the bots' Vitals (health, push, credit, knockout, repair)
## and the hazard knockouts, all idempotently from the restored state of the tick.
## Respawn is not here: it is BotVitals' own tick.
##
## Owner: task B (combat core).
##
## Rules fixed by task A for task B:
## - Credit: a knockout is credited to vitals.last_attacker only when
##   0 <= tick - last_attack_tick <= credit window in ticks (cfg.credit_window x tick_rate);
##   a negative difference (an attack stamped after this tick, seen on a re-run) never credits.
## - The dummy (Bot.DUMMY_PEER, slot cfg.max_players) takes hits and is knocked out like any bot;
##   it never fires, throws or picks up. Never use -1 (Bot.NO_PEER) for it.
## - A push is a velocity change of push x cfg.push_speed_scale bh/s (recoil too), then the
##   low-health multiplier on the victim's side.
##
## Rules added by task B:
## - A push (any kind, see Hit) that lands on a dashing bot ends its dash: the velocity first becomes
##   the dash exit velocity (dash_dir x dash_exit_speed), then the push is applied, and dash_left goes
##   to 0 (the cooldown stays). Otherwise the next dash tick would overwrite the push.
## - A launch (Hit.launch) replaces the victim's vertical velocity and adds its horizontal part.
## - The hits on one victim are sorted by a total order (attacker, damage, push x, push y, flags) before
##   they are summed, so float addition gives the same bits for any order of the input list.
## - Of several attackers in one tick, the one with the most combined damage on that victim is the
##   last attacker, then the one with the longest combined push, then the lowest peer id.
## - A hit with no damage and no push after cleaning (non-finite, negative damage) is not a hit.
## - The push window runs from the tick after the hit for cfg.push_window_time.
## - A bot is never moved here: a knocked-out bot stays where it was until its respawn moves it.
## - Phase 1 test cycle: a bot knocked out at or after the hazard's start time in a cycle, or whose
##   respawn delay would end at or after that time, respawns at the start of the next cycle.

const CombatMath := preload("res://combat/combat_math.gd")
const HazardMath := preload("res://hazard/hazard_math.gd")
const FLAG_BULLET: int = 1
const FLAG_SCALE: int = 2
const FLAG_LAUNCH: int = 4

## Apply this tick's hits. bots are sorted by peer id, never tree order, so the result
## does not depend on which hit was found first.
static func apply(tick: int, bots: Array[Bot], hits: Array[Hit], layout: ArenaLayout, cfg: TuningConfig) -> void:
	var live: Array[Bot] = []
	for bot: Bot in bots:
		if not bot.vitals.knocked_out:
			live.append(bot)
	var out: Array[Bot] = []
	for victim: Bot in live:
		if _apply_hits(tick, victim, hits, cfg) or _in_metal(tick, victim, layout, cfg):
			out.append(victim)
	_credit_and_repair(tick, bots, out, cfg)
	var respawn_tick: int = _respawn_tick(tick, cfg)
	for victim: Bot in out:
		var vitals: BotVitals = victim.vitals
		vitals.health = 0.0
		vitals.knocked_out = true
		vitals.ko_serial += 1
		vitals.respawn_tick = respawn_tick

# The tick at which a bot knocked out at this tick comes back (phase 1 test cycle).
static func _respawn_tick(tick: int, cfg: TuningConfig) -> int:
	var back: int = tick + roundi(cfg.respawn_time * float(cfg.tick_rate))
	var into_cycle: int = MatchSettings.hazard_ticks(tick)
	var cycle: int = roundi(cfg.hazard_cycle_time * float(cfg.tick_rate))
	if into_cycle < 0 or cycle <= 0:
		return back
	var hazard_start: int = roundi(cfg.hazard_start_time * float(cfg.tick_rate))
	if into_cycle >= hazard_start or into_cycle + (back - tick) >= hazard_start:
		return tick - into_cycle + cycle
	return back

# One hit as it is summed: [attacker, damage, push x, push y, flags]. Cleaned of non-finite values.
static func _entry(hit: Hit) -> Array:
	var damage: float = hit.damage if is_finite(hit.damage) and hit.damage > 0.0 else 0.0
	var push: Vector2 = hit.push if hit.push.is_finite() else Vector2.ZERO
	var flags: int = (FLAG_BULLET if hit.bullet else 0) | (FLAG_SCALE if hit.scale_push else 0) | (FLAG_LAUNCH if hit.launch else 0)
	return [hit.attacker_peer, damage, push.x, push.y, flags]

static func _entry_less(a: Array, b: Array) -> bool:
	for i: int in a.size():
		if a[i] != b[i]:
			return a[i] < b[i]
	return false

# Combine this tick's hits on one live victim and write the result. Returns true when the
# damage brought its health to zero.
static func _apply_hits(tick: int, victim: Bot, hits: Array[Hit], cfg: TuningConfig) -> bool:
	var vitals: BotVitals = victim.vitals
	var dashing: bool = victim.dash_left > 0.0
	var multiplier: float = CombatMath.push_multiplier(vitals.health, cfg.low_health_threshold, cfg.low_health_push_multiplier)
	var entries: Array[Array] = []
	for hit: Hit in hits:
		if hit.victim == victim and not (hit.bullet and dashing):
			var entry: Array = _entry(hit)
			if (entry[1] as float) != 0.0 or entry[2] != 0.0 or entry[3] != 0.0:
				entries.append(entry)
	if entries.is_empty():
		return false
	entries.sort_custom(_entry_less)
	var damage: float = 0.0
	var speed: Vector2 = Vector2.ZERO  # velocity change in bh/s from ordinary pushes
	var launch_x: float = 0.0
	var launch_y: float = 0.0
	var launched: bool = false
	# Per attacker peer: [damage, push length] of this tick, for the last-attacker choice.
	var from_peer: Dictionary[int, Vector2] = {}
	for entry: Array in entries:
		var peer: int = entry[0]
		var hit_damage: float = entry[1]
		var hit_push: Vector2 = Vector2(entry[2] as float, entry[3] as float)
		var flags: int = entry[4]
		var own: bool = peer == victim.peer_id
		if own:
			hit_damage *= cfg.self_damage_scale
		var hit_speed: Vector2 = hit_push
		if flags & FLAG_LAUNCH != 0:
			launch_x += hit_push.x
			# Several launches in one tick: the most upward one wins, whatever the order.
			launch_y = minf(launch_y, hit_push.y) if launched else hit_push.y
			launched = true
		else:
			if flags & FLAG_SCALE != 0:
				hit_speed = hit_push * cfg.push_speed_scale * multiplier
			speed += hit_speed
		damage += hit_damage
		if peer != Bot.NO_PEER and not own:
			var total: Vector2 = from_peer.get(peer, Vector2.ZERO)
			from_peer[peer] = total + Vector2(hit_damage, hit_speed.length())
	vitals.hits_taken += 1
	var launch: Vector2 = Vector2(launch_x, launch_y) if launched else Vector2.ZERO
	vitals.last_hit_push = speed + launch
	vitals.last_hit_damage = damage
	vitals.health = maxf(vitals.health - damage, 0.0)
	if launched or speed != Vector2.ZERO:
		_push(victim, speed, launch, launched, cfg)
		vitals.push_until_tick = maxi(vitals.push_until_tick, tick + 1 + roundi(cfg.push_window_time * float(cfg.tick_rate)))
	# An attack stamped later than this tick (only a bug could leave one) is never replaced.
	if not from_peer.is_empty() and tick >= vitals.last_attack_tick:
		vitals.last_attacker = _strongest(from_peer)
		vitals.last_attack_tick = tick
	return vitals.health <= 0.0

# A push first ends a dash (the velocity becomes what a dash exit gives), then a launch replaces
# the vertical velocity and adds its horizontal part, then the ordinary pushes are added.
static func _push(victim: Bot, speed: Vector2, launch: Vector2, launched: bool, cfg: TuningConfig) -> void:
	var px: float = cfg.bot_height_px
	if victim.dash_left > 0.0:
		victim.finish_dash(cfg)
	if launched:
		victim.velocity = Vector2(victim.velocity.x + launch.x * px, launch.y * px)
	victim.velocity += speed * px

# The peer with the largest [damage, push] total; ties go to the lowest peer id.
static func _strongest(from_peer: Dictionary[int, Vector2]) -> int:
	var best: int = Bot.NO_PEER
	var best_total: Vector2 = Vector2.ZERO
	for peer: int in from_peer:
		var total: Vector2 = from_peer[peer]
		var better: bool = best == Bot.NO_PEER or total.x > best_total.x \
			or (total.x == best_total.x and (total.y > best_total.y or (total.y == best_total.y and peer < best)))
		if better:
			best = peer
			best_total = total
	return best

static func _in_metal(tick: int, victim: Bot, layout: ArenaLayout, cfg: TuningConfig) -> bool:
	var px: float = cfg.bot_height_px
	return HazardMath.is_in_metal(victim.body_rect().end.y, MatchSettings.hazard_ticks(tick), cfg.tick_rate,
		cfg.hazard_start_time, cfg.hazard_cap_time, layout.hazard_floor_px(px), layout.hazard_top_px(px))

# Credit every knockout of the tick first, then repair, so a trade (both out on one tick)
# credits both attackers and repairs neither.
static func _credit_and_repair(tick: int, bots: Array[Bot], out: Array[Bot], cfg: TuningConfig) -> void:
	var window: int = roundi(cfg.credit_window * float(cfg.tick_rate))
	var credited: Array[Bot] = []
	for victim: Bot in out:
		var age: int = tick - victim.vitals.last_attack_tick
		if victim.vitals.last_attacker == Bot.NO_PEER or age < 0 or age > window:
			continue
		for bot: Bot in bots:
			if bot.peer_id == victim.vitals.last_attacker and bot != victim:
				credited.append(bot)
	for attacker: Bot in credited:
		attacker.vitals.knockouts += 1
		if not out.has(attacker) and not attacker.vitals.knocked_out:
			attacker.vitals.health = minf(attacker.vitals.health + cfg.knockout_repair, cfg.max_health)
