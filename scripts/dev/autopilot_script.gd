class_name AutopilotScript
extends RefCounted
## Fixed scripted input for the network smoke test. Test scaffolding only:
## the numbers here are a test sequence, not gameplay tuning.

## Total length of the scripted part in seconds; the bot idles afterwards.
const LENGTH_SECONDS: float = 5.0

## Segments in order: end time in seconds, left stick, jetpack held.
const SEGMENTS: Array[Dictionary] = [
	{"end": 0.5, "move": Vector2(0.0, 0.0), "jet": false},
	{"end": 1.5, "move": Vector2(1.0, 0.0), "jet": false},
	{"end": 2.5, "move": Vector2(0.7, -0.7), "jet": true},
	{"end": 3.0, "move": Vector2(-1.0, 0.0), "jet": true},
	{"end": 3.5, "move": Vector2(-1.0, 0.0), "jet": false},
	{"end": 4.0, "move": Vector2(0.0, 1.0), "jet": false},
	{"end": 4.6, "move": Vector2(0.0, 0.0), "jet": false},
	{"end": 5.0, "move": Vector2(1.0, 0.0), "jet": false},
]

## Seconds at which the dash button is pressed for one tick. The first dash has
## the stick pushed right; the second, 3.2 s later (after the 3 s cooldown), has
## the stick neutral, so it goes the facing way (left, from the earlier run).
const DASH_AT_SECONDS: Array[float] = [1.0, 4.2]

## --autopilot-wiggle: the stick, the jetpack and the aim change every few ticks for the whole
## script instead of following the segments, so that an input that is filled in or replayed
## from the tick before differs from the real one on almost every tick (late-input tests).
static var wiggle: bool = false

## Input for the tick that is tick_offset ticks after the script start.
static func sample(tick_offset: int, tick_rate: int) -> Dictionary:
	if tick_offset < 0 or tick_offset >= int(LENGTH_SECONDS * tick_rate):
		return {}
	if wiggle:
		return {
			"move": Vector2(1.0 if (tick_offset / 2) % 2 == 0 else -1.0, 0.0),
			"jet": (tick_offset / 3) % 2 == 0,
			"aim": Vector2.from_angle(float(tick_offset) * 0.37),
		}
	var t: float = float(tick_offset) / float(tick_rate)
	var result: Dictionary = {"aim": Vector2.from_angle(t)}
	for segment: Dictionary in SEGMENTS:
		if t < (segment["end"] as float):
			result["move"] = segment["move"]
			result["jet"] = segment["jet"]
			break
	for dash_time: float in DASH_AT_SECONDS:
		if tick_offset == int(dash_time * tick_rate):
			result["dash"] = true
	return result
