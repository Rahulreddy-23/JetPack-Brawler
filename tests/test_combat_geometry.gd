extends SceneTree
## Run: godot --headless --path <project> --script res://tests/test_combat_geometry.gd
## Exits non-zero on any failed check, when a test function does not run to its end
## (each test returns true as its last statement; a script error aborts it and returns false),
## and when the engine reports any error (an ErrorCounter logger counts ERROR and SCRIPT ERROR;
## warnings are not counted).

const Geo: GDScript = preload("res://scripts/game/combat_geometry.gd")

## Comparison slack for fractions that are not exactly representable (for example 0.6).
const EPS: float = 0.000001
## Cross-check: samples per segment. One sample step is 1.0 / SAMPLES of the segment.
const SAMPLES: int = 1000
const CASES: int = 3000
## Cross-check: a reported hit point may sit this far outside the rectangle (float rounding).
const POINT_SLACK: float = 0.0001
const SEED: int = 20260101
## Cross-check coordinates are multiples of 1/16 or 1/1024, so every sum, difference and
## product in the exact reference test is exact in a double.
const COARSE: int = 16
const FINE: int = 1024
## Extent of the random coordinates in the cross-check.
const EXTENT: float = 50.0

## Used by most tests: x 10..40, y 20..60.
const R: Rect2 = Rect2(10.0, 20.0, 30.0, 40.0)

var _failures: int = 0
var _checks: int = 0
var _errors: ErrorCounter = ErrorCounter.new()


## Counts errors the engine reports (the lines printed as ERROR or SCRIPT ERROR).
class ErrorCounter extends Logger:
	var count: int = 0

	func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != Logger.ERROR_TYPE_WARNING:
			count += 1

	func _log_message(_message: String, _error: bool) -> void:
		pass


func _init() -> void:
	OS.add_logger(_errors)
	var tests: Array[Callable] = [
		test_segment_basic,
		test_segment_axis_aligned,
		test_segment_degenerate,
		test_cast,
		test_circle_rect,
		test_bad_inputs,
		test_cross_check,
	]
	for test: Callable in tests:
		var finished: bool = test.call() == true
		if not finished:
			_failures += 1
			print("FAIL: ", test.get_method(), " did not run to its end")
	if _errors.count > 0:
		_failures += 1
		print("FAIL: the engine reported ", _errors.count, " error(s)")
	print("checks: ", _checks, "  failures: ", _failures)
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: ", label)


func _near(actual: float, expected: float, label: String) -> void:
	_check(absf(actual - expected) <= EPS, "%s: got %s, expected %s" % [label, actual, expected])


func _seg(a: Vector2, b: Vector2) -> float:
	return Geo.segment_rect(a, b, R)


func test_segment_basic() -> bool:
	_check(_seg(Vector2(0, 40), Vector2(20, 40)) == 0.5, "clear hit, exact fraction")
	_near(_seg(Vector2(0, 40), Vector2(50, 40)), 0.2, "clear hit longer segment")
	_check(_seg(Vector2(0, 0), Vector2(20, 10)) == -1.0, "clear miss")
	_check(_seg(Vector2(0, 40), Vector2(8, 40)) == -1.0, "stops short")
	_check(_seg(Vector2(0, 40), Vector2(10, 40)) == 1.0, "ends exactly on the face")
	_check(_seg(Vector2(20, 30), Vector2(100, 30)) == 0.0, "starts inside")
	_check(_seg(Vector2(0, 10), Vector2(10, 20)) == 1.0, "ends on a corner")
	_check(_seg(Vector2(0, 30), Vector2(20, 10)) == 0.5, "passes through a corner only")
	_check(_seg(Vector2(0, 20), Vector2(80, 20)) == 0.125, "runs along the top edge")
	_check(_seg(Vector2(0, 60), Vector2(80, 60)) == 0.125, "runs along the bottom edge")
	_check(_seg(Vector2(0, 40), Vector2(-20, 40)) == -1.0, "pointing away")
	_check(_seg(Vector2(50, 40), Vector2(100, 40)) == -1.0, "past the far side, pointing away")
	_check(_seg(Vector2(80, 40), Vector2(0, 40)) == 0.5, "entering from the right")
	_check(_seg(Vector2(0, 0), Vector2(100, 10)) == -1.0, "shallow miss above")
	_check(_seg(Vector2(0, 19), Vector2(10, 19)) == -1.0, "parallel just above the edge")
	_check(Geo.segment_rect(Vector2(0, 5), Vector2(10, 5), Rect2(5, 5, 0, 0)) == 0.5, "zero-size rectangle")
	return true


