class_name WeaponStats
extends Resource
## Numbers of one weapon, used four times inside config/tuning.tres (indexed by
## ItemIds weapon id). Distances and speeds are in bot heights (bh). Times are in
## seconds; rules convert them to ticks. Every value is a first guess for
## playtesting, except where a comment names the GDD. Zero is a real value only
## where a comment says so.

## Damage of one hit; for the scrap blaster, of one pellet.
@export var damage: float = 0.0
## Push of one hit as a DISTANCE in bh, before the low-health multiplier (GDD: the bot is
## pushed this far on flat ground with a neutral stick, see CombatRules). GDD values: bolt
## thrower 0.1; scrap blaster 1.5 in total at close range (pellets x push, so 0.25 per pellet).
## The rivet gun's is not in the GDD (first guess, close to the bolt thrower's).
@export var push: float = 0.0
## Seconds between shots.
@export var fire_interval: float = 0.0
## Shots a picked-up weapon holds. Ignored when infinite_ammo is true.
@export var ammo: int = 0
## True for the starting weapon.
@export var infinite_ammo: bool = false
## Longest distance a shot or projectile travels, bh.
@export var range_bh: float = 0.0
## Pellets per shot (1 for single-shot weapons).
@export var pellets: int = 0
## Total cone of the pellets, degrees. Zero for a single exact shot.
@export var spread_degrees: float = 0.0
## Recoil: a push on the shooter opposite to the aim, a distance in bh like push and under the
## same rule (CombatRules.push_change). GDD: scrap blaster 1. Zero for no recoil.
@export var recoil: float = 0.0
## Projectile speed, bh/s. Zero means the shot is instant (hit test along a line).
@export var projectile_speed: float = 0.0
## Projectile radius for the contact test, bh. Zero for instant shots.
@export var projectile_radius: float = 0.0
## Blast radius, bh. Zero for weapons that do not blast.
@export var blast_radius: float = 0.0
## Blast push at the centre as a distance in bh; falls linearly to zero at the radius. Zero for no blast.
@export var blast_push: float = 0.0
## Blast damage at the centre. Zero for no blast.
@export var blast_damage: float = 0.0
