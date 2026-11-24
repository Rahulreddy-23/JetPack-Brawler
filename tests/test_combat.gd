extends SceneTree
## Run: godot --headless --path <project> --script res://tests/test_combat.gd
## Exits non-zero on any failure. GDD numbers appear only here.

const CombatMath := preload("res://combat/combat_math.gd")

const THRESHOLD: float = 25.0
const MAX_MULT: float = 2.0
const BLAST_PUSH: float = 5.0
const BLAST_RADIUS: float = 3.0

var _failures: int = 0


func _init() -> void:
	_test_push_multiplier()
	_test_blast()
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