func test_segment_axis_aligned() -> bool:
	_check(_seg(Vector2(25, 0), Vector2(25, 80)) == 0.25, "vertical hit")
	_check(_seg(Vector2(5, 0), Vector2(5, 80)) == -1.0, "vertical miss")
	_check(_seg(Vector2(10, 0), Vector2(10, 80)) == 0.25, "vertical along the left edge")
	_check(_seg(Vector2(40, 0), Vector2(40, 80)) == 0.25, "vertical along the right edge")
	_near(_seg(Vector2(25, 100), Vector2(25, 0)), 0.4, "vertical upward hit")
	_check(_seg(Vector2(25, 70), Vector2(25, 100)) == -1.0, "vertical pointing away")
	_check(_seg(Vector2(0, 40), Vector2(80, 40)) == 0.125, "horizontal hit")
	_check(_seg(Vector2(0, 70), Vector2(80, 70)) == -1.0, "horizontal miss")
	_check(_seg(Vector2(25, 40), Vector2(25, 100)) == 0.0, "vertical, starts inside")
	return true


func test_segment_degenerate() -> bool:
	_check(_seg(Vector2(20, 30), Vector2(20, 30)) == 0.0, "zero length inside")
	_check(_seg(Vector2(0, 0), Vector2(0, 0)) == -1.0, "zero length outside")
	_check(_seg(Vector2(10, 30), Vector2(10, 30)) == 0.0, "zero length on an edge")
	_check(_seg(Vector2(10, 20), Vector2(10, 20)) == 0.0, "zero length on a corner")
	_check(_seg(Vector2(9.5, 30), Vector2(9.5, 30)) == -1.0, "zero length just outside")
	return true


func test_cast() -> bool:
	var rects: Array[Rect2] = [Rect2(50, 0, 10, 10), Rect2(30, 0, 10, 10), Rect2(10, 0, 10, 10)]
	var hit: CastResult = Geo.cast(Vector2(0, 5), Vector2(100, 5), rects)
	_check(hit.index == 2, "nearest of several: index")
	_near(hit.t, 0.1, "nearest of several: t")
	_check(hit.normal == Vector2(-1, 0), "nearest of several: normal")

	var one: Array[Rect2] = [R]
	var left: CastResult = Geo.cast(Vector2(0, 40), Vector2(20, 40), one)
	_check(left.normal == Vector2(-1, 0) and left.index == 0 and left.t == 0.5, "enter through left face")
	var right: CastResult = Geo.cast(Vector2(80, 40), Vector2(30, 40), one)
	_check(right.normal == Vector2(1, 0) and right.index == 0, "enter through right face")
	var top: CastResult = Geo.cast(Vector2(25, 0), Vector2(25, 40), one)
	_check(top.normal == Vector2(0, -1) and top.index == 0, "enter through top face (y is down)")
	var bottom: CastResult = Geo.cast(Vector2(25, 100), Vector2(25, 50), one)
	_check(bottom.normal == Vector2(0, 1) and bottom.index == 0, "enter through bottom face")
	var diagonal: CastResult = Geo.cast(Vector2(0, 30), Vector2(20, 40), one)
	_check(diagonal.normal == Vector2(-1, 0), "diagonal entry through the left face")

	var inside: CastResult = Geo.cast(Vector2(20, 30), Vector2(100, 30), one)
	_check(inside.t == 0.0 and inside.index == 0 and inside.normal == Vector2.ZERO, "start inside: zero normal")

	var ties: Array[Rect2] = [Rect2(200, 0, 5, 5), R, R, R]
	var tie: CastResult = Geo.cast(Vector2(0, 40), Vector2(20, 40), ties)
	_check(tie.index == 1, "tie goes to the lowest index")
	var overlap: Array[Rect2] = [Rect2(10, 0, 5, 100), Rect2(10, 30, 5, 5)]
	_check(Geo.cast(Vector2(0, 32), Vector2(20, 32), overlap).index == 0, "same entry from different rects")

	# Corner entry reports the x face, whichever corner and direction.
	var corner_tl: CastResult = Geo.cast(Vector2(0, 30), Vector2(20, 10), one)
	_check(corner_tl.t == 0.5 and corner_tl.normal == Vector2(-1, 0), "corner entry top-left reports x face")
	var corner_br: CastResult = Geo.cast(Vector2(50, 70), Vector2(30, 50), one)
	_check(corner_br.t == 0.5 and corner_br.normal == Vector2(1, 0), "corner entry bottom-right reports x face")
	var corner_tr: CastResult = Geo.cast(Vector2(50, 10), Vector2(30, 30), one)
	_check(corner_tr.t == 0.5 and corner_tr.normal == Vector2(1, 0), "corner entry top-right reports x face")
	var corner_bl: CastResult = Geo.cast(Vector2(0, 90), Vector2(20, 30), one)
	_check(corner_bl.t == 0.5 and corner_bl.normal == Vector2(-1, 0), "corner entry bottom-left reports x face")
	# Starting exactly on the boundary: t = 0 and the zero normal, whichever way it moves.
	var on_surface: Array[Vector2] = [
		Vector2(10, 30), Vector2(40, 30), Vector2(25, 20), Vector2(25, 60), Vector2(10, 20), Vector2(40, 60),
	]
	var directions: Array[Vector2] = [
		Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1), Vector2(1, 1), Vector2(-1, -1), Vector2(1, -1),
	]
	for start: Vector2 in on_surface:
		for dir: Vector2 in directions:
			var res: CastResult = Geo.cast(start, start + dir * 25.0, one)
			_check(res.t == 0.0 and res.index == 0 and res.normal == Vector2.ZERO, "start on surface %s moving %s" % [start, dir])

	var empty: Array[Rect2] = []
	var none: CastResult = Geo.cast(Vector2(0, 0), Vector2(100, 100), empty)
	_check(none.t == -1.0 and none.index == -1 and none.normal == Vector2.ZERO, "empty list")
	var miss: CastResult = Geo.cast(Vector2(0, 0), Vector2(5, 0), one)
	_check(miss.t == -1.0 and miss.index == -1 and miss.normal == Vector2.ZERO, "no hit")
	return true


