extends RefCounted
## Health plus knockout credit for every fighter, keyed by integer id. Pure logic, called by
## the host on its network tick. Callers set the tuning fields from the shared config.
## The host calls end_tick() once after applying all hits for a tick: knockout repairs are
## queued until then, so a same-tick trade knocks out both fighters and repairs neither.

const FighterHealth := preload("res://combat/fighter_health.gd")

const NO_FIGHTER: int = -1

## Set by the caller before use.
var knockout_repair: float = 0.0
var credit_window_ticks: int = 0

var _fighters: Dictionary = {}  # int -> FighterHealth
var _last_attacker: Dictionary = {}  # int -> int
var _last_attack_tick: Dictionary = {}  # int -> int
var _credited_to: Dictionary = {}  # int -> int, set when a fighter is knocked out
var _pending_repairs: Array[int] = []  # attacker ids, applied by end_tick()


## Registers a fighter, or re-registers it at full health with no history (respawn).
## Ignored for a negative id (it would collide with NO_FIGHTER) and for a max health that is
## not finite or not above zero.
func add_fighter(id: int, max_health: float) -> void:
	if id < 0 or not is_finite(max_health) or max_health <= 0.0:
		return
	_fighters[id] = FighterHealth.new(max_health)
	_last_attacker.erase(id)
	_last_attack_tick.erase(id)
	_credited_to.erase(id)
	# A repair earned in the previous life must not carry over to the respawn.
	while _pending_repairs.has(id):
		_pending_repairs.erase(id)


func health_of(id: int) -> float:
	if not _fighters.has(id):
		return 0.0
	var fighter: FighterHealth = _fighters[id]
	return fighter.health


func is_knocked_out(id: int) -> bool:
	if not _fighters.has(id):
		return false
	var fighter: FighterHealth = _fighters[id]
	return fighter.knocked_out


## Who was credited with this fighter's knockout, or NO_FIGHTER (self-knockout, or not out).
func credited_to(id: int) -> int:
	return _credited_to.get(id, NO_FIGHTER)


## Damage from attacker (NO_FIGHTER for the hazard or the map edge). Returns true if this
## call knocked the victim out.
func damage(victim: int, attacker: int, amount: float, tick: int) -> bool:
	if not _fighters.has(victim):
		return false
	var health: FighterHealth = _fighters[victim]
	var before: float = health.health
	var knocked_out: bool = health.apply_damage(amount)
	if health.health < before:
		_record(victim, attacker, tick)
	if knocked_out:
		_finish_knockout(victim, tick)
	return knocked_out


## A push with no damage still makes the pusher the last attacker.
func record_push(victim: int, attacker: int, tick: int) -> void:
	if _fighters.has(victim) and not is_knocked_out(victim):
		_record(victim, attacker, tick)


## Hazard or map-edge knockout that ignores health. Returns true if newly knocked out.
func knock_out(victim: int, tick: int) -> bool:
	if not _fighters.has(victim):
		return false
	var fighter: FighterHealth = _fighters[victim]
	if not fighter.force_knock_out():
		return false
	_finish_knockout(victim, tick)
	return true


## Applies the repairs queued by credited knockouts this tick, then clears the queue.
## A knocked-out attacker gets nothing, because a knocked-out fighter cannot be healed.
func end_tick() -> void:
	for attacker: int in _pending_repairs:
		var fighter: FighterHealth = _fighters[attacker]
		fighter.heal(knockout_repair)
	_pending_repairs.clear()


## A fighter never becomes its own last attacker; unknown ids are ignored. A record older
## than the stored one is ignored too, because the netcode can re-run earlier ticks.
func _record(victim: int, attacker: int, tick: int) -> void:
	if attacker == victim or not _fighters.has(attacker):
		return
	if _last_attack_tick.has(victim) and tick < int(_last_attack_tick[victim]):
		return
	_last_attacker[victim] = attacker
	_last_attack_tick[victim] = tick


func _finish_knockout(victim: int, tick: int) -> void:
	var attacker: int = _last_attacker.get(victim, NO_FIGHTER)
	if attacker == NO_FIGHTER or tick - int(_last_attack_tick[victim]) > credit_window_ticks:
		return
	_credited_to[victim] = attacker
	_pending_repairs.append(attacker)
