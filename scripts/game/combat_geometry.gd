class_name CombatGeometry
extends RefCounted
## Pure hit-test geometry for the host. Static functions only, no state, no physics queries.
## Godot's y axis points down. All arithmetic is plain add, subtract, multiply, divide,
## compare, min and max on doubles, so results are identical on every device.


## Fraction (0 to 1) along a to b at which the segment first enters r, or -1.0 for no hit.
## Starting inside or exactly on the boundary returns 0.0; touching an edge or corner counts
## as a hit.
static func segment_rect(a: Vector2, b: Vector2, r: Rect2) -> float:
	if not _finite_point(a) or not _finite_point(b) or not _valid_rect(r):
		return -1.0
	return _slab(a.x, a.y, b.x, b.y, r.position.x, r.position.y, r.position.x + r.size.x, r.position.y + r.size.y, null)


## Nearest hit among rects. Ties go to the lowest index. A bad rectangle is skipped.
## A bad a or b gives an empty result.
## Normal rules: the normal is the outward unit normal of the face entered, which points
## against the segment's motion on that axis. A segment that enters exactly through a corner
## reports the x face (the unit vector along x pointing against the segment's x direction).
## A segment that starts inside the rectangle or exactly on its boundary gives t = 0.0 and the
## zero normal whichever way it moves; callers must treat a zero normal as "started inside or
## on the surface".
static func cast(a: Vector2, b: Vector2, rects: Array[Rect2]) -> CastResult:
	var result: CastResult = CastResult.new()
	if not _finite_point(a) or not _finite_point(b):
		return result
	var ax: float = a.x
	var ay: float = a.y
	var bx: float = b.x
	var by: float = b.y
	var min_x: float = minf(ax, bx)
	var max_x: float = maxf(ax, bx)
	var min_y: float = minf(ay, by)
	var max_y: float = maxf(ay, by)
	var best_t: float = -1.0
	var best_i: int = -1
	for i: int in rects.size():
		var r: Rect2 = rects[i]
		var px: float = r.position.x
		var py: float = r.position.y
		var sx: float = r.size.x
		var sy: float = r.size.y
		# Four finite values (read as doubles, so no overflow) have a finite sum; any NaN or
		# infinity makes it non-finite. Same test as _valid_rect with one call.
		if not (sx >= 0.0 and sy >= 0.0 and is_finite(px + py + sx + sy)):
			continue
		var hx: float = px + sx
		var hy: float = py + sy
		# Touching counts as overlapping, so grazes still reach the slab test.
		if hx < min_x or px > max_x or hy < min_y or py > max_y:
			continue
		var t: float = _slab(ax, ay, bx, by, px, py, hx, hy, null)
		if t >= 0.0 and (best_i < 0 or t < best_t):
			best_t = t
			best_i = i
	if best_i >= 0:
		var w: Rect2 = rects[best_i]
		_slab(ax, ay, bx, by, w.position.x, w.position.y, w.position.x + w.size.x, w.position.y + w.size.y, result)
		result.index = best_i
	return result


## Whether the circle overlaps r, touching included.
static func circle_rect(c: Vector2, radius: float, r: Rect2) -> bool:
	if not _finite_point(c) or not is_finite(radius) or radius < 0.0 or not _valid_rect(r):
		return false
	var dx: float = c.x - clampf(c.x, r.position.x, r.position.x + r.size.x)
	var dy: float = c.y - clampf(c.y, r.position.y, r.position.y + r.size.y)
	return dx * dx + dy * dy <= radius * radius


static func _finite_point(p: Vector2) -> bool:
	return is_finite(p.x) and is_finite(p.y)


static func _valid_rect(r: Rect2) -> bool:
	return _finite_point(r.position) and _finite_point(r.size) and r.size.x >= 0.0 and r.size.y >= 0.0


## Slab test on a validated segment and rectangle (lo and hi corners). Returns the entry
## fraction or -1.0; fills hit (t and normal) when it is not null.
static func _slab(ax: float, ay: float, bx: float, by: float, lox: float, loy: float, hix: float, hiy: float, hit: CastResult) -> float:
	var t_in: float = 0.0
	var t_out: float = 1.0
	var axis_in: int = -1
	var dir_in: float = 0.0
	var dx: float = bx - ax
	if dx == 0.0:
		# Parallel to this slab: it either stays inside it or never touches it.
		if ax < lox or ax > hix:
			return -1.0
	else:
		var t1: float = (lox - ax) / dx
		var t2: float = (hix - ax) / dx
		if t1 > t2:
			var swap: float = t1
			t1 = t2
			t2 = swap
		if t1 > t_in:
			t_in = t1
			axis_in = 0
			dir_in = dx
		t_out = minf(t_out, t2)
		if t_in > t_out:
			return -1.0
	var dy: float = by - ay
	if dy == 0.0:
		if ay < loy or ay > hiy:
			return -1.0
	else:
		var u1: float = (loy - ay) / dy
		var u2: float = (hiy - ay) / dy
		if u1 > u2:
			var swap_y: float = u1
			u1 = u2
			u2 = swap_y
		if u1 > t_in:
			t_in = u1
			axis_in = 1
			dir_in = dy
		t_out = minf(t_out, u2)
		if t_in > t_out:
			return -1.0
	if hit != null:
		hit.t = t_in
		hit.normal = Vector2.ZERO
		if axis_in == 0:
			hit.normal.x = -1.0 if dir_in > 0.0 else 1.0
		elif axis_in == 1:
			hit.normal.y = -1.0 if dir_in > 0.0 else 1.0
	return t_in
