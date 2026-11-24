extends SceneTree
## Run: godot --headless --path <project> --script res://tests/test_combat.gd
## Exits non-zero on any failure. GDD numbers appear only here.

const CombatMath := preload("res://combat/combat_math.gd")
const CombatLedger := preload("res://combat/combat_ledger.gd")
const FighterHealth := preload("res://combat/fighter_health.gd")

const MAX_HEALTH: float = 100.0
const REPAIR: float = 20.0
const THRESHOLD: float = 25.0
const MAX_MULT: float = 2.0
const BLAST_PUSH: float = 5.0
const BLAST_RADIUS: float = 3.0
const CREDIT_WINDOW: int = 90  # first guess: 3 seconds at 30 ticks per second; not in the GDD
const NO_ONE: int = -1

var _failures: int = 0


func _init() -> void:
	_test_health()
	_test_ignored_inputs()
	_test_push_multiplier()
	_test_blast()
	_test_credit()
	_test_credit_order_and_repair()
	_test_registration()
	_test_nonfinite_math()
	if _failures == 0:
		print("ALL COMBAT TESTS PASSED")
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		printerr("FAIL: ", label)


func _near(a: float, b: float) -> bool:
	return absf(a - b) < 0.0001


func _ledger() -> CombatLedger:
	var ledger: CombatLedger = CombatLedger.new()
	ledger.knockout_repair = REPAIR
	ledger.credit_window_ticks = CREDIT_WINDOW
	ledger.add_fighter(1, MAX_HEALTH)
	ledger.add_fighter(2, MAX_HEALTH)
	ledger.add_fighter(3, MAX_HEALTH)
	return ledger


func _test_health() -> void:
	var h: FighterHealth = FighterHealth.new(MAX_HEALTH)
	_check(_near(h.health, 100.0) and not h.knocked_out, "starts full")
	_check(not h.apply_damage(30.0) and _near(h.health, 70.0), "damage reduces health")
	h.heal(50.0)
	_check(_near(h.health, 100.0), "heal capped at max")
	_check(h.apply_damage(500.0), "overkill reports knockout")
	_check(_near(h.health, 0.0) and h.knocked_out, "health clamps at zero")
	h.heal(10.0)
	_check(_near(h.health, 0.0), "no heal when knocked out")


func _test_ignored_inputs() -> void:
	var h: FighterHealth = FighterHealth.new(MAX_HEALTH)
	for bad: float in [0.0, -5.0, NAN, INF, -INF]:
		_check(not h.apply_damage(bad) and _near(h.health, 100.0), "ignored damage %s" % bad)
	h.apply_damage(40.0)
	for bad: float in [0.0, -5.0, NAN, INF]:
		h.heal(bad)
		_check(_near(h.health, 60.0), "ignored heal %s" % bad)
	h.apply_damage(100.0)
	_check(not h.apply_damage(10.0) and _near(h.health, 0.0), "damage after knockout ignored")
	var ledger: CombatLedger = _ledger()
	ledger.damage(1, 2, NAN, 10)
	ledger.knock_out(1, 20)
	_check(ledger.credited_to(1) == NO_ONE, "NaN damage records no attacker")


func _test_push_multiplier() -> void:
	_check(_near(CombatMath.push_multiplier(100.0, THRESHOLD, MAX_MULT), 1.0), "mult at 100")
	_check(_near(CombatMath.push_multiplier(25.0, THRESHOLD, MAX_MULT), 1.0), "mult at 25")
	_check(_near(CombatMath.push_multiplier(12.5, THRESHOLD, MAX_MULT), 1.5), "mult at 12.5")
	_check(_near(CombatMath.push_multiplier(0.0, THRESHOLD, MAX_MULT), 2.0), "mult at 0")


func _test_blast() -> void:
	var c: Vector2 = Vector2(10.0, 10.0)
	_check(CombatMath.blast_push(c + Vector2(1.5, 0.0), c, BLAST_PUSH, BLAST_RADIUS).is_equal_approx(Vector2(2.5, 0.0)), "blast at 1.5 is half, points away")
	_check(CombatMath.blast_push(c, c, BLAST_PUSH, BLAST_RADIUS).is_equal_approx(Vector2(0.0, -5.0)), "dead centre pushes up at full strength")
	_check(CombatMath.blast_push(c + Vector2(0.0, 3.0), c, BLAST_PUSH, BLAST_RADIUS) == Vector2.ZERO, "blast at 3 is zero")
	_check(CombatMath.blast_push(c + Vector2(4.0, 0.0), c, BLAST_PUSH, BLAST_RADIUS) == Vector2.ZERO, "blast beyond 3 is zero")
	var diag: Vector2 = CombatMath.blast_push(c + Vector2(-1.0, 1.0), c, BLAST_PUSH, BLAST_RADIUS)
	_check(diag.x < 0.0 and diag.y > 0.0 and _near(diag.length(), 5.0 * (1.0 - sqrt(2.0) / 3.0)), "diagonal points away from centre")


