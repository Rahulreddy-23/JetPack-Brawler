extends RefCounted
## Stateless push maths. Distances and pushes are in bot heights.


## 1 at or above threshold health, rising linearly to max_multiplier at 0 health.
static func push_multiplier(health: float, threshold: float, max_multiplier: float) -> float:
	if not (is_finite(health) and is_finite(threshold) and is_finite(max_multiplier)):
		return 1.0
	if threshold <= 0.0 or health >= threshold:
		return 1.0
	return lerpf(max_multiplier, 1.0, maxf(health, 0.0) / threshold)


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
