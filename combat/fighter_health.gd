extends RefCounted
## Health of one fighter. No regeneration. Pure logic: no nodes, no physics.

var max_health: float
var health: float
var knocked_out: bool = false


func _init(max_health_value: float) -> void:
	max_health = max_health_value
	health = max_health_value


## Returns true only when this call is the one that knocked the fighter out.
## Zero, negative and non-finite damage, and damage to a knocked-out fighter, are ignored.
func apply_damage(amount: float) -> bool:
	if knocked_out or not is_finite(amount) or amount <= 0.0:
		return false
	health = maxf(health - amount, 0.0)
	if health <= 0.0:
		knocked_out = true
		return true
	return false


## A knocked-out fighter cannot be healed. Non-finite and non-positive amounts are ignored.
func heal(amount: float) -> void:
	if knocked_out or not is_finite(amount) or amount <= 0.0:
		return
	health = minf(health + amount, max_health)


## Knock out regardless of health (hazard, map edge). Returns true if newly knocked out.
func force_knock_out() -> bool:
	if knocked_out:
		return false
	health = 0.0
	knocked_out = true
	return true