func _test_credit() -> void:
	# Credit inside the window (edge inclusive), with repair.
	var l: CombatLedger = _ledger()
	l.damage(2, NO_ONE, 50.0, 0)
	l.damage(1, 2, 60.0, 100)
	_check(l.damage(1, NO_ONE, 100.0, 100 + CREDIT_WINDOW), "hazard knocks out")
	_check(l.credited_to(1) == 2, "credit at window edge")
	l.end_tick()
	_check(_near(l.health_of(2), 70.0), "attacker repaired by 20")
	# Repair cap.
	l = _ledger()
	l.damage(1, 2, 10.0, 0)
	l.knock_out(1, 5)
	l.end_tick()
	_check(l.credited_to(1) == 2 and _near(l.health_of(2), 100.0), "repair capped at max")
	# Outside the window.
	l = _ledger()
	l.damage(2, NO_ONE, 50.0, 0)
	l.damage(1, 2, 10.0, 0)
	l.knock_out(1, CREDIT_WINDOW + 1)
	l.end_tick()
	_check(l.credited_to(1) == NO_ONE and _near(l.health_of(2), 50.0), "no credit outside window, no repair")
	# Self-damage only.
	l = _ledger()
	l.damage(1, 1, 10.0, 0)
	l.record_push(1, 1, 0)
	l.knock_out(1, 1)
	_check(l.credited_to(1) == NO_ONE, "self-knockout has no credit")
	# Self-damage does not erase an earlier attacker.
	l = _ledger()
	l.record_push(1, 2, 0)
	l.damage(1, 1, 10.0, 5)
	l.knock_out(1, 6)
	_check(l.credited_to(1) == 2, "self-damage keeps earlier attacker")
	# A later attacker replaces an earlier one; a push without damage counts.
	l = _ledger()
	l.damage(1, 2, 10.0, 0)
	l.record_push(1, 3, 10)
	l.knock_out(1, 20)
	_check(l.credited_to(1) == 3, "later attacker replaces earlier")
	# Window is measured from the latest attacker, not the first.
	l = _ledger()
	l.damage(1, 2, 10.0, 0)
	l.damage(1, 3, 10.0, CREDIT_WINDOW)
	l.knock_out(1, CREDIT_WINDOW * 2)
	_check(l.credited_to(1) == 3, "window measured from last hit")
	# Knockout happens once: no second knockout, no second repair.
	l = _ledger()
	l.damage(2, NO_ONE, 50.0, 0)
	l.damage(1, 2, 10.0, 0)
	l.knock_out(1, 1)
	l.end_tick()
	_check(not l.knock_out(1, 2) and not l.damage(1, 2, 5.0, 2) and _near(l.health_of(2), 70.0), "knockout happens once")