func test_circle_rect() -> bool:
	_check(Geo.circle_rect(Vector2(20, 30), 1.0, R), "centre inside")
	_check(Geo.circle_rect(Vector2(5, 40), 6.0, R), "overlapping an edge")
	_check(Geo.circle_rect(Vector2(7, 17), 5.0, R), "overlapping the corner region")
	_check(Geo.circle_rect(Vector2(5, 40), 5.0, R), "just touching an edge")
	_check(not Geo.circle_rect(Vector2(5, 40), 4.999, R), "just missing an edge")
	_check(Geo.circle_rect(Vector2(7, 16), 5.0, R), "just touching a corner (3, 4, 5)")
	_check(not Geo.circle_rect(Vector2(7, 16), 4.999, R), "just missing a corner")
	# Bounding box of this circle (2.8..11.2 on both axes) overlaps R, but the circle does not.
	_check(not Geo.circle_rect(Vector2(7, 17), 4.2, R), "diagonal miss at a corner")
	_check(Geo.circle_rect(Vector2(7, 17), 4.25, R), "diagonal hit at a corner")
	_check(Geo.circle_rect(Vector2(-100, 40), 200.0, R), "big circle, centre outside")
	_check(Geo.circle_rect(Vector2(20, 30), 0.0, R), "zero radius inside")
	_check(Geo.circle_rect(Vector2(10, 30), 0.0, R), "zero radius on an edge")
	_check(not Geo.circle_rect(Vector2(9, 30), 0.0, R), "zero radius outside")
	return true


