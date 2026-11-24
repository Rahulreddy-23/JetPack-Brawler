class_name Hit
extends RefCounted
## One hit collected by the weapon and gadget rules and applied by CombatRules, all
## inside the host's resolver pass for one tick. Never stored between ticks.

## The bot that takes the hit.
var victim: Bot
## Peer id of the attacker (a bot's peer_id), or Bot.NO_PEER for the hazard.
var attacker_peer: int = Bot.NO_PEER
## Health removed, before the self-damage scale.
var damage: float = 0.0
## Push in bot heights per second, before push_speed_scale and the low-health multiplier.
var push: Vector2 = Vector2.ZERO
## True for a bullet: ignored while the victim is dashing.
var bullet: bool = false
## False for a push that must not be scaled by the low-health multiplier.
var scale_push: bool = true
