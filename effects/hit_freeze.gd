class_name HitFreeze
extends Node
## Hit freeze for one visual, the way fighting games do it: the hit bot's picture stops for a
## few rendered frames while everything else keeps moving.
##
## Place it as a child of a visual Node2D (the target), or assign target. freeze() only arms it.
## In its own next _process (priority PROCESS_PRIORITY, after every node at a lower priority,
## so after other nodes' _process and after interpolation) it records the target's global and
## local transform, and from then on puts that global transform back every frame, so nothing that
## moves the target's parents can move it. When the freeze ends it restores the local transform
## the target had when the freeze began, so the visual is back under its parent as before.
## Whatever the visual would have drawn in the frame freeze() was called is what is held.
##
## Length rules, so a stream of hits can never hold the picture: a freeze has a total length,
## the longest request received while it runs, and frames already held count against it. Repeating
## the same request does not refill it; only a longer request extends it. After a freeze ends,
## freeze() calls are ignored for as many frames as it lasted, so the visual spends at least half
## of its time following its body.
##
## Contract: one HitFreeze per visual; two on the same target is unsupported and leaves it offset.
## The target is a visual child whose own local transform is not animated by other code during
## the freeze (the freeze overwrites it); the parents are free to move. Do not target the node
## the simulation moves (the CharacterBody2D itself), target its visual child.
## Presentation only: no screen capture, no render or engine settings, no pause, no time scale,
## and nothing that touches physics or netfox. The simulation is never aware of it.

## Runs after the default priority of 0 used by gameplay, animation and interpolation nodes.
const PROCESS_PRIORITY: int = 1000

var target: Node2D

var _armed: bool = false
var _active: bool = false
var _total: int = 0
var _held_count: int = 0
var _cooldown: int = 0
var _held: Transform2D = Transform2D.IDENTITY
var _local: Transform2D = Transform2D.IDENTITY


func _ready() -> void:
	if target == null:
		target = get_parent() as Node2D
	process_priority = PROCESS_PRIORITY


## Asks for a freeze of this many rendered frames. Ignored while not in the tree, without a live
## target, for frames of 0 or less, and during the cooldown after a freeze. While a freeze runs
## the longest request wins and frames already held count against it.
func freeze(frames: int) -> void:
	if frames <= 0 or _cooldown > 0 or not is_inside_tree():
		return
	if target == null or not is_instance_valid(target) or not target.is_inside_tree():
		return
	if _active or _armed:
		_total = maxi(_total, frames)
	else:
		_total = frames
		_armed = true


## True from the freeze() call until the freeze is released.
func is_frozen() -> bool:
	return _active or _armed


func _process(_delta: float) -> void:
	if not _active and not _armed:
		_cooldown = maxi(_cooldown - 1, 0)
		return
	if not is_instance_valid(target):
		_release(false)
		return
	if not target.is_inside_tree():
		_release(true)
		return
	if _armed:
		_held = target.global_transform
		_local = target.transform
		_held_count = 0
		_armed = false
		_active = true
	if _held_count >= _total:
		var lasted: int = _held_count
		_release(true)
		_cooldown = lasted
		return
	target.global_transform = _held
	_held_count += 1


func _release(restore: bool) -> void:
	if _active and restore and is_instance_valid(target):
		target.transform = _local
	_active = false
	_armed = false
	_held_count = 0
	_total = 0
	_cooldown = 0


func _exit_tree() -> void:
	_release(true)
