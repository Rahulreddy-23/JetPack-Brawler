extends Node
## Headless test of CombatRules.apply and of the respawn in BotVitals, on instanced bots with
## hand-built hit lists (task B). It also holds the rules ported from the retired
## combat_ledger and fighter_health tests. It opens no socket. Run:
##   godot --headless --path . res://tests/test_combat_rules.tscn
## Exits 0 when every check passes, 1 otherwise. Numbers come from the shared config; only the
## GDD's multiplier points (1 at 25 health, 2 at 0) are written here.

const BOT_SCENE: PackedScene = preload("res://scenes/bot.tscn")
const LAYOUT: ArenaLayout = preload("res://config/smelter.tres")
const HazardMath := preload("res://hazard/hazard_math.gd")
const TIMEOUT_SECONDS: float = 60.0
const EPS: float = 0.001
const NO_ONE: int = Bot.NO_PEER

var _cfg: TuningConfig = TuningConfig.get_default()
var _px: float = 0.0
var _dt: float = 0.0
var _window: int = 0
var _failures: int = 0
var _checks: int = 0
var _arena: Node2D = null
var _state_paths: Array[String] = []

func _ready() -> void:
	get_tree().create_timer(TIMEOUT_SECONDS).timeout.connect(func() -> void:
		print("FAIL timeout, the test did not finish")
		get_tree().quit(1))
	_run()

