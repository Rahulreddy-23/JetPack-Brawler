extends SceneTree
## Run: godot --headless --path <project> --script res://tests/test_hazard.gd
## Exits 1 on any failure.

const HazardMath: GDScript = preload("res://hazard/hazard_math.gd")
const VisualScene: PackedScene = preload("res://hazard/hazard_visual.tscn")

const TICK_RATE: int = 30
const START_S: float = 30.0
const CAP_S: float = 45.0
const FLOOR_Y: float = 1000.0 # larger y = lower on screen
const TOP_Y: float = 100.0

var failures: int = 0


func _init() -> void:
	_test_levels()
	_test_constant_speed()
	_test_bad_config()
	_test_query()
	_test_no_hidden_state()
	_test_degenerate()
	_test_visual()
	if failures > 0:
		print("FAILED: %d check(s)" % failures)
	else:
		print("ALL PASSED")
	quit(1 if failures > 0 else 0)


func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", label)


func _level(ticks: int) -> float:
	return HazardMath.surface_y(ticks, TICK_RATE, START_S, CAP_S, FLOOR_Y, TOP_Y)


func _in_metal(bottom_y: float, ticks: int) -> bool:
	return HazardMath.is_in_metal(bottom_y, ticks, TICK_RATE, START_S, CAP_S, FLOOR_Y, TOP_Y)


func _test_levels() -> void:
	_check(_level(0) == FLOOR_Y, "tick 0 at floor")
	_check(_level(899) == FLOOR_Y, "just before start (tick 899) at floor")
	_check(_level(900) == FLOOR_Y, "at start (tick 900) at floor")
	_check(_level(901) < FLOOR_Y, "one tick after start has risen (y decreased)")
	_check(is_equal_approx(_level(1125), (FLOOR_Y + TOP_Y) * 0.5), "midway 37.5 s is half way")
	_check(_level(1350) == TOP_Y, "at cap (tick 1350) at top")
	_check(_level(1351) == TOP_Y, "after cap stays at top")
	_check(_level(100000) == TOP_Y, "long after cap stays at top")
	_check(_level(1000) >= _level(1100) and _level(1100) >= _level(1300), "monotonic rise")
	# Nothing is in the metal before the start time, not even a body below the floor line; from the
	# start time on a body below the floor line is.
	_check(not _in_metal(FLOOR_Y + 0.0013, 0) and not _in_metal(FLOOR_Y + 50.0, 899), "before the start time a body at or below the floor line is not in the metal")
	_check(not _in_metal(FLOOR_Y + 50.0, -1), "with no round (negative ticks) nothing is in the metal")
	_check(_in_metal(FLOOR_Y + 0.0013, 900) and not _in_metal(FLOOR_Y, 900), "at the start time the bare comparison holds: below the floor line is in the metal, on it is not")


## Expected level for a tick on a straight line from the floor at START_S to the top at CAP_S.
func _linear_level(ticks: int) -> float:
	var progress: float = (float(ticks) / float(TICK_RATE) - START_S) / (CAP_S - START_S)
	return FLOOR_Y + (TOP_Y - FLOOR_Y) * progress


func _test_constant_speed() -> void:
	# 33.75 s and 41.25 s are half a tick off the grid, so check the ticks either side.
	for t: int in [1012, 1013, 1237, 1238, 950, 1300]:
		_check(is_equal_approx(_level(t), _linear_level(t)), "tick %d matches the straight line" % t)
	var step: float = _level(1000) - _level(1100)
	_check(step > 0.0, "level falls (y decreases) over 100 ticks")
	_check(is_equal_approx(_level(1100) - _level(1200), step), "equal tick steps give equal level steps (1100 to 1200)")
	_check(is_equal_approx(_level(1200) - _level(1300), step), "equal tick steps give equal level steps (1200 to 1300)")
	_check(is_equal_approx(_level(901) - _level(902), _level(1349) - _level(1350)), "step at the start equals step at the cap")