func test_bad_inputs() -> bool:
	var bad: Array[float] = [NAN, INF, -INF]
	var good_rects: Array[Rect2] = [R]
	for v: float in bad:
		var label: String = str(v)
		var points: Array[Vector2] = [Vector2(v, 0), Vector2(0, v)]
		for p: Vector2 in points:
			_check(Geo.segment_rect(p, Vector2(20, 40), R) == -1.0, "segment a %s %s" % [label, p])
			_check(Geo.segment_rect(Vector2(0, 40), p, R) == -1.0, "segment b %s %s" % [label, p])
			var c1: CastResult = Geo.cast(p, Vector2(20, 40), good_rects)
			_check(c1.t == -1.0 and c1.index == -1 and c1.normal == Vector2.ZERO, "cast a %s %s" % [label, p])
			var c2: CastResult = Geo.cast(Vector2(0, 40), p, good_rects)
			_check(c2.t == -1.0 and c2.index == -1, "cast b %s %s" % [label, p])
			_check(not Geo.circle_rect(p, 1.0, R), "circle centre %s %s" % [label, p])
		var rects: Array[Rect2] = [
			Rect2(v, 20, 30, 40), Rect2(10, v, 30, 40), Rect2(10, 20, v, 40), Rect2(10, 20, 30, v),
		]
		for bad_rect: Rect2 in rects:
			_check(Geo.segment_rect(Vector2(0, 40), Vector2(20, 40), bad_rect) == -1.0, "segment rect %s" % label)
			_check(not Geo.circle_rect(Vector2(20, 30), 1.0, bad_rect), "circle rect %s" % label)
			var mixed: Array[Rect2] = [bad_rect, R]
			var c3: CastResult = Geo.cast(Vector2(0, 40), Vector2(20, 40), mixed)
			_check(c3.index == 1 and c3.t == 0.5, "cast skips a bad rect %s" % label)
			var only_bad: Array[Rect2] = [bad_rect]
			_check(Geo.cast(Vector2(0, 40), Vector2(20, 40), only_bad).index == -1, "cast only bad rect %s" % label)
		_check(not Geo.circle_rect(Vector2(20, 30), v, R), "circle radius %s" % label)
	_check(not Geo.circle_rect(Vector2(20, 30), -1.0, R), "negative radius")
	_check(not Geo.circle_rect(Vector2(20, 30), -0.001, R), "small negative radius")
	var negative: Array[Rect2] = [Rect2(10, 20, -30, 40), Rect2(10, 20, 30, -40), Rect2(10, 20, -30, -40)]
	for neg_rect: Rect2 in negative:
		_check(Geo.segment_rect(Vector2(0, 40), Vector2(80, 40), neg_rect) == -1.0, "segment negative size")
		_check(Geo.segment_rect(Vector2(20, 30), Vector2(20, 30), neg_rect) == -1.0, "zero-length negative size")
		_check(not Geo.circle_rect(Vector2(20, 30), 100.0, neg_rect), "circle negative size")
		var one_neg: Array[Rect2] = [neg_rect]
		_check(Geo.cast(Vector2(0, 40), Vector2(80, 40), one_neg).index == -1, "cast negative size")
	return true


## Brute force: first sample point along the segment that lies in the closed rectangle,
## as a fraction, or -1.0. Only used to classify grazes and to check the entry fraction.
func _sampled_entry(a: Vector2, b: Vector2, r: Rect2) -> float:
	for i: int in SAMPLES + 1:
		var t: float = float(i) / float(SAMPLES)
		var p: Vector2 = a + (b - a) * t
		if p.x >= r.position.x and p.x <= r.end.x and p.y >= r.position.y and p.y <= r.end.y:
			return t
	return -1.0


## Exact reference, written differently from the implementation (no division): the sign of
## the cross product of (q - p) and (s - p).
func _orient(p: Vector2, q: Vector2, s: Vector2) -> int:
	return int(signf((q.x - p.x) * (s.y - p.y) - (q.y - p.y) * (s.x - p.x)))


func _in_box(p: Vector2, q: Vector2, s: Vector2) -> bool:
	return s.x >= minf(p.x, q.x) and s.x <= maxf(p.x, q.x) and s.y >= minf(p.y, q.y) and s.y <= maxf(p.y, q.y)


## Closed segments p1p2 and p3p4 share at least one point.
func _segments_touch(p1: Vector2, p2: Vector2, p3: Vector2, p4: Vector2) -> bool:
	var o1: int = _orient(p1, p2, p3)
	var o2: int = _orient(p1, p2, p4)
	var o3: int = _orient(p3, p4, p1)
	var o4: int = _orient(p3, p4, p2)
	if o1 * o2 < 0 and o3 * o4 < 0:
		return true
	return (o1 == 0 and _in_box(p1, p2, p3)) or (o2 == 0 and _in_box(p1, p2, p4)) \
		or (o3 == 0 and _in_box(p3, p4, p1)) or (o4 == 0 and _in_box(p3, p4, p2))


func _contains(r: Rect2, p: Vector2) -> bool:
	return p.x >= r.position.x and p.x <= r.end.x and p.y >= r.position.y and p.y <= r.end.y