func _run() -> void:
	_px = _cfg.bot_height_px
	_dt = 1.0 / float(_cfg.tick_rate)
	_window = roundi(_cfg.credit_window * float(_cfg.tick_rate))
	_arena = Node2D.new()
	add_child(_arena)
	var probe: Bot = _bot(1)
	_state_paths.assign((probe.get_node("RollbackSynchronizer") as RollbackSynchronizer).state_properties)
	_test_damage_and_knocked_out()
	_test_push()
	_test_bullet_immunity()
	_test_bookkeeping()
	_test_self_damage()
	_test_attacker_rules()
	_test_credit_window()
	_test_repair_and_trade()
	_test_hazard()
	_test_hazard_layout()
	_test_respawn_rule()
	_test_launch()
	_test_dash_exit_velocity()
	_test_dummy()
	_test_order_independence()
	_test_fractional_order()
	_test_idempotence()
	_test_dash_ends()
	_test_respawn()
	_test_cycle_reset()
	_test_cycle_skipped_tick()
	print("%d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)

# ---- helpers ----

func _check(ok: bool, label: String) -> void:
	_checks += 1
	if ok:
		print("PASS ", label)
	else:
		_failures += 1
		print("FAIL ", label)

func _near(got: float, want: float, label: String) -> void:
	_check(absf(got - want) <= EPS, "%s (got %.4f, want %.4f)" % [label, got, want])

func _near_vec(got: Vector2, want: Vector2, label: String) -> void:
	_check(got.distance_to(want) <= EPS, "%s (got %s, want %s)" % [label, got, want])

# A bot in mid-air (clear of the floor and the hazard), full health.
func _bot(peer: int) -> Bot:
	var bot: Bot = BOT_SCENE.instantiate() as Bot
	bot.peer_id = peer
	bot.slot = peer
	_arena.add_child(bot)
	bot.global_position = Vector2(float(peer + 3) * 2.0 * _px, 5.0 * _px)
	bot.vitals.spawn_position = bot.global_position
	return bot

func _hit(victim: Bot, attacker: int, damage: float, push: Vector2 = Vector2.ZERO, bullet: bool = false, scale_push: bool = true) -> Hit:
	var hit: Hit = Hit.new()
	hit.victim = victim
	hit.attacker_peer = attacker
	hit.damage = damage
	hit.push = push
	hit.bullet = bullet
	hit.scale_push = scale_push
	return hit

func _apply(tick: int, bots: Array[Bot], hits: Array[Hit]) -> void:
	CombatRules.apply(tick, bots, hits, LAYOUT, _cfg)

func _list(items: Array) -> Array[Bot]:
	var bots: Array[Bot] = []
	bots.assign(items)
	bots.sort_custom(func(a: Bot, b: Bot) -> bool: return a.peer_id < b.peer_id)
	return bots

func _hits(items: Array) -> Array[Hit]:
	var hits: Array[Hit] = []
	hits.assign(items)
	return hits

func _free_all(bots: Array) -> void:
	for bot: Bot in bots:
		bot.free()

func _node_for(bot: Bot, path: String) -> Node:
	var node_path: String = path.get_slice(":", 0)
	return bot if node_path.is_empty() else bot.get_node(node_path)

func _snapshot(bots: Array[Bot]) -> Array:
	var result: Array = []
	for bot: Bot in bots:
		var values: Dictionary = {}
		for path: String in _state_paths:
			values[path] = _node_for(bot, path).get(path.get_slice(":", 1))
		result.append(values)
	return result

func _restore(bots: Array[Bot], snapshot: Array) -> void:
	for i: int in bots.size():
		var values: Dictionary = snapshot[i]
		for path: String in values:
			_node_for(bots[i], path).set(path.get_slice(":", 1), values[path])

# The same state, bot by bot, property by property.
func _same(a: Array, b: Array) -> bool:
	return a == b

# A fresh bot's velocity change from one hit, in pixels per second.
func _kick(health: float, push: Vector2, scale_push: bool = true) -> Vector2:
	var victim: Bot = _bot(1)
	victim.vitals.health = health
	_apply(10, _list([victim]), _hits([_hit(victim, 2, 0.0, push, false, scale_push)]))
	var result: Vector2 = victim.velocity
	victim.free()
	return result

# ---- damage ----

func _test_damage_and_knocked_out() -> void:
	var a: Bot = _bot(1)
	var b: Bot = _bot(2)
	var bots: Array[Bot] = _list([a, b])
	_apply(10, bots, _hits([_hit(b, 1, 30.0)]))
	_near(b.vitals.health, _cfg.max_health - 30.0, "damage reduces health")
	_check(not b.vitals.knocked_out and b.vitals.ko_serial == 0, "a hit that leaves health is no knockout")
	var position_before: Vector2 = b.global_position
	_apply(11, bots, _hits([_hit(b, 1, _cfg.max_health, Vector2(3.0, -3.0))]))
	_check(b.global_position == position_before, "a bot is not moved on the tick it is knocked out")
	_near(b.vitals.health, 0.0, "health never goes below zero")
	_check(b.vitals.knocked_out and b.vitals.ko_serial == 1, "health at zero knocks out, once")
	_check(b.vitals.respawn_tick == 11 + roundi(_cfg.respawn_time * float(_cfg.tick_rate)), "respawn tick is the knockout tick plus the respawn delay (no round running)")
	var hits_before: int = b.vitals.hits_taken
	var velocity_before: Vector2 = b.velocity
	_apply(12, bots, _hits([_hit(b, 1, 5.0, Vector2(3.0, 0.0))]))
	_check(b.vitals.hits_taken == hits_before and b.velocity == velocity_before and b.vitals.ko_serial == 1, "no hit affects a knocked-out bot")
	_near(b.vitals.health, 0.0, "a knocked-out bot takes no damage")
	_apply(13, bots, _hits([_hit(a, NO_ONE, NAN), _hit(a, 2, -5.0), _hit(a, 2, INF * 0.0), _hit(a, 2, 0.0, Vector2(NAN, 0.0))]))
	_near(a.vitals.health, _cfg.max_health, "zero, negative and non-finite damage does nothing")
	_check(a.vitals.hits_taken == 0 and a.vitals.last_attacker == NO_ONE, "a hit with no damage and no push is not a hit and records no attacker")
	_free_all(bots)

# ---- push ----

# The velocity change in pixels per second for a push distance in bot heights on a bot at rest.
func _speed(distance: Vector2) -> Vector2:
	return CombatRules.push_change(Vector2.ZERO, distance, _cfg) * _px

# The window is as long as it takes the window's braking to take the sideways speed (px/s) away:
# n ticks of braking remove it, n - 1 do not.
func _window_fits(until_tick: int, tick: int, sideways_px: float, label: String) -> void:
	var brake: float = _cfg.ground_brake * _cfg.push_window_control * _px * _dt
	var ticks: int = until_tick - tick - 1
	_check(float(ticks) * brake >= absf(sideways_px) - EPS and float(ticks - 1) * brake < absf(sideways_px), "%s (%d ticks)" % [label, ticks])

func _test_push() -> void:
	var push: Vector2 = Vector2(3.0, -4.0)
	var base: Vector2 = _speed(push)
	_near_vec(_kick(_cfg.max_health, push), base, "a push is a distance in bot heights: the velocity change is the launch speed for that distance")
	_near_vec(_kick(_cfg.low_health_threshold, push), base, "multiplier 1 at the threshold health (25)")
	_near_vec(_kick(_cfg.low_health_threshold / 2.0, push), _speed(push * 1.5), "multiplier 1.5 on the distance at 12.5 health")
	_near_vec(_kick(0.0, push), _speed(push * _cfg.low_health_push_multiplier), "multiplier 2 on the distance at 0 health")
	_check(_kick(0.0, push).length() < base.length() * _cfg.low_health_push_multiplier * 0.9, "the multiplier is on the distance, not the speed (twice the distance is less than twice the speed)")
	_near_vec(_kick(_cfg.max_health, push, false), push * _px, "an unscaled push is applied as given, already a speed")
	_near_vec(_kick(0.0, push, false), push * _px, "an unscaled push ignores the low-health multiplier")
	# The multiplier comes from the health before this tick's damage.
	var victim: Bot = _bot(1)
	victim.vitals.health = _cfg.low_health_threshold + 5.0
	_apply(10, _list([victim]), _hits([_hit(victim, 2, 20.0, push)]))
	_near_vec(victim.velocity, base, "the multiplier uses health before the tick's damage")
	_check(victim.vitals.health < _cfg.low_health_threshold, "the same hit took the victim below the threshold")
	victim.free()
	# Pushes of one tick add up.
	victim = _bot(1)
	_apply(10, _list([victim]), _hits([_hit(victim, 2, 0.0, push), _hit(victim, 3, 0.0, Vector2(1.0, 1.0))]))
	_near_vec(victim.velocity, _speed(push + Vector2(1.0, 1.0)), "two pushes in one tick: the distance vectors add, then the sum is converted")
	_check(victim.velocity.distance_to(_speed(push) + _speed(Vector2(1.0, 1.0))) > 1.0, "two pushes in one tick are not the sum of their two speeds")
	_window_fits(victim.vitals.push_until_tick, 10, victim.velocity.x, "a push sets the push window from the next tick, as long as its sideways speed takes to brake away")
	victim.free()
	victim = _bot(1)
	_apply(10, _list([victim]), _hits([_hit(victim, 2, 0.0, Vector2(3.0, 0.0)), _hit(victim, 3, 0.0, Vector2(-3.0, 0.0))]))
	_near_vec(victim.velocity, Vector2.ZERO, "pushes of equal distance in opposite directions cancel")
	victim.free()
	victim = _bot(1)
	_apply(10, _list([victim]), _hits([_hit(victim, 2, 0.0, Vector2(3.0, 0.0)), _hit(victim, 3, 0.0, Vector2(-1.0, 0.0))]))
	_near_vec(victim.velocity, _speed(Vector2(2.0, 0.0)), "opposite pushes: the sum of the distance vectors decides")
	victim.free()
	victim = _bot(1)
	_apply(10, _list([victim]), _hits([_hit(victim, 2, 5.0)]))
	_check(victim.vitals.push_until_tick == 0, "damage without a push sets no push window")
	victim.free()

# ---- bullet immunity ----

func _test_bullet_immunity() -> void:
	var dasher: Bot = _bot(1)
	dasher.dash_left = _cfg.dash_time
	dasher.dash_dir = Vector2.RIGHT
	dasher.velocity = Vector2(100.0, 0.0)
	var other: Bot = _bot(2)
	_apply(10, _list([dasher, other]), _hits([_hit(dasher, 2, 10.0, Vector2(2.0, 0.0), true)]))
	_near(dasher.vitals.health, _cfg.max_health, "a bullet does no damage to a dashing bot")
	_check(dasher.vitals.hits_taken == 0 and dasher.vitals.last_attacker == NO_ONE and dasher.vitals.push_until_tick == 0, "a bullet on a dashing bot leaves no trace")
	_check(dasher.velocity == Vector2(100.0, 0.0) and dasher.dash_left == _cfg.dash_time, "a bullet does not push a dashing bot or end its dash")
	_apply(11, _list([dasher, other]), _hits([_hit(dasher, 2, 10.0, Vector2(2.0, 0.0), true), _hit(dasher, 2, 7.0, Vector2(0.0, -1.0), false)]))
	_near(dasher.vitals.health, _cfg.max_health - 7.0, "a blast or melee hit lands on a dashing bot, the bullet beside it does not")
	_apply(12, _list([other, dasher]), _hits([_hit(other, 1, 10.0, Vector2.ZERO, true)]))
	_near(other.vitals.health, _cfg.max_health - 10.0, "a bullet hits a bot that is not dashing")
	_free_all([dasher, other])

# ---- bookkeeping ----

func _test_bookkeeping() -> void:
	var victim: Bot = _bot(1)
	var hits: Array[Hit] = _hits([_hit(victim, 2, 5.0, Vector2(1.0, 0.0)), _hit(victim, 2, 6.0, Vector2(0.0, -2.0)), _hit(victim, 3, 1.0)])
	_apply(10, _list([victim]), hits)
	_check(victim.vitals.hits_taken == 1, "hits_taken rises by exactly 1 however many hits land in a tick")
	_near(victim.vitals.last_hit_damage, 12.0, "last_hit_damage is the tick's combined damage")
	_near_vec(victim.vitals.last_hit_push, Vector2(1.0, -2.0), "last_hit_push is the tick's combined push distance in bot heights")
	_apply(11, _list([victim]), _hits([_hit(victim, 2, 1.0)]))
	_check(victim.vitals.hits_taken == 2, "hits_taken rises again on the next hit tick")
	_apply(12, _list([victim]), _hits([]))
	_check(victim.vitals.hits_taken == 2, "hits_taken stays when nothing hits")
	victim.free()

# ---- self damage ----

func _test_self_damage() -> void:
	var bot: Bot = _bot(1)
	var push: Vector2 = Vector2(0.0, -5.0)
	_apply(10, _list([bot]), _hits([_hit(bot, 1, 40.0, push)]))
	_near(bot.vitals.health, _cfg.max_health - 40.0 * _cfg.self_damage_scale, "damage from the bot's own blast is scaled")
	_near_vec(bot.velocity, _speed(push), "the push from the bot's own blast is not reduced")
	_check(bot.vitals.last_attacker == NO_ONE and bot.vitals.last_attack_tick == -1, "a bot never becomes its own last attacker")
	_check(bot.vitals.hits_taken == 1, "self damage counts as a hit")
	bot.free()
	# Self damage does not erase an earlier attacker, and a self-knockout has no credit.
	var victim: Bot = _bot(1)
	var attacker: Bot = _bot(2)
	var bots: Array[Bot] = _list([victim, attacker])
	_apply(10, bots, _hits([_hit(victim, 2, 0.0, Vector2(1.0, 0.0))]))
	_apply(11, bots, _hits([_hit(victim, 1, 10.0)]))
	_check(victim.vitals.last_attacker == 2 and victim.vitals.last_attack_tick == 10, "self damage keeps the earlier attacker")
	_apply(12, bots, _hits([_hit(victim, 1, _cfg.max_health * 4.0)]))
	_check(victim.vitals.knocked_out and attacker.vitals.knockouts == 1, "the earlier attacker is credited when a blast of the victim's own finishes it")
	_free_all(bots)
	victim = _bot(1)
	attacker = _bot(2)
	bots = _list([victim, attacker])
	_apply(12, bots, _hits([_hit(victim, 1, _cfg.max_health * 4.0)]))
	_check(victim.vitals.knocked_out and attacker.vitals.knockouts == 0 and victim.vitals.knockouts == 0, "a self-knockout credits nobody")
	_free_all(bots)

# ---- last attacker ----

func _test_attacker_rules() -> void:
	var victim: Bot = _bot(1)
	var a2: Bot = _bot(2)
	var a3: Bot = _bot(3)
	var bots: Array[Bot] = _list([victim, a2, a3])
	_apply(10, bots, _hits([_hit(victim, NO_ONE, 5.0)]))
	_check(victim.vitals.last_attacker == NO_ONE and victim.vitals.last_attack_tick == -1, "an attack by no bot sets no attacker")
	_apply(11, bots, _hits([_hit(victim, 2, 0.0, Vector2(1.0, 0.0))]))
	_check(victim.vitals.last_attacker == 2 and victim.vitals.last_attack_tick == 11, "a push with no damage still sets the last attacker")
	_apply(15, bots, _hits([_hit(victim, 3, 1.0)]))
	_check(victim.vitals.last_attacker == 3 and victim.vitals.last_attack_tick == 15, "a later attacker replaces an earlier one")
	_apply(15 - 3, bots, _hits([_hit(victim, 2, 1.0)]))
	_check(victim.vitals.last_attacker == 3 and victim.vitals.last_attack_tick == 15, "an older tick never replaces a newer attacker")
	_apply(16, bots, _hits([_hit(victim, NO_ONE, 1.0)]))
	_check(victim.vitals.last_attacker == 3, "a later hazard hit does not erase the attacker")
	# Several attackers in one tick: the most damage wins, then the longest push, then the lowest peer id.
	var ids: Array = [[2, 5.0, 0.0, 3, 9.0, 0.0, 3], [2, 5.0, 0.0, 3, 5.0, 2.0, 3], [2, 5.0, 1.0, 3, 5.0, 1.0, 2]]
	for case: Array in ids:
		var v: Bot = _bot(4)
		for order: int in 2:
			v.vitals.last_attacker = NO_ONE
			v.vitals.last_attack_tick = -1
			var first: Hit = _hit(v, case[0] as int, case[1] as float, Vector2(case[2] as float, 0.0))
			var second: Hit = _hit(v, case[3] as int, case[4] as float, Vector2(case[5] as float, 0.0))
			_apply(20, _list([v, a2, a3]), _hits([first, second] if order == 0 else [second, first]))
			_check(v.vitals.last_attacker == case[6] as int, "attacker choice in one tick %s, order %d" % [case, order])
		v.free()
	_free_all(bots)

# ---- credit window ----

func _credit_case(age: int) -> int:
	var victim: Bot = _bot(1)
	var attacker: Bot = _bot(2)
	attacker.vitals.health = 50.0
	var bots: Array[Bot] = _list([victim, attacker])
	_apply(100, bots, _hits([_hit(victim, 2, 10.0)]))
	_apply(100 + age, bots, _hits([_hit(victim, NO_ONE, _cfg.max_health * 4.0)]))
	var credited: int = attacker.vitals.knockouts
	_free_all(bots)
	return credited

func _test_credit_window() -> void:
	_check(_credit_case(0) == 1, "credit on the tick of the attack")
	_check(_credit_case(_window - 1) == 1, "credit just inside the window")
	_check(_credit_case(_window) == 1, "credit at the edge of the window")
	_check(_credit_case(_window + 1) == 0, "no credit outside the window")
	# A negative tick difference never credits: the attack is stamped after the knockout tick.
	var victim: Bot = _bot(1)
	var attacker: Bot = _bot(2)
	var bots: Array[Bot] = _list([victim, attacker])
	victim.vitals.last_attacker = 2
	victim.vitals.last_attack_tick = 200
	_apply(150, bots, _hits([_hit(victim, NO_ONE, _cfg.max_health * 4.0)]))
	_check(victim.vitals.knocked_out and attacker.vitals.knockouts == 0, "a negative tick difference never credits")
	_free_all(bots)
	# The window counts from the latest attacker, not the first.
	victim = _bot(1)
	var first: Bot = _bot(2)
	var second: Bot = _bot(3)
	bots = _list([victim, first, second])
	_apply(100, bots, _hits([_hit(victim, 2, 1.0)]))
	_apply(100 + _window, bots, _hits([_hit(victim, 3, 1.0)]))
	_apply(100 + _window * 2, bots, _hits([_hit(victim, NO_ONE, _cfg.max_health * 4.0)]))
	_check(second.vitals.knockouts == 1 and first.vitals.knockouts == 0, "the window is measured from the last hit")
	_free_all(bots)
	# A knockout whose attacker has left the match credits nobody and does not fail.
	victim = _bot(1)
	var gone: Bot = _bot(2)
	_apply(100, _list([victim, gone]), _hits([_hit(victim, 2, 1.0)]))
	_apply(101, _list([victim]), _hits([_hit(victim, NO_ONE, _cfg.max_health * 4.0)]))
	_check(victim.vitals.knocked_out and gone.vitals.knockouts == 0, "a knockout whose attacker is gone credits nobody")
	_free_all([victim, gone])

# ---- repair and trades ----

func _test_repair_and_trade() -> void:
	var victim: Bot = _bot(1)
	var attacker: Bot = _bot(2)
	var bots: Array[Bot] = _list([victim, attacker])
	attacker.vitals.health = 50.0
	_apply(10, bots, _hits([_hit(victim, 2, _cfg.max_health * 4.0)]))
	_near(attacker.vitals.health, 50.0 + _cfg.knockout_repair, "the attacker is repaired by the knockout repair")
	_check(attacker.vitals.knockouts == 1 and victim.vitals.knocked_out, "the knockout is credited")
	_apply(11, bots, _hits([_hit(victim, 2, 5.0)]))
	_check(attacker.vitals.knockouts == 1 and absf(attacker.vitals.health - (50.0 + _cfg.knockout_repair)) <= EPS, "a knockout happens once: no second credit or repair")
	_free_all(bots)
	# The repair is capped at maximum health.
	victim = _bot(1)
	attacker = _bot(2)
	attacker.vitals.health = _cfg.max_health - 1.0
	_apply(10, _list([victim, attacker]), _hits([_hit(victim, 2, _cfg.max_health * 4.0)]))
	_near(attacker.vitals.health, _cfg.max_health, "the repair is capped at maximum health")
	_free_all([victim, attacker])
	# Two knockouts by one attacker in one tick repair twice.
	var v1: Bot = _bot(1)
	var v2: Bot = _bot(2)
	attacker = _bot(3)
	attacker.vitals.health = 10.0
	_apply(10, _list([v1, v2, attacker]), _hits([_hit(v1, 3, _cfg.max_health * 4.0), _hit(v2, 3, _cfg.max_health * 4.0)]))
	_near(attacker.vitals.health, 10.0 + 2.0 * _cfg.knockout_repair, "two knockouts in one tick repair twice")
	_check(attacker.vitals.knockouts == 2, "two knockouts in one tick are both credited")
	_free_all([v1, v2, attacker])
	# An attacker that was already out is credited but not repaired.
	victim = _bot(1)
	attacker = _bot(2)
	var bots2: Array[Bot] = _list([victim, attacker])
	_apply(10, bots2, _hits([_hit(victim, 2, 1.0)]))
	attacker.vitals.knocked_out = true
	attacker.vitals.health = 0.0
	_apply(11, bots2, _hits([_hit(victim, NO_ONE, _cfg.max_health * 4.0)]))
	_check(attacker.vitals.knockouts == 1 and attacker.vitals.health == 0.0, "an attacker that is already out is credited and not repaired")
	_free_all(bots2)
	# The trade, in both hit orders: both out, each credited, neither repaired.
	for flip: int in 2:
		var x: Bot = _bot(1)
		var y: Bot = _bot(2)
		x.vitals.health = 10.0
		y.vitals.health = 10.0
		var pair: Array[Hit] = _hits([_hit(x, 2, 15.0), _hit(y, 1, 15.0)])
		if flip == 1:
			pair.reverse()
		_apply(10, _list([x, y]), pair)
		_check(x.vitals.knocked_out and y.vitals.knocked_out, "trade knocks out both (order %d)" % flip)
		_check(x.vitals.knockouts == 1 and y.vitals.knockouts == 1, "trade credits each (order %d)" % flip)
		_check(x.vitals.health == 0.0 and y.vitals.health == 0.0, "trade repairs neither (order %d)" % flip)
		_free_all([x, y])
	# A three-way cycle: 1 hits 2, 2 hits 3, 3 hits 1, all lethal on one tick.
	var cycle: Array[Bot] = [_bot(1), _bot(2), _bot(3)]
	for bot: Bot in cycle:
		bot.vitals.health = 10.0
	_apply(10, cycle, _hits([_hit(cycle[1], 1, 15.0), _hit(cycle[2], 2, 15.0), _hit(cycle[0], 3, 15.0)]))
	var all_out: bool = true
	var all_credited: bool = true
	var none_repaired: bool = true
	for bot: Bot in cycle:
		all_out = all_out and bot.vitals.knocked_out
		all_credited = all_credited and bot.vitals.knockouts == 1
		none_repaired = none_repaired and bot.vitals.health == 0.0
	_check(all_out and all_credited and none_repaired, "a three-way cycle knocks out all, credits each once, repairs none")
	_free_all(cycle)

# ---- hazard ----

func _floor_bot(peer: int) -> Bot:
	var bot: Bot = _bot(peer)
	bot.global_position = Vector2(bot.global_position.x, LAYOUT.bounds.end.y * _px - _px / 2.0)
	return bot

# The first hazard tick at which a body resting on the floor is in the metal, by HazardMath alone.
func _predicted_hazard_tick() -> int:
	var rest: float = LAYOUT.bounds.end.y * _px
	for ticks: int in roundi(_cfg.hazard_cycle_time * float(_cfg.tick_rate)):
		if HazardMath.is_in_metal(rest, ticks, _cfg.tick_rate, _cfg.hazard_start_time, _cfg.hazard_cap_time, rest, LAYOUT.hazard_top * _px):
			return ticks
	return -1

func _test_hazard() -> void:
	var start: int = 1000
	MatchSettings.round_start_tick = start
	var predicted: int = _predicted_hazard_tick()
	_check(predicted > 0, "HazardMath puts a floor bot in the metal at some tick (%d)" % predicted)
	var bot: Bot = _floor_bot(1)
	var rival: Bot = _bot(2)
	var bots: Array[Bot] = _list([bot, rival])
	_apply(start + predicted - 1, bots, _hits([]))
	_check(not bot.vitals.knocked_out, "no hazard knockout the tick before HazardMath says so")
	_apply(start + predicted, bots, _hits([]))
	_check(bot.vitals.knocked_out and bot.vitals.ko_serial == 1 and bot.vitals.health == 0.0, "hazard knockout on exactly the tick HazardMath predicts")
	_check(not rival.vitals.knocked_out, "a bot above the metal is not knocked out")
	_check(bot.vitals.respawn_tick == start + roundi(_cfg.hazard_cycle_time * float(_cfg.tick_rate)), "a hazard knockout waits for the next cycle")
	_apply(start + predicted + 1, bots, _hits([]))
	_check(bot.vitals.ko_serial == 1, "a bot already out is not knocked out again by the hazard")
	_free_all(bots)
	# The hazard knockout is credited to whoever pushed last, within the window.
	bot = _floor_bot(1)
	rival = _bot(2)
	bots = _list([bot, rival])
	rival.vitals.health = 50.0
	_apply(start + predicted - 5, bots, _hits([_hit(bot, 2, 0.0, Vector2(1.0, 0.0))]))
	_apply(start + predicted, bots, _hits([]))
	_check(bot.vitals.knocked_out and rival.vitals.knockouts == 1 and absf(rival.vitals.health - (50.0 + _cfg.knockout_repair)) <= EPS, "the hazard knockout is credited and repaired")
	_free_all(bots)
	# With no round the metal never moves.
	MatchSettings.round_start_tick = -1
	bot = _floor_bot(1)
	_apply(start + predicted, _list([bot]), _hits([]))
	_check(not bot.vitals.knocked_out, "no hazard before a round starts")
	bot.free()
	MatchSettings.round_start_tick = -1
	# Nothing is in the metal before the hazard's start time, wherever it stands (float error from a
	# fast slide into a wall once left a floor bot 0.0013 px inside the floor); from the start time
	# on the bare comparison holds.
	MatchSettings.round_start_tick = 1000
	var settled: Bot = _floor_bot(1)
	settled.global_position.y += 0.0013
	var sunk: Bot = _floor_bot(2)
	sunk.global_position.y += 2.0
	var start_ticks: int = roundi(_cfg.hazard_start_time * float(_cfg.tick_rate))
	_apply(1000 + start_ticks - 1, _list([settled, sunk]), _hits([]))
	_check(not settled.vitals.knocked_out and not sunk.vitals.knocked_out, "before the hazard's start time a bot at or below the floor line is not knocked out")
	_apply(1000 + start_ticks, _list([settled, sunk]), _hits([]))
	_check(settled.vitals.knocked_out and sunk.vitals.knocked_out, "from the start time on, a bot below the floor line is in the metal as before")
	_free_all([settled, sunk])
	MatchSettings.round_start_tick = -1

# ---- the dummy ----

func _test_dummy() -> void:
	var dummy: Bot = _bot(Bot.DUMMY_PEER)
	dummy.slot = _cfg.max_players
	var player: Bot = _bot(1)
	player.vitals.health = 40.0
	var bots: Array[Bot] = _list([dummy, player])
	_check(bots[0] == dummy, "the dummy sorts first")
	_apply(10, bots, _hits([_hit(dummy, 1, _cfg.max_health * 4.0)]))
	_check(dummy.vitals.knocked_out and player.vitals.knockouts == 1 and absf(player.vitals.health - (40.0 + _cfg.knockout_repair)) <= EPS, "the dummy takes hits, is knocked out and credits the attacker")
	_apply(11, bots, _hits([_hit(player, Bot.DUMMY_PEER, 5.0)]))
	_check(player.vitals.last_attacker == Bot.DUMMY_PEER, "peer 0 is a real attacker id, unlike -1")
	_free_all(bots)

# ---- order independence and idempotence ----

# A busy tick: a trade, a push on a dashing bot, a blast on all, a bullet on a dasher, a hazard-free
# bystander, several attackers on one victim.
func _busy_scene() -> Array:
	var bots: Array[Bot] = []
	for peer: int in 5:
		bots.append(_bot(peer))
	bots[0].vitals.health = 10.0
	bots[1].vitals.health = 10.0
	bots[2].dash_left = _cfg.dash_time
	bots[3].vitals.health = 30.0
	var hits: Array[Hit] = _hits([
		_hit(bots[0], 1, 15.0, Vector2(2.0, 0.0)),
		_hit(bots[1], 0, 15.0, Vector2(-2.0, 0.0)),
		_hit(bots[2], 3, 9.0, Vector2(0.0, -1.0), true),
		_hit(bots[2], 4, 3.0, Vector2(0.0, -1.0)),
		_hit(bots[3], 2, 4.0, Vector2(1.0, 1.0)),
		_hit(bots[3], 4, 4.0, Vector2(0.0, 2.0), false, false),
		_hit(bots[3], 3, 6.0, Vector2(0.0, 0.0)),
		_hit(bots[4], 4, 20.0, Vector2(0.0, -5.0)),
		_hit(bots[4], 0, 2.0),
	])
	return [bots, hits]

func _test_order_independence() -> void:
	var scene: Array = _busy_scene()
	var bots: Array[Bot] = scene[0]
	var hits: Array[Hit] = scene[1]
	var start: Array = _snapshot(bots)
	_apply(50, bots, hits)
	var baseline: Array = _snapshot(bots)
	_check(not _same(baseline, start), "the busy scene changes state")
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	var all_same: bool = true
	for round: int in 40:
		_restore(bots, start)
		var shuffled: Array[Hit] = hits.duplicate()
		for i: int in range(shuffled.size() - 1, 0, -1):
			var j: int = rng.randi_range(0, i)
			var held: Hit = shuffled[i]
			shuffled[i] = shuffled[j]
			shuffled[j] = held
		_apply(50, bots, shuffled)
		all_same = all_same and _same(_snapshot(bots), baseline)
	_check(all_same, "40 shuffles of the hit list give identical state")
	_free_all(bots)

func _test_idempotence() -> void:
	var scene: Array = _busy_scene()
	var bots: Array[Bot] = scene[0]
	var hits: Array[Hit] = scene[1]
	var start: Array = _snapshot(bots)
	_apply(50, bots, hits)
	var first: Array = _snapshot(bots)
	_restore(bots, start)
	_apply(50, bots, hits)
	_check(_same(_snapshot(bots), first), "applying the same tick twice from the same starting state gives identical state")
	_restore(bots, start)
	_check(_same(_snapshot(bots), start), "the snapshot round trip is exact")
	_free_all(bots)

# ---- a push ends a dash ----

func _dasher() -> Bot:
	var bot: Bot = _bot(1)
	bot.dash_left = _cfg.dash_time
	bot.dash_cooldown_left = _cfg.dash_cooldown
	bot.dash_dir = Vector2.RIGHT
	return bot

# A hit lands on tick 0 of a dash that has already run one tick; both bots then run 3 ticks.
# Returns [hit bot, untouched bot].
func _dash_pair(hit_for: Callable) -> Array[Bot]:
	var hit_bot: Bot = _dasher()
	var plain: Bot = _dasher()
	plain.peer_id = 9
	plain.global_position += Vector2(0.0, 2.0 * _px)
	for bot: Bot in [hit_bot, plain]:
		bot._rollback_tick(_dt, 0, true)
	var others: Bot = _bot(2)
	_apply(1, _list([hit_bot, others]), _hits([hit_for.call(hit_bot) as Hit]))
	for tick: int in range(1, 4):
		hit_bot._rollback_tick(_dt, tick, true)
		plain._rollback_tick(_dt, tick, true)
	others.free()
	return [hit_bot, plain]

func _test_dash_ends() -> void:
	var up: Vector2 = Vector2(0.0, -4.0)
	var cases: Dictionary = {
		"melee-style hit": func(victim: Bot) -> Hit: return _hit(victim, 2, _cfg.melee_damage, Vector2(0.0, -_cfg.melee_push)),
		"blast-style hit": func(victim: Bot) -> Hit: return _hit(victim, 2, 20.0, up),
		"plate-style hit (unscaled)": func(victim: Bot) -> Hit: return _hit(victim, Bot.NO_PEER, 0.0, Vector2(0.0, -_cfg.plate_launch_speed), false, false),
	}
	for label: String in cases:
		var pair: Array[Bot] = _dash_pair(cases[label] as Callable)
		var hit_bot: Bot = pair[0]
		var plain: Bot = pair[1]
		var rise: float = (plain.global_position.y - 2.0 * _px) - hit_bot.global_position.y
		_check(hit_bot.dash_left == 0.0, "a %s ends the dash" % label)
		_near(hit_bot.dash_cooldown_left, plain.dash_cooldown_left, "a %s leaves the dash cooldown alone" % label)
		_check(plain.dash_left > 0.0, "the bot that was not hit is still dashing after the same ticks (%s)" % label)
		_check(rise > 0.3 * _px, "after a %s the bot moves with the push, %.1f px above the bot that was not hit" % [label, rise])
		_free_all(pair)
	# A bullet changes nothing: the dash goes on, no damage, no push.
	var bullet_bot: Bot = _dasher()
	var control: Bot = _dasher()
	control.peer_id = 9
	var bullet_hit: Hit = _hit(bullet_bot, 2, 10.0, Vector2(0.0, -4.0), true)
	for tick: int in 4:
		if tick == 1:
			_apply(tick, _list([bullet_bot]), _hits([bullet_hit]))
		bullet_bot._rollback_tick(_dt, tick, true)
		control._rollback_tick(_dt, tick, true)
	_check(bullet_bot.dash_left == control.dash_left and bullet_bot.dash_left > 0.0, "a bullet leaves the dash running")
	_near_vec(bullet_bot.global_position, control.global_position, "a bullet leaves the dashing bot's path unchanged")
	_near(bullet_bot.vitals.health, _cfg.max_health, "a bullet on a dashing bot does no damage")
	# Damage without a push does not end a dash.
	var damaged: Bot = _dasher()
	_apply(1, _list([damaged]), _hits([_hit(damaged, 2, 5.0)]))
	_check(damaged.dash_left > 0.0, "a hit with no push does not end the dash")
	_free_all([bullet_bot, control, damaged])

# ---- respawn and the test cycle ----

func _test_respawn() -> void:
	var bot: Bot = _bot(1)
	var spawn: Vector2 = bot.vitals.spawn_position
	bot.global_position = Vector2(77.0, 99.0)
	bot.velocity = Vector2(500.0, -300.0)
	bot.fuel = 0.1
	bot.dash_left = 0.05
	bot.dash_cooldown_left = 2.0
	bot.dash_dir = Vector2.UP
	bot.wall_nx = 1
	bot.arsenal.picked_weapon = ItemIds.BOLT_THROWER
	bot.arsenal.active_slot = 1
	bot.gadgets.gadget_a = ItemIds.SPRING_PLATE
	bot.vitals.health = 0.0
	bot.vitals.knocked_out = true
	bot.vitals.ko_serial = 3
	bot.vitals.knockouts = 2
	bot.vitals.hits_taken = 6
	bot.vitals.respawn_tick = 300
	bot.vitals._rollback_tick(_dt, 299, true)
	_check(bot.vitals.knocked_out and bot.global_position == Vector2(77.0, 99.0), "no respawn before the respawn tick")
	bot.vitals._rollback_tick(_dt, 300, true)
	_check(not bot.vitals.knocked_out and bot.vitals.health == _cfg.max_health, "respawn at the respawn tick with full health")
	_check(bot.global_position == spawn and bot.velocity == Vector2.ZERO, "respawn at the spawn point at rest")
	_near(bot.fuel, _cfg.fuel_capacity, "respawn refills the fuel")
	_check(bot.dash_left == 0.0 and bot.dash_cooldown_left == 0.0 and bot.wall_nx == 0, "respawn clears the movement state")
	# Phase 1 ruling: a bot gets one Cooker Bomb on every spawn and respawn.
	_check(bot.arsenal.picked_weapon == ItemIds.NONE and bot.gadgets.gadget_a == ItemIds.COOKER_BOMB and bot.gadgets.gadget_b == ItemIds.NONE, "respawn calls reset_for_spawn on the arsenal and the gadgets")
	_check(bot.vitals.ko_serial == 3 and bot.vitals.knockouts == 2 and bot.vitals.hits_taken == 6, "respawn keeps the counters")
	# A late tick (the exact one was not simulated) still respawns the bot.
	bot.vitals.knocked_out = true
	bot.vitals.respawn_tick = 310
	bot.vitals._rollback_tick(_dt, 315, true)
	_check(not bot.vitals.knocked_out, "a bot whose respawn tick was skipped respawns on the next simulated tick")
	# A live bot is left alone.
	bot.global_position = Vector2(5.0, 5.0)
	bot.vitals._rollback_tick(_dt, 400, true)
	_check(bot.global_position == Vector2(5.0, 5.0), "a live bot is not moved by its own tick")
	bot.free()

func _test_cycle_reset() -> void:
	var start: int = 100
	var cycle: int = roundi(_cfg.hazard_cycle_time * float(_cfg.tick_rate))
	var bot: Bot = _bot(1)
	var spawn: Vector2 = bot.vitals.spawn_position
	MatchSettings.round_start_tick = -1
	bot.vitals.health = 30.0
	bot.global_position = Vector2(11.0, 22.0)
	bot.vitals._rollback_tick(_dt, start + cycle, true)
	_check(bot.vitals.health == 30.0, "no cycle reset before a round starts")
	MatchSettings.round_start_tick = start
	bot.vitals._rollback_tick(_dt, start, true)
	_check(bot.vitals.health == 30.0 and bot.global_position == Vector2(11.0, 22.0), "no reset at the first cycle start")
	bot.vitals._rollback_tick(_dt, start + cycle - 1, true)
	_check(bot.vitals.health == 30.0, "no reset one tick before the cycle ends")
	bot.vitals._rollback_tick(_dt, start + cycle, true)
	_check(bot.vitals.health == _cfg.max_health and bot.global_position == spawn, "every bot is reset at the start of the second cycle")
	bot.vitals.health = 30.0
	bot.vitals.knocked_out = true
	bot.vitals.respawn_tick = start + cycle * 5
	bot.vitals._rollback_tick(_dt, start + cycle * 2, true)
	_check(bot.vitals.health == _cfg.max_health and not bot.vitals.knocked_out, "the third cycle start resets a knocked-out bot too")
	MatchSettings.round_start_tick = -1
	bot.free()

# ---- hazard helpers on a layout whose bounds do not start at 0 ----

func _test_hazard_layout() -> void:
	var layout: ArenaLayout = ArenaLayout.new()
	layout.bounds = Rect2(1.0, 2.0, 40.0, 16.0)
	layout.hazard_top = 4.0
	_near(layout.hazard_floor_px(_px), 18.0 * _px, "the hazard floor is the bottom of the interior")
	_near(layout.hazard_top_px(_px), 6.0 * _px, "the hazard top is hazard_top below the top of the interior")
	_near(LAYOUT.hazard_floor_px(_px), LAYOUT.bounds.end.y * _px, "Smelter hazard floor")
	# At the cap time the metal stands at the top: a bot whose bottom is between 4 and 6 bot heights is
	# above it, one whose bottom is at 7 is in it.
	var start: int = 1000
	MatchSettings.round_start_tick = start
	var cap_tick: int = start + roundi(_cfg.hazard_cap_time * float(_cfg.tick_rate)) - 1
	var high: Bot = _bot(1)
	high.global_position = Vector2(100.0, 5.0 * _px - _px / 2.0)
	var low: Bot = _bot(2)
	low.global_position = Vector2(300.0, 7.0 * _px - _px / 2.0)
	CombatRules.apply(cap_tick, _list([high, low]), _hits([]), layout, _cfg)
	_check(not high.vitals.knocked_out, "a bot above the metal of an offset layout is not knocked out")
	_check(low.vitals.knocked_out, "a bot in the metal of an offset layout is knocked out")
	_free_all([high, low])
	# Before the metal rises the surface is the floor, the bottom of the interior (18 bot heights here).
	var resting: Bot = _bot(1)
	resting.global_position = Vector2(100.0, 17.5 * _px)
	CombatRules.apply(start, _list([resting]), _hits([]), layout, _cfg)
	_check(not resting.vitals.knocked_out, "a bot above the floor of an offset layout is safe before the metal rises")
	resting.free()
	MatchSettings.round_start_tick = -1

# ---- when a knocked-out bot comes back (phase 1 test cycle) ----

func _ko_at(tick: int) -> Bot:
	var bot: Bot = _bot(1)
	_apply(tick, _list([bot]), _hits([_hit(bot, NO_ONE, _cfg.max_health * 4.0)]))
	return bot

func _test_respawn_rule() -> void:
	var start: int = 1000
	var rate: float = float(_cfg.tick_rate)
	var cycle: int = roundi(_cfg.hazard_cycle_time * rate)
	var hazard: int = roundi(_cfg.hazard_start_time * rate)
	var delay: int = roundi(_cfg.respawn_time * rate)
	MatchSettings.round_start_tick = start
	var bot: Bot = _ko_at(start + 100)
	_check(bot.vitals.respawn_tick == start + 100 + delay, "knocked out well before the hazard starts: back after the normal delay")
	bot.free()
	bot = _ko_at(start + hazard - delay - 1)
	_check(bot.vitals.respawn_tick == start + hazard - 1, "the delay ends one tick before the hazard starts: back after the normal delay")
	bot.free()
	bot = _ko_at(start + hazard - delay)
	_check(bot.vitals.respawn_tick == start + cycle, "the delay would end when the hazard starts: back at the next cycle start")
	bot.free()
	bot = _ko_at(start + hazard)
	_check(bot.vitals.respawn_tick == start + cycle, "knocked out when the hazard starts: back at the next cycle start")
	bot.free()
	bot = _ko_at(start + cycle - 1)
	_check(bot.vitals.respawn_tick == start + cycle, "knocked out on the last tick of a cycle: back on the first tick of the next")
	bot.free()
	bot = _ko_at(start + cycle + 100)
	_check(bot.vitals.respawn_tick == start + cycle + 100 + delay, "the same rule holds in the second cycle")
	bot.free()
	bot = _ko_at(start + cycle + hazard + 5)
	_check(bot.vitals.respawn_tick == start + cycle * 2, "knocked out late in the second cycle: back at the third cycle start")
	_check(bot.vitals.ko_serial == 1, "ko_serial rose once for the knockout")
	# The bot's own tick keeps it out until then and brings it back then.
	bot.vitals.cycle_index = 1
	bot.vitals._rollback_tick(_dt, start + cycle * 2 - 1, true)
	_check(bot.vitals.knocked_out, "a bot knocked out in the hazard stays out until the next cycle")
	bot.vitals._rollback_tick(_dt, start + cycle * 2, true)
	_check(not bot.vitals.knocked_out and bot.vitals.cycle_index == 2, "it is back on the first tick of the next cycle")
	bot.free()
	MatchSettings.round_start_tick = -1

# ---- launch (Spring Plate) ----

func _launch(victim: Bot, push: Vector2, attacker: int = 2) -> Hit:
	var hit: Hit = _hit(victim, attacker, 0.0, push)
	hit.launch = true
	return hit

func _test_launch() -> void:
	var speed: float = _cfg.plate_launch_speed
	var up: Vector2 = Vector2(0.0, -speed)
	var faller: Bot = _bot(1)
	faller.velocity = Vector2(0.0, _cfg.fall_speed_limit * _px)
	_apply(10, _list([faller]), _hits([_launch(faller, up)]))
	_near_vec(faller.velocity, Vector2(0.0, -speed * _px), "a bot falling at the fall limit leaves a plate at exactly the plate's speed")
	_check(faller.vitals.push_until_tick == 0, "a launch straight up opens no push window: there is no sideways speed to protect")
	_check(faller.vitals.last_attacker == 2 and faller.vitals.last_attack_tick == 10, "a launch credits the plate's owner")
	faller.free()
	var runner: Bot = _bot(1)
	var run: Vector2 = Vector2(_cfg.run_speed * _px, 100.0)
	runner.velocity = run
	_apply(10, _list([runner]), _hits([_launch(runner, up)]))
	_near_vec(runner.velocity, Vector2(run.x, -speed * _px), "a bot running across a plate keeps its horizontal speed")
	runner.free()
	var sideways: Bot = _bot(1)
	sideways.velocity = Vector2(50.0, 0.0)
	_apply(10, _list([sideways]), _hits([_launch(sideways, Vector2(3.0, -speed))]))
	_near_vec(sideways.velocity, Vector2(50.0 + 3.0 * _px, -speed * _px), "the horizontal part of a launch is added")
	sideways.free()
	var low_health: Bot = _bot(1)
	low_health.vitals.health = 0.0
	_apply(10, _list([low_health]), _hits([_launch(low_health, up)]))
	_near_vec(low_health.velocity, Vector2(0.0, -speed * _px), "a launch is not scaled by the low-health multiplier")
	low_health.free()
	var dasher: Bot = _dasher()
	_apply(10, _list([dasher]), _hits([_launch(dasher, Vector2(1.0, -speed))]))
	_check(dasher.dash_left == 0.0, "a launch ends a dash")
	_near_vec(dasher.velocity, Vector2(_cfg.dash_exit_speed * _px + _px, -speed * _px), "a launch on a dashing bot: dash exit velocity, vertical replaced, horizontal added")
	dasher.free()
	var bullet_dasher: Bot = _dasher()
	var bullet: Hit = _launch(bullet_dasher, up)
	bullet.bullet = true
	_apply(10, _list([bullet_dasher]), _hits([bullet]))
	_check(bullet_dasher.dash_left > 0.0, "a bullet-flagged launch on a dashing bot is ignored")
	bullet_dasher.free()
	# Two plates in one tick: the most upward one wins whatever the order.
	var twice: Bot = _bot(1)
	var first: Hit = _launch(twice, Vector2(0.0, -10.0))
	var second: Hit = _launch(twice, Vector2(0.0, -14.0))
	_apply(10, _list([twice]), _hits([first, second]))
	var forward: Vector2 = twice.velocity
	twice.velocity = Vector2.ZERO
	_apply(10, _list([twice]), _hits([second, first]))
	_check(forward == twice.velocity and absf(forward.y + 14.0 * _px) <= EPS, "two launches in one tick: the most upward wins, in either order")
	twice.free()
	# scale_push false without launch still adds.
	var added: Bot = _bot(1)
	added.velocity = Vector2(0.0, 100.0)
	_apply(10, _list([added]), _hits([_hit(added, 2, 0.0, up, false, false)]))
	_near_vec(added.velocity, Vector2(0.0, 100.0 - speed * _px), "an unscaled push without launch is added to the velocity")
	added.free()

# ---- a push that ends a dash leaves the dash exit velocity plus the push ----

func _test_dash_exit_velocity() -> void:
	var dasher: Bot = _dasher()
	dasher.velocity = Vector2(_cfg.dash_distance / _cfg.dash_time * _px, 0.0)
	_apply(10, _list([dasher]), _hits([_hit(dasher, 2, _cfg.melee_damage, Vector2(0.0, -_cfg.melee_push))]))
	_near_vec(dasher.velocity, Vector2(_cfg.dash_exit_speed * _px, _speed(Vector2(0.0, -_cfg.melee_push)).y), "a melee push on a bot dashing right leaves dash exit speed plus the push")
	_check(dasher.dash_left == 0.0, "the dash is over")
	dasher.free()
	var diagonal: Bot = _dasher()
	diagonal.dash_dir = Vector2(1.0, -1.0).normalized()
	diagonal.velocity = diagonal.dash_dir * 999.0
	_apply(10, _list([diagonal]), _hits([_hit(diagonal, 2, 1.0, Vector2(-1.0, 0.0))]))
	_near_vec(diagonal.velocity, diagonal.dash_dir * _cfg.dash_exit_speed * _px + CombatRules.push_change(diagonal.dash_dir * _cfg.dash_exit_speed, Vector2(-1.0, 0.0), _cfg) * _px, "the exit velocity follows the dash direction, and the push is added as distance to the exit speed")
	diagonal.free()

# ---- fractional damage: the order of the input list must not matter ----

func _permutations(items: Array) -> Array:
	if items.size() <= 1:
		return [items.duplicate()]
	var result: Array = []
	for i: int in items.size():
		var rest: Array = items.duplicate()
		rest.remove_at(i)
		for tail: Array in _permutations(rest):
			tail.push_front(items[i])
			result.append(tail)
	return result

func _test_fractional_order() -> void:
	# The reviewer's probe: 1.0 health, hits of 0.1, 0.2 and 0.7. Summed in different orders the
	# float result differs, so one order knocked the bot out and another left 1.1e-16.
	var victim: Bot = _bot(1)
	var other: Bot = _bot(2)
	var bots: Array[Bot] = _list([victim, other])
	victim.vitals.health = 1.0
	var start: Array = _snapshot(bots)
	var hits: Array = [_hit(victim, 2, 0.1), _hit(victim, 2, 0.2), _hit(victim, 2, 0.7)]
	var baseline: Array = []
	var identical: bool = true
	var orders: Array = _permutations(hits)
	for i: int in orders.size():
		_restore(bots, start)
		_apply(50, bots, _hits(orders[i]))
		var state: Array = _snapshot(bots)
		if i == 0:
			baseline = state
		identical = identical and _same(state, baseline)
	_check(orders.size() == 6 and identical, "0.1, 0.2 and 0.7 on 1.0 health give bit-identical state in all 6 orders")
	# Several victims, fractional damage and pushes, two attackers whose totals are nearly equal.
	var a: Bot = _bot(3)
	var b: Bot = _bot(4)
	var c: Bot = _bot(5)
	var all: Array[Bot] = _list([victim, other, a, b, c])
	_restore([victim, other], start)
	var mixed: Array = [
		_hit(c, 3, 0.1, Vector2(0.1, 0.2)), _hit(c, 4, 0.2, Vector2(0.3, 0.1)), _hit(c, 3, 0.7, Vector2(0.7, -0.1)),
		_hit(c, 4, 0.3, Vector2(0.2, 0.2)), _hit(c, 3, 0.6, Vector2(-0.4, 0.3)), _hit(c, 4, 0.1, Vector2(0.1, 0.1)),
		_hit(victim, 3, 0.1, Vector2(0.1, 0.0)), _hit(victim, 4, 0.1, Vector2(0.0, 0.1)), _hit(victim, 3, 0.2, Vector2(0.3, 0.3)),
	]
	var mixed_start: Array = _snapshot(all)
	_apply(50, all, _hits(mixed))
	var mixed_baseline: Array = _snapshot(all)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 11
	var all_same: bool = true
	for round: int in 200:
		_restore(all, mixed_start)
		var shuffled: Array = mixed.duplicate()
		for i: int in range(shuffled.size() - 1, 0, -1):
			var j: int = rng.randi_range(0, i)
			var held: Hit = shuffled[i]
			shuffled[i] = shuffled[j]
			shuffled[j] = held
		_apply(50, all, _hits(shuffled))
		all_same = all_same and _same(_snapshot(all), mixed_baseline)
	_check(all_same, "200 shuffles of fractional hits give bit-identical state, last attacker included")
	_free_all(all)

# ---- the cycle reset does not depend on one exact tick ----

func _test_cycle_skipped_tick() -> void:
	var start: int = 100
	var cycle: int = roundi(_cfg.hazard_cycle_time * float(_cfg.tick_rate))
	MatchSettings.round_start_tick = start
	var bot: Bot = _bot(1)
	var spawn: Vector2 = bot.vitals.spawn_position
	bot.vitals.health = 30.0
	bot.global_position = Vector2(11.0, 22.0)
	bot.vitals._rollback_tick(_dt, start + cycle - 1, true)
	bot.vitals._rollback_tick(_dt, start + cycle + 1, true)
	_check(bot.vitals.health == _cfg.max_health and bot.global_position == spawn and bot.vitals.cycle_index == 1, "a bot that skipped the exact reset tick is reset on the next tick it runs")
	bot.vitals.health = 30.0
	bot.vitals._rollback_tick(_dt, start + cycle + 2, true)
	_check(bot.vitals.health == 30.0, "and only once")
	bot.vitals._rollback_tick(_dt, start + cycle * 3 + 5, true)
	_check(bot.vitals.health == _cfg.max_health and bot.vitals.cycle_index == 3, "a bot that skipped whole cycles is reset once and catches up")
	bot.free()
	MatchSettings.round_start_tick = -1
