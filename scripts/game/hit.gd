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
## Push in bot heights per second. How it is applied depends on scale_push and launch:
## - scale_push true, launch false (default): a velocity change of push x push_speed_scale,
##   times the low-health multiplier, added to the victim's velocity.
## - scale_push false, launch false: a velocity change of push exactly, already a speed, added
##   to the victim's velocity.
## - launch true (a Spring Plate): a speed with no scale and no multiplier. Its vertical part
##   REPLACES the victim's vertical velocity, its horizontal part is added.
## Every push ends a dash first (velocity becomes the dash exit velocity), sets the push window
## and credits the attacker.
var push: Vector2 = Vector2.ZERO
## True for a bullet: ignored while the victim is dashing.
var bullet: bool = false
## False for a push that must not be scaled by push_speed_scale and the low-health multiplier.
var scale_push: bool = true
## True for a plate launch: see push. scale_push is not read when launch is true.
var launch: bool = false