## Exact hit test: an endpoint is inside or on the rectangle, or the segment touches an edge.
func _exact_hit(a: Vector2, b: Vector2, r: Rect2) -> bool:
	if _contains(r, a) or _contains(r, b):
		return true
	var c0: Vector2 = r.position
	var c1: Vector2 = Vector2(r.end.x, r.position.y)
	var c2: Vector2 = r.end
	var c3: Vector2 = Vector2(r.position.x, r.end.y)
	return _segments_touch(a, b, c0, c1) or _segments_touch(a, b, c1, c2) \
		or _segments_touch(a, b, c2, c3) or _segments_touch(a, b, c3, c0)


## Exact idea of the entry normal for a hit: zero when a is inside or on the rectangle.
## Otherwise the face crossed last among the axes on which a is outside, compared by
## cross-multiplication (no division); a tie goes to x.
func _exact_normal(a: Vector2, b: Vector2, r: Rect2) -> Vector2:
	if _contains(r, a):
		return Vector2.ZERO
	var out_x: bool = a.x < r.position.x or a.x > r.end.x
	var out_y: bool = a.y < r.position.y or a.y > r.end.y
	var face_x: float = r.position.x if a.x < r.position.x else r.end.x
	var face_y: float = r.position.y if a.y < r.position.y else r.end.y
	var use_x: bool = out_x
	if out_x and out_y:
		# time_x = |face_x - a.x| / |dx|, time_y likewise; x wins unless y is strictly later.
		use_x = absf(face_y - a.y) * absf(b.x - a.x) <= absf(face_x - a.x) * absf(b.y - a.y)
	if use_x:
		return Vector2(-signf(b.x - a.x), 0.0)
	return Vector2(0.0, -signf(b.y - a.y))


func _quantize(rng: RandomNumberGenerator, unit: int) -> float:
	return float(rng.randi_range(-int(EXTENT) * unit, int(EXTENT) * unit)) / float(unit)


func _random_rect(rng: RandomNumberGenerator, unit: int) -> Rect2:
	var size: Vector2 = Vector2(
		float(rng.randi_range(0, 40 * unit)) / float(unit), float(rng.randi_range(0, 40 * unit)) / float(unit)
	)
	match rng.randi_range(0, 7):
		0:
			size.x = 0.0
		1:
			size.y = 0.0
	return Rect2(Vector2(_quantize(rng, unit), _quantize(rng, unit)), size)


