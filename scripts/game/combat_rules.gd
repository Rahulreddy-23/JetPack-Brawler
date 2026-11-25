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
##
## Rules added by task B:
## - THE PUSH RULE (push_change below; recoil follows it too). A push number is a DISTANCE in bot
##   heights, as in the GDD. On flat ground with a neutral stick, a push of P bot heights moves
##   the bot P bot heights, and distances ADD, within one tick and across ticks: the bot always
##   gets the launch speed for (the distance its present speed would still carry it under the
##   push window's braking) + (the new push), per axis, with signs. Hence:
##   - The bot's own speed counts as distance still to travel, whatever gave it: a bot running
##     into a push is slowed, and one running away from it goes a little further than P; a
##     push against an earlier push's motion takes that distance off; 30 bolts of 0.1 move a
##     bot 3.0, not the 10 or so that adding speeds would give.
##   - The low-health multiplier multiplies each push's distance (1 at 25 health or more, 2 at
##     0), so a bot at 0 health goes twice as far, not four times.
##   - Each axis is converted on its own: sideways against ground_brake x push_window_control,
##     up and down against gravity. Almost every blast has an upward part, so a blast lifts the
##     bot and the sideways travel that follows is the air figure, not the ground one (a push
##     of 2.5 at 45 degrees carried a grounded bot 6.2 bot heights sideways), and a diagonal
##     push is bent toward 45 degrees when the two decelerations are equal.
##   - In the air the same speed carries further because air braking is weaker ("momentum
##     carries"): about P x (ground_brake x window control / air_brake) x 1.4, about 5 P today.
##     The knob is push_window_control (lower it and pushes carry less in the air, at the cost
##     of a longer window).
##   - Distances add exactly only on the ground. An airborne bot slows far less between hits
##     than the ground window's braking the rule measures with, so pushes on separate ticks
##     still build on each other in the air (30 bolts: about 27 bot heights), bounded, and
##     tuned by the same knob. See docs/ARCHITECTURE.md D10.
##   - The window covers the bot's whole sideways speed, so a small sideways push on a running
##     bot opens a window of the full length for that speed.
##   - The window (push_window_ticks) is as long as it takes to brake the bot's sideways speed
##     away after a push or launch with a sideways part; a push with none (straight up, a plate)
##     opens no window and leaves the bot's steering alone.
## - A push (any kind, see Hit) that lands on a dashing bot ends its dash: the velocity first becomes
##   the dash exit velocity (dash_dir x dash_exit_speed), then the push is applied, and dash_left goes
##   to 0 (the cooldown stays). Otherwise the next dash tick would overwrite the push.
## - A launch (Hit.launch) replaces the victim's vertical velocity and adds its horizontal part.
## - The hits on one victim are sorted by a total order (attacker, damage, push x, push y, flags) before
##   they are summed, so float addition gives the same bits for any order of the input list.
## - Of several attackers in one tick, the one with the most combined damage on that victim is the
##   last attacker, then the one with the longest combined push, then the lowest peer id.
## - A hit with no damage and no push after cleaning (non-finite, negative damage) is not a hit.
## - The push window runs from the tick after the hit for as long as the bot's sideways speed takes
##   to brake away (push_window_ticks), so the full brake never cuts a push short.
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
	var distance: Vector2 = Vector2.ZERO  # summed push distances in bh, low-health multiplier applied
	var speed: Vector2 = Vector2.ZERO  # summed pushes that are already speeds (scale_push false), bh/s
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
		if flags & FLAG_LAUNCH != 0:
			launch_x += hit_push.x
			# Several launches in one tick: the most upward one wins, whatever the order.
			launch_y = minf(launch_y, hit_push.y) if launched else hit_push.y
			launched = true
		else:
			if flags & FLAG_SCALE != 0:
				hit_push *= multiplier
				distance += hit_push
			else:
				speed += hit_push
		damage += hit_damage
		if peer != Bot.NO_PEER and not own:
			var total: Vector2 = from_peer.get(peer, Vector2.ZERO)
			from_peer[peer] = total + Vector2(hit_damage, hit_push.length())
	vitals.hits_taken += 1
	var launch: Vector2 = Vector2(launch_x, launch_y) if launched else Vector2.ZERO
	# Effects read the length and direction only: distance in bh, plus a launch's speed.
	vitals.last_hit_push = distance + speed + launch
	vitals.last_hit_damage = damage
	vitals.health = maxf(vitals.health - damage, 0.0)
	if launched or distance != Vector2.ZERO or speed != Vector2.ZERO:
		var previous_speed: float = victim.velocity.x / cfg.bot_height_px
		if _push(victim, distance, speed, launch, launched, cfg):
			vitals.push_until_tick = push_window_end_tick(tick, vitals.push_until_tick, previous_speed, victim.velocity.x / cfg.bot_height_px, cfg)
	# An attack stamped later than this tick (only a bug could leave one) is never replaced.
	if not from_peer.is_empty() and tick >= vitals.last_attack_tick:
		vitals.last_attacker = _strongest(from_peer)
		vitals.last_attack_tick = tick
	return vitals.health <= 0.0