func _test_bad_config() -> void:
	var nan: float = NAN
	var inf: float = INF
	# Swapped floor and top: no body in the metal at tick 0, mid-rise or after the cap.
	for t: int in [0, 1125, 1350, 5000]:
		_check(not HazardMath.is_in_metal(500.0, t, TICK_RATE, START_S, CAP_S, TOP_Y, FLOOR_Y), "swapped floor/top: no metal at tick %d" % t)
		_check(not HazardMath.is_in_metal(TOP_Y, t, TICK_RATE, START_S, CAP_S, TOP_Y, FLOOR_Y), "swapped floor/top: no metal at tick %d (body at top)" % t)
	# Each non-finite float input: no body in the metal and no NaN from surface_y.
	var bad: Array[Array] = [
		[nan, CAP_S, FLOOR_Y, TOP_Y], [inf, CAP_S, FLOOR_Y, TOP_Y], [-inf, CAP_S, FLOOR_Y, TOP_Y],
		[START_S, nan, FLOOR_Y, TOP_Y], [START_S, inf, FLOOR_Y, TOP_Y], [START_S, -inf, FLOOR_Y, TOP_Y],
		[START_S, CAP_S, nan, TOP_Y], [START_S, CAP_S, inf, TOP_Y], [START_S, CAP_S, -inf, TOP_Y],
		[START_S, CAP_S, FLOOR_Y, nan], [START_S, CAP_S, FLOOR_Y, inf], [START_S, CAP_S, FLOOR_Y, -inf],
	]
	for args: Array in bad:
		for t: int in [0, 1125, 1350, 5000]:
			var level: float = HazardMath.surface_y(t, TICK_RATE, args[0], args[1], args[2], args[3])
			_check(not is_nan(level), "non-finite input %s gives no NaN at tick %d" % [str(args), t])
			for body_y: float in [-1000.0, TOP_Y, 500.0, FLOOR_Y, 5000.0]:
				_check(not HazardMath.is_in_metal(body_y, t, TICK_RATE, args[0], args[1], args[2], args[3]), "non-finite input %s: no metal at tick %d" % [str(args), t])
		_check(not HazardMath.is_config_valid(TICK_RATE, args[0], args[1], args[2], args[3]), "is_config_valid false for %s" % str(args))
	# Validity function.
	_check(HazardMath.is_config_valid(TICK_RATE, START_S, CAP_S, FLOOR_Y, TOP_Y), "is_config_valid true for the GDD values")
	_check(HazardMath.is_config_valid(TICK_RATE, START_S, CAP_S, FLOOR_Y, FLOOR_Y), "is_config_valid true when top == floor")
	_check(not HazardMath.is_config_valid(TICK_RATE, START_S, CAP_S, TOP_Y, FLOOR_Y), "is_config_valid false for swapped floor/top")
	_check(not HazardMath.is_config_valid(0, START_S, CAP_S, FLOOR_Y, TOP_Y), "is_config_valid false for zero tick rate")
	_check(not HazardMath.is_config_valid(-1, START_S, CAP_S, FLOOR_Y, TOP_Y), "is_config_valid false for negative tick rate")
	# Visual stays hidden when given INF.
	var visual: ColorRect = VisualScene.instantiate() as ColorRect
	visual.set("floor_y", FLOOR_Y)
	visual.set("arena_width", 2000.0)
	root.add_child(visual)
	visual.call("set_surface_y", HazardMath.surface_y(1125, TICK_RATE, START_S, CAP_S, TOP_Y, FLOOR_Y))
	_check(not visual.visible, "visual hidden for a bad-config surface (INF)")
	_check(visual.size.y == 0.0 and not is_nan(visual.position.y), "visual has zero height and no NaN for INF")
	visual.free()