func _test_credit_order_and_repair() -> void:
	# Records arrive out of tick order: the newer tick wins, an equal tick replaces.
	# (The task's example used knock_out at 1100; with a 90-tick window that is outside it,
	# so the same sequence is checked at 1000 + window / 2.)
	var l: CombatLedger = _ledger()
	l.record_push(1, 3, 1000)
	l.record_push(1, 2, 500)
	l.knock_out(1, 1000 + CREDIT_WINDOW / 2)
	_check(l.credited_to(1) == 3, "older tick does not replace newer attacker")
	l = _ledger()
	l.record_push(1, 3, 1000)
	l.record_push(1, 2, 1000)
	l.knock_out(1, 1001)
	_check(l.credited_to(1) == 2, "equal tick replaces")
	# Mutual knockout on one tick, both call orders: both out, each credited, no repair.
	for first: int in [1, 2]:
		var second: int = 3 - first
		l = _ledger()
		l.damage(1, NO_ONE, 90.0, 0)
		l.damage(2, NO_ONE, 90.0, 0)
		l.damage(first, second, 15.0, 10)
		l.damage(second, first, 15.0, 10)
		l.end_tick()
		_check(l.is_knocked_out(1) and l.is_knocked_out(2), "mutual trade knocks out both (first=%d)" % first)
		_check(l.credited_to(1) == 2 and l.credited_to(2) == 1, "mutual trade credits each other (first=%d)" % first)
		_check(_near(l.health_of(1), 0.0) and _near(l.health_of(2), 0.0), "mutual trade repairs neither (first=%d)" % first)
	# Repair only after end_tick, and only once.
	l = _ledger()
	l.damage(2, NO_ONE, 50.0, 0)
	l.damage(1, 2, 10.0, 0)
	l.knock_out(1, 1)
	_check(_near(l.health_of(2), 50.0), "no repair before end_tick")
	l.end_tick()
	l.end_tick()
	_check(_near(l.health_of(2), 70.0), "end_tick twice repairs once")
	# Two knockouts by one attacker in one tick repair twice, capped at max.
	l = _ledger()
	l.damage(3, NO_ONE, 70.0, 0)
	l.damage(1, 3, 10.0, 0)
	l.damage(2, 3, 10.0, 0)
	l.knock_out(1, 1)
	l.knock_out(2, 1)
	l.end_tick()
	_check(_near(l.health_of(3), 70.0), "two knockouts repair twice")
	l = _ledger()
	l.damage(3, NO_ONE, 10.0, 0)
	l.damage(1, 3, 10.0, 0)
	l.damage(2, 3, 10.0, 0)
	l.knock_out(1, 1)
	l.knock_out(2, 1)
	l.end_tick()
	_check(_near(l.health_of(3), MAX_HEALTH), "double repair capped at max")


func _test_registration() -> void:
	# Id -1 is NO_FIGHTER and must not be registrable.
	var l: CombatLedger = _ledger()
	l.add_fighter(-1, MAX_HEALTH)
	l.damage(1, NO_ONE, 10.0, 0)
	l.knock_out(1, 1)
	# credited_to() returns -1 for "nobody", so also check -1 was never registered.
	_check(l.credited_to(1) == NO_ONE and _near(l.health_of(-1), 0.0), "id -1 is ignored")
	l.end_tick()
	_check(_near(l.health_of(-1), 0.0), "id -1 receives no repair")
	# Bad max health leaves the id unknown.
	var l2: CombatLedger = _ledger()
	var id: int = 10
	for bad: float in [NAN, INF, 0.0, -5.0]:
		id += 1
		l2.add_fighter(id, bad)
		_check(_near(l2.health_of(id), 0.0) and not l2.is_knocked_out(id) and not l2.damage(id, 1, 10.0, 0), "bad max health %s ignored" % bad)
	# A repair queued before a respawn is dropped: 2 knocks out 1 twice, respawns, takes 30.
	var l3: CombatLedger = _ledger()
	l3.damage(1, 2, 100.0, 10)
	l3.add_fighter(1, MAX_HEALTH)
	l3.damage(1, 2, 100.0, 10)
	l3.add_fighter(2, MAX_HEALTH)
	l3.damage(2, NO_ONE, 30.0, 10)
	l3.end_tick()
	_check(_near(l3.health_of(2), 70.0), "queued repairs do not survive a respawn")


func _test_nonfinite_math() -> void:
	var c: Vector2 = Vector2(1.0, 2.0)
	var nan_vec: Vector2 = Vector2(NAN, 0.0)
	var inf_vec: Vector2 = Vector2(INF, 0.0)
	var mult_cases: Array[Array] = [
		[NAN, THRESHOLD, MAX_MULT], [10.0, NAN, MAX_MULT], [10.0, INF, MAX_MULT],
		[10.0, THRESHOLD, NAN], [10.0, THRESHOLD, INF], [INF, THRESHOLD, MAX_MULT],
	]
	for args: Array in mult_cases:
		var m: float = CombatMath.push_multiplier(args[0], args[1], args[2])
		_check(is_finite(m) and m == 1.0, "non-finite multiplier args %s give 1" % [args])
	var blast_cases: Array[Array] = [
		[nan_vec, c, BLAST_PUSH, BLAST_RADIUS], [inf_vec, c, BLAST_PUSH, BLAST_RADIUS],
		[c, nan_vec, BLAST_PUSH, BLAST_RADIUS], [c, inf_vec, BLAST_PUSH, BLAST_RADIUS],
		[c, c, NAN, BLAST_RADIUS], [c, c, INF, BLAST_RADIUS],
		[c, c, BLAST_PUSH, NAN], [c, c, BLAST_PUSH, INF],
	]
	for args: Array in blast_cases:
		var p: Vector2 = CombatMath.blast_push(args[0], args[1], args[2], args[3])
		_check(p.is_finite() and p == Vector2.ZERO, "non-finite blast args %s give zero" % [args])