## The velocity change in bh/s that gives a bot moving at `velocity` (bh/s) a push of `distance`
## bot heights (the sum of one tick's distance vectors), see THE PUSH RULE in the header. Per
## axis the new speed is the launch speed for the distance the bot's present speed would still
## carry it (signed) plus the push, so distances add across ticks; an axis with no push is left
## alone. Sideways the braking is the window's (ground_brake x push_window_control), up and down
## it is gravity (a falling bot counts as distance still to fall, so an upward push cancels it
## first). Pure function of the velocity, the distance and the config: the same on
## re-simulation and on host and client.
static func push_change(velocity: Vector2, distance: Vector2, cfg: TuningConfig) -> Vector2:
	var dt: float = 1.0 / float(cfg.tick_rate)
	return Vector2(
		_axis_change(velocity.x, distance.x, cfg.ground_brake * cfg.push_window_control, dt),
		_axis_change(velocity.y, distance.y, cfg.gravity, dt))

static func _axis_change(speed: float, push: float, decel: float, dt: float) -> float:
	if push == 0.0:
		return 0.0
	var net: float = signf(speed) * CombatMath.travel_distance(absf(speed), decel, dt) + push
	return signf(net) * CombatMath.launch_speed(absf(net), decel, dt) - speed

## Ticks, counted from the tick after the push, for which braking and steering stay reduced: the
## time the window's braking needs to take a sideways speed (bh/s) away. Only sideways control is
## ever reduced, so only the sideways speed sizes it.
static func push_window_ticks(sideways_speed: float, cfg: TuningConfig) -> int:
	var dt: float = 1.0 / float(cfg.tick_rate)
	return ceili(absf(sideways_speed) / (cfg.ground_brake * cfg.push_window_control * dt) - 0.0001)

## Resize an existing window when a push reduces sideways speed. If speed grows, keep at least
## the time already left in the window. Both speeds are in bot heights per second.
static func push_window_end_tick(tick: int, previous_end: int, previous_speed: float, sideways_speed: float, cfg: TuningConfig) -> int:
	var end: int = tick + 1 + push_window_ticks(sideways_speed, cfg)
	if absf(sideways_speed) < absf(previous_speed):
		return end
	return maxi(previous_end, end)

# A push first ends a dash (the velocity becomes what a dash exit gives), then a launch replaces
# the vertical velocity and adds its horizontal part, then the ordinary pushes are added on top of
# the velocity the bot has by then. Returns true when the push or launch has a sideways part, which
# is what opens the push window.
static func _push(victim: Bot, distance: Vector2, speed: Vector2, launch: Vector2, launched: bool, cfg: TuningConfig) -> bool:
	var px: float = cfg.bot_height_px
	if victim.dash_left > 0.0:
		victim.finish_dash(cfg)
	if launched:
		victim.velocity = Vector2(victim.velocity.x + launch.x * px, launch.y * px)
	var change: Vector2 = push_change(victim.velocity / px, distance, cfg) + speed
	victim.velocity += change * px
	return change.x != 0.0 or launch.x != 0.0

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
