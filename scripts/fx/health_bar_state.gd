class_name HealthBarState
extends RefCounted
## Decides when the thin health bar above a bot is on screen (BotVisual draws it). The bar shows
## when the bot's health value changes (damage, a repair, a respawn back to full) and stays for a
## hold, which restarts on every further change. The first value seen is not a change, so the bar
## stays hidden for a bot that has just appeared or whose first real state has just arrived; reset()
## makes the next value a first sight again (a session starts or stops). While the bot is knocked
## out the bar is hidden. Presentation only: the hold runs on the frame clock handed to tick(), it
## reads health and writes nothing to the simulation.
##
## The value compared is the one seen at the frame, the last one observe() was given, not anything
## in between, so a value that flickers during a re-simulation and ends where it started shows
## nothing.

var _last: float = 0.0
var _primed: bool = false
var _hold_left: float = 0.0

## Forget what was seen: the next observed value is a first sight and the bar is hidden.
func reset() -> void:
	_primed = false
	_hold_left = 0.0

## Look at the bot's health on this frame. hold_seconds is the config's hold.
func observe(health: float, hold_seconds: float, knocked_out: bool) -> void:
	if not is_finite(health):
		return
	if knocked_out:
		_hold_left = 0.0
	elif _primed and health != _last:
		_hold_left = hold_seconds
	_last = health
	_primed = true

## Advance the hold by one frame.
func tick(delta: float) -> void:
	_hold_left = maxf(_hold_left - delta, 0.0)

## True while the bar is on screen.
func showing() -> bool:
	return _hold_left > 0.0

## How full the bar is, 0 to 1.
static func fraction(health: float, max_health: float) -> float:
	if max_health <= 0.0 or not is_finite(health):
		return 0.0
	return clampf(health / max_health, 0.0, 1.0)

## True at or below the health where the extra push starts, so the bar changes colour there.
static func is_low(health: float, low_health_threshold: float) -> bool:
	return health <= low_health_threshold