func _test_query() -> void:
	var tick: int = 1125
	var surface: float = _level(tick)
	_check(_in_metal(surface + 1.0, tick), "bottom below surface is in metal")
	_check(not _in_metal(surface - 1.0, tick), "bottom above surface is not in metal")
	_check(not _in_metal(surface, tick), "bottom exactly on surface is not in metal")
	_check(not _in_metal(FLOOR_Y, 0), "body on floor safe before start")
	_check(not _in_metal(FLOOR_Y, 900), "body on floor safe at start")
	_check(_in_metal(FLOOR_Y, 901), "body on floor in metal one tick after start")
	_check(_in_metal(TOP_Y + 1.0, 1350), "everything below top is in metal at cap")


func _test_no_hidden_state() -> void:
	var order_a: Array[int] = [1350, 0, 1125, 901, 1125, 5000, 0]
	var order_b: Array[int] = [0, 5000, 1125, 901, 1125, 0, 1350]
	var seen: Dictionary = {}
	var consistent: bool = true
	for ticks: Array[int] in [order_a, order_b, order_a]:
		for t: int in ticks:
			var level: float = _level(t)
			if seen.has(t) and seen[t] != level:
				consistent = false
			seen[t] = level
	_check(consistent, "same tick gives same level when repeated and out of order")


func _test_degenerate() -> void:
	# Each call must simply return; reaching the next line proves no crash.
	_check(HazardMath.surface_y(1000, 0, START_S, CAP_S, FLOOR_Y, TOP_Y) == FLOOR_Y, "zero tick rate gives floor")
	_check(HazardMath.surface_y(1000, -5, START_S, CAP_S, FLOOR_Y, TOP_Y) == FLOOR_Y, "negative tick rate gives floor")
	_check(HazardMath.surface_y(-1, TICK_RATE, START_S, CAP_S, FLOOR_Y, TOP_Y) == FLOOR_Y, "negative ticks give floor")
	_check(HazardMath.surface_y(1350, TICK_RATE, 45.0, 45.0, FLOOR_Y, TOP_Y) == TOP_Y, "cap == start jumps to top")
	_check(HazardMath.surface_y(1349, TICK_RATE, 45.0, 45.0, FLOOR_Y, TOP_Y) == FLOOR_Y, "cap == start stays at floor before")
	_check(HazardMath.surface_y(1000, TICK_RATE, 45.0, 30.0, FLOOR_Y, TOP_Y) == FLOOR_Y, "cap before start, before start time: floor")
	_check(HazardMath.surface_y(1400, TICK_RATE, 45.0, 30.0, FLOOR_Y, TOP_Y) == TOP_Y, "cap before start, after start time: top")
	_check(HazardMath.surface_y(1125, TICK_RATE, START_S, CAP_S, FLOOR_Y, FLOOR_Y) == FLOOR_Y, "top == floor gives floor")
	_check(not HazardMath.is_in_metal(FLOOR_Y, 1125, TICK_RATE, START_S, CAP_S, FLOOR_Y, FLOOR_Y), "top == floor: nothing in metal")
	_check(not HazardMath.is_in_metal(FLOOR_Y, 5, 0, START_S, CAP_S, FLOOR_Y, TOP_Y), "zero tick rate: nothing in metal")


func _test_visual() -> void:
	var visual: ColorRect = VisualScene.instantiate() as ColorRect
	_check(visual != null, "visual scene instantiates as ColorRect")
	if visual == null:
		return
	visual.set("floor_y", FLOOR_Y)
	visual.set("arena_width", 2000.0)
	root.add_child(visual)
	var surface: float = _level(1125)
	visual.call("set_surface_y", surface)
	_check(is_equal_approx(visual.position.y, surface), "visual top edge equals surface level")
	_check(is_equal_approx(visual.position.y + visual.size.y, FLOOR_Y), "visual bottom edge at floor")
	_check(is_equal_approx(visual.size.x, 2000.0), "visual spans arena width")
	_check(visual.visible, "visual visible while metal is up")
	visual.call("set_surface_y", _level(0))
	_check(not visual.visible, "visual hidden before hazard starts")
	visual.call("set_surface_y", TOP_Y)
	_check(is_equal_approx(visual.position.y, TOP_Y), "visual top edge at top at cap")
	visual.free()