## Mode 0: uniform. 1: through a corner. 2: through a corner, off by up to one quantum.
## 3: along an edge line, possibly one quantum off. 4: starts on a face or corner.
## 5: ends on a face or corner. 6: starts on a face and runs along or against it.
func _random_segment(rng: RandomNumberGenerator, r: Rect2, unit: int, mode: int) -> Array[Vector2]:
	var quantum: float = 1.0 / float(unit)
	var a: Vector2 = Vector2(_quantize(rng, unit), _quantize(rng, unit))
	var b: Vector2 = Vector2(_quantize(rng, unit), _quantize(rng, unit))
	var corners: Array[Vector2] = [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	var corner: Vector2 = corners[rng.randi_range(0, 3)]
	# A point on the boundary: a random point on one side, with the other coordinate on a face.
	var on_face: Vector2 = Vector2(
		r.position.x + r.size.x * float(rng.randi_range(0, 1)), r.position.y + r.size.y * float(rng.randi_range(0, 1))
	)
	if rng.randi_range(0, 1) == 0:
		on_face.x = r.position.x + float(rng.randi_range(0, int(r.size.x * float(unit)))) / float(unit)
	else:
		on_face.y = r.position.y + float(rng.randi_range(0, int(r.size.y * float(unit)))) / float(unit)
	var nudge: Vector2 = Vector2(float(rng.randi_range(-1, 1)), float(rng.randi_range(-1, 1))) * quantum
	match mode:
		1:
			b = a + (corner - a) * float(rng.randi_range(1, 3))
		2:
			b = a + (corner - a) * float(rng.randi_range(1, 3)) + nudge
		3:
			var edge_x: Array[float] = [r.position.x, r.end.x]
			var edge_y: Array[float] = [r.position.y, r.end.y]
			if rng.randi_range(0, 1) == 0:
				a.y = edge_y[rng.randi_range(0, 1)] + nudge.y
				b.y = a.y
			else:
				a.x = edge_x[rng.randi_range(0, 1)] + nudge.x
				b.x = a.x
		4:
			a = on_face
		5:
			b = on_face
		6:
			a = on_face + nudge
			if rng.randi_range(0, 1) == 0:
				b.x = a.x
			else:
				b.y = a.y
	return [a, b]


func test_cross_check() -> bool:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = SEED
	var step: float = 1.0 / float(SAMPLES)
	var worst_entry_gap: float = 0.0
	var worst_point_error: float = 0.0
	var hits: int = 0
	var misses: int = 0
	var grazes: int = 0
	var started_inside: int = 0
	var decision_mismatch: int = 0
	var normal_mismatch: int = 0
	var cast_bad: int = 0
	for case_index: int in CASES:
		var unit: int = COARSE if case_index % 2 == 0 else FINE
		var r: Rect2 = _random_rect(rng, unit)
		var seg: Array[Vector2] = _random_segment(rng, r, unit, rng.randi_range(0, 6))
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		var t: float = Geo.segment_rect(a, b, r)
		var expected_hit: bool = _exact_hit(a, b, r)
		_checks += 1
		if (t >= 0.0) != expected_hit:
			decision_mismatch += 1
			print("FAIL: hit decision a=%s b=%s r=%s code=%s exact=%s" % [a, b, r, t, expected_hit])
		var sampled: float = _sampled_entry(a, b, r)
		if expected_hit:
			hits += 1
			if sampled < 0.0:
				grazes += 1
			if _contains(r, a):
				started_inside += 1
		else:
			misses += 1
		if t >= 0.0 and expected_hit:
			# The entry point lies on the rectangle.
			var q: Vector2 = a + (b - a) * t
			var err: float = maxf(
				maxf(r.position.x - q.x, q.x - r.end.x), maxf(r.position.y - q.y, q.y - r.end.y)
			)
			worst_point_error = maxf(worst_point_error, err)
			_check(t <= 1.0 and err <= POINT_SLACK, "hit point lies on the rect: t=%s err=%s" % [t, err])
			if sampled >= 0.0:
				# Entry is at or before the first sample inside, and less than a step earlier.
				var gap: float = sampled - t
				worst_entry_gap = maxf(worst_entry_gap, absf(gap))
				_check(gap >= -EPS and gap <= step + EPS, "entry vs samples: t=%s sampled=%s" % [t, sampled])
			# The normal against the independent idea of the entry face.
			var one: Array[Rect2] = [r]
			var res: CastResult = Geo.cast(a, b, one)
			var expected_normal: Vector2 = _exact_normal(a, b, r)
			var unit_axis: bool = res.normal == Vector2.ZERO or (
				absf(res.normal.x) + absf(res.normal.y) == 1.0 and res.normal.length() == 1.0
			)
			_checks += 1
			if res.normal != expected_normal or not unit_axis or res.index != 0 or res.t != t:
				normal_mismatch += 1
				print("FAIL: normal a=%s b=%s r=%s got=%s expected=%s" % [a, b, r, res.normal, expected_normal])

		# cast over four rectangles must equal the manual nearest, lowest index first.
		var list: Array[Rect2] = [r]
		for _k: int in 3:
			list.append(_random_rect(rng, unit))
		var best_t: float = -1.0
		var best_i: int = -1
		for i: int in list.size():
			var ti: float = Geo.segment_rect(a, b, list[i])
			if ti >= 0.0 and (best_i < 0 or ti < best_t):
				best_t = ti
				best_i = i
		var result: CastResult = Geo.cast(a, b, list)
		if result.index != best_i or result.t != best_t:
			cast_bad += 1
	_check(decision_mismatch == 0, "hit or miss agrees with the exact test on every case (%d differ)" % decision_mismatch)
	_check(normal_mismatch == 0, "normal agrees with the exact test on every hit (%d differ)" % normal_mismatch)
	_check(cast_bad == 0, "cast agrees with segment_rect on every case (%d differ)" % cast_bad)
	_check(hits > 500 and misses > 500, "cross-check covers both outcomes")
	_check(grazes > 0, "cross-check contains grazes (hits that dense sampling misses)")
	_check(started_inside > 0, "cross-check contains starts inside or on the boundary")
	print("cross-check: cases=%d hits=%d misses=%d grazes=%d started inside or on boundary=%d" % [CASES, hits, misses, grazes, started_inside])
	print("cross-check: sample step=%s worst entry gap=%s worst point error=%s" % [step, worst_entry_gap, worst_point_error])
	return true
