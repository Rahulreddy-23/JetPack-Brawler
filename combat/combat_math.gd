extends RefCounted
## Stateless push maths. Distances and pushes are in bot heights.


## 1 at or above threshold health, rising linearly to max_multiplier at 0 health.
static func push_multiplier(health: float, threshold: float, max_multiplier: float) -> float:
	if not (is_finite(health) and is_finite(threshold) and is_finite(max_multiplier)):
		return 1.0
	if threshold <= 0.0 or health >= threshold:
		return 1.0
	return lerpf(max_multiplier, 1.0, maxf(health, 0.0) / threshold)


## The speed (units per second) that carries a body `distance` units against a constant
## deceleration `decel` (units per second squared), when every tick of length `dt` first cuts the
## speed by decel x dt and then moves the body, which is how Bot brakes and falls. Without the
## tick the answer would be sqrt(2 x decel x distance); the half-step terms make the sum over
## whole ticks come out at `distance` (to well under one percent for pushes above 0.1).
static func launch_speed(distance: float, decel: float, dt: float) -> float:
	if not (is_finite(distance) and is_finite(decel) and is_finite(dt)):
		return 0.0
	if distance <= 0.0 or decel <= 0.0 or dt <= 0.0:
		return 0.0
	var half_step: float = decel * dt / 2.0
	return half_step + sqrt(2.0 * decel * distance + half_step * half_step)


## The inverse of launch_speed: the distance a body moving at `speed` still covers against a
## constant deceleration `decel` with ticks of length `dt` (zero at or below one tick of braking,
## which stops it before it moves). launch_speed(travel_distance(v)) is v for v above
## decel x dt, and travel_distance(launch_speed(d)) is d for d above zero.
static func travel_distance(speed: float, decel: float, dt: float) -> float:
	if not (is_finite(speed) and is_finite(decel) and is_finite(dt)):
		return 0.0
	if speed <= 0.0 or decel <= 0.0 or dt <= 0.0:
		return 0.0
	return maxf(speed * (speed - decel * dt) / (2.0 * decel), 0.0)


## Push on a target from a blast: centre_push at the centre, linear to zero at radius,
## zero beyond. Points away from the centre; straight up (Vector2.UP) at the exact centre.
static func blast_push(target: Vector2, centre: Vector2, centre_push: float, radius: float) -> Vector2:
	if not (target.is_finite() and centre.is_finite() and is_finite(centre_push) and is_finite(radius)):
		return Vector2.ZERO
	var offset: Vector2 = target - centre
	var distance: float = offset.length()
	if radius <= 0.0 or distance >= radius:
		return Vector2.ZERO
	var strength: float = centre_push * (1.0 - distance / radius)
	if distance == 0.0:
		return Vector2.UP * strength
	return offset / distance * strength
