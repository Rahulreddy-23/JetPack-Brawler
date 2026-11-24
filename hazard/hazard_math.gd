extends RefCounted
## Closing-hazard (rising metal) logic. Pure functions of the tick, no state, no nodes.
## Godot's y axis points DOWN: floor_y is the LARGER number, top_y the SMALLER one.
## The metal surface starts at floor_y and moves up (y decreases) to top_y.
## Hazard time is measured from the round start (the tick after the countdown ends).


## Metal surface y at a tick. Rises at constant speed from start_time_s so it reaches top_y at cap_time_s.
## Bad config (a non-finite start, cap, floor or top, or floor_y < top_y) returns INF, meaning
## "no metal anywhere": is_in_metal is false for every finite body and the visual hides itself.
## Other degenerate inputs: tick_rate <= 0 or negative ticks give floor_y; cap_time_s <= start_time_s
## jumps from floor_y to top_y at start_time_s; top_y == floor_y gives floor_y.
static func surface_y(ticks_since_round_start: int, tick_rate: int, start_time_s: float, cap_time_s: float, floor_y: float, top_y: float) -> float:
	if not (is_finite(start_time_s) and is_finite(cap_time_s) and is_finite(floor_y) and is_finite(top_y)) or floor_y < top_y:
		return INF
	if tick_rate <= 0 or ticks_since_round_start < 0:
		return floor_y
	var time_s: float = float(ticks_since_round_start) / float(tick_rate)
	if time_s < start_time_s:
		return floor_y
	var duration_s: float = cap_time_s - start_time_s
	if duration_s <= 0.0:
		return top_y
	var progress: float = clampf((time_s - start_time_s) / duration_s, 0.0, 1.0)
	return lerpf(floor_y, top_y, progress)


## True when the inputs describe a usable hazard: finite floats, floor_y >= top_y, tick_rate > 0.
## The code that wires the shared config calls this once and reports a bad config loudly.
static func is_config_valid(tick_rate: int, start_time_s: float, cap_time_s: float, floor_y: float, top_y: float) -> bool:
	return tick_rate > 0 and is_finite(start_time_s) and is_finite(cap_time_s) and is_finite(floor_y) and is_finite(top_y) and floor_y >= top_y


## True when a body whose lowest point is bottom_y is below the metal surface (larger y) at this tick.
## A body resting exactly on the surface is not in the metal.
static func is_in_metal(bottom_y: float, ticks_since_round_start: int, tick_rate: int, start_time_s: float, cap_time_s: float, floor_y: float, top_y: float) -> bool:
	return bottom_y > surface_y(ticks_since_round_start, tick_rate, start_time_s, cap_time_s, floor_y, top_y)
