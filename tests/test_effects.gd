extends SceneTree
## Headless test for the impact feel kit.
## Run: godot --headless --path <project> --script res://tests/test_effects.gd
## Exits non-zero on any failure, and also when any test function did not run to its end (a
## script error inside an awaited test function only aborts that function).
## Needs the project imported once so class_name lookups work.

const TEST_NAMES: Array[String] = ["burst", "cap", "shake", "flash", "freeze"]

var _failures: int = 0
var _completed: Array[String] = []
var _parent: Mover
var _child: Node2D
var _freezer: HitFreeze


## A parent that moves every frame in its own _process (default priority, before HitFreeze).
class Mover extends Node2D:
	var step: Vector2 = Vector2.ZERO
	var spin: float = 0.0
	var grow: float = 1.0

	func _process(_delta: float) -> void:
		position += step
		rotation += spin
		scale *= grow


## Stands in for netfox: at default priority, inside its own _process, it puts the parent at a
## "tick" position, raises the hit, then moves the parent to the "interpolated" position.
## It must be added to the tree after the parent so it runs after the parent's movement.
class Driver extends Node:
	var parent: Node2D
	var freezer: HitFreeze
	var armed: bool = false

	func _process(_delta: float) -> void:
		if not armed:
			return
		armed = false
		parent.position = Vector2(100.0, 100.0)
		freezer.freeze(3)
		parent.position = Vector2(200.0, 200.0)


func _initialize() -> void:
	# The root is not inside the tree yet during _initialize.
	await process_frame
	await _run()
	for test_name: String in TEST_NAMES:
		_check(_completed.has(test_name), "test function '%s' ran to its end" % test_name)
	print("RESULT: %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("ok   - ", message)
	else:
		_failures += 1
		printerr("FAIL - ", message)


func _done(test_name: String) -> void:
	_completed.append(test_name)


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _make_burst(count: int, lifetime: float, cap: int) -> PartsBurst:
	var burst: PartsBurst = PartsBurst.new()
	burst.piece_count = count
	burst.lifetime = lifetime
	burst.fade_time = lifetime * 0.5
	burst.impulse = 300.0
	burst.impulse_variation = 0.5
	burst.spread_degrees = 90.0
	burst.spin = 5.0
	burst.piece_size_min = 4.0
	burst.piece_size_max = 10.0
	burst.bounce = 0.4
	burst.max_debris = cap
	root.add_child(burst)
	return burst


func _run() -> void:
	await _test_burst()
	await _test_cap()
	await _test_shake()
	await _test_flash()
	await _test_freeze()


func _test_burst() -> void:
	var burst: PartsBurst = _make_burst(10, 0.3, 100)
	burst.burst(Vector2(100.0, 100.0), Color.GRAY, Vector2.UP)
	_check(DebrisPiece.live.size() == 10, "burst creates the requested number of pieces")
	var pieces: Array[DebrisPiece] = DebrisPiece.live.duplicate()
	var layers_ok: bool = true
	for p: DebrisPiece in pieces:
		layers_ok = layers_ok and p.collision_layer == DebrisLayers.DEBRIS and p.collision_mask == DebrisLayers.WORLD
	_check(layers_ok, "debris layer is exactly DEBRIS and mask is exactly WORLD")
	_check(DebrisLayers.DEBRIS != DebrisLayers.WORLD and (DebrisLayers.DEBRIS & DebrisLayers.WORLD) == 0, "DEBRIS and WORLD are different bits")
	await _wait(0.8)
	var all_freed: bool = true
	for p: DebrisPiece in pieces:
		all_freed = all_freed and not is_instance_valid(p)
	_check(all_freed and DebrisPiece.live.size() == 0, "all pieces freed after the lifetime")
	burst.queue_free()
	_done("burst")


func _test_cap() -> void:
	var cap: int = 15
	var burst: PartsBurst = _make_burst(10, 5.0, cap)
	var created: Array[DebrisPiece] = []
	for i: int in 6:
		burst.burst(Vector2(100.0, 100.0), Color.GRAY, Vector2.UP)
		created.append_array(DebrisPiece.live.slice(DebrisPiece.live.size() - 10))
	_check(DebrisPiece.live.size() == cap, "debris cap holds after 60 pieces requested (live = %d)" % DebrisPiece.live.size())
	_check(DebrisPiece.live == created.slice(created.size() - cap), "the newest pieces survive, the oldest go first")
	_check(created[0].is_queued_for_deletion(), "the very first piece was freed")
	_check(not created[created.size() - 1].is_queued_for_deletion(), "the newest piece is alive")
	for p: DebrisPiece in DebrisPiece.live.duplicate():
		p.queue_free()
	burst.queue_free()
	await _wait(0.1)
	_check(DebrisPiece.live.size() == 0, "registry empties when pieces are freed")
	_done("cap")


func _test_shake() -> void:
	var camera: Camera2D = Camera2D.new()
	root.add_child(camera)
	var shake: ScreenShake = ScreenShake.new()
	shake.decay_per_second = 200.0
	camera.add_child(shake)
	_check(camera.offset == Vector2.ZERO, "shake offset is zero before")
	shake.shake(20.0)
	var peak: float = 0.0
	var start: int = Engine.get_process_frames()
	while shake.is_shaking() and Engine.get_process_frames() - start < 600:
		await process_frame
		peak = maxf(peak, camera.offset.length())
	_check(peak > 0.0, "shake offset is non-zero during (peak %.1f px)" % peak)
	_check(not shake.is_shaking(), "shake finishes by decaying")
	_check(camera.offset == Vector2.ZERO, "shake offset is exactly zero after")

	# Adds on top of another offset and gives it back unchanged.
	camera.offset = Vector2(7.0, -3.0)
	shake.shake(20.0)
	start = Engine.get_process_frames()
	while shake.is_shaking() and Engine.get_process_frames() - start < 600:
		await process_frame
	_check(camera.offset == Vector2(7.0, -3.0), "an existing camera offset is preserved")
	camera.offset = Vector2.ZERO

	# The shake must not advance the global random sequence.
	seed(7)
	var expected: float = randf()
	seed(7)
	shake.shake(20.0)
	for i: int in 5:
		await process_frame
	_check(randf() == expected, "shake does not consume the global random generator")
	while shake.is_shaking():
		await process_frame

	shake.reduce_shake = 0.0
	shake.shake(20.0)
	var any_offset: bool = false
	for i: int in 10:
		await process_frame
		any_offset = any_offset or camera.offset != Vector2.ZERO
	_check(not any_offset, "reduce shake 0 scales the shake to zero")
	shake.reduce_shake = 5.0
	_check(shake.reduce_shake == 1.0, "reduce shake is clamped to 0..1")
	camera.queue_free()
	_done("shake")


func _flash_params(item: CanvasItem) -> ShaderMaterial:
	return item.material as ShaderMaterial


func _test_flash() -> void:
	var item: Node2D = Node2D.new()
	var tint: Color = Color(0.2, 0.4, 0.6, 0.8)
	var preexisting: CanvasItemMaterial = CanvasItemMaterial.new()
	item.modulate = tint
	item.material = preexisting
	root.add_child(item)
	var flash: HitFlash = HitFlash.new()
	item.add_child(flash)

	flash.flash(0.3)
	_check(flash.is_flashing() and _flash_params(item) != null and item.material != preexisting, "flash puts its shader material on the target")
	_check(_flash_params(item).get_shader_parameter("flash_color") == Color.WHITE, "default flash colour is white")
	_check(item.modulate == tint, "flash does not touch modulate")

	# Timing is driven by hand so a slow machine cannot change the outcome.
	flash.set_process(false)
	flash._process(0.2)
	_check(flash.is_flashing(), "still flashing 0.2 s into a 0.3 s flash")
	flash.flash(0.3, Color.RED, 0.5)
	flash.set_process(false)
	_check(_flash_params(item).get_shader_parameter("flash_color") == Color.RED, "retrigger sets the new flash colour")
	_check(_flash_params(item).get_shader_parameter("amount") == 0.5, "retrigger sets the new amount")
	flash._process(0.2)
	_check(flash.is_flashing(), "retrigger restarted the timer (0.4 s after the first call, still flashing)")
	item.modulate = Color(1.0, 0.0, 0.0, 1.0)
	flash._process(0.2)
	_check(not flash.is_flashing() and item.material == preexisting, "the pre-existing material is restored after a retrigger")
	_check(item.modulate == Color(1.0, 0.0, 0.0, 1.0), "a tint set by another system during the flash survives")

	# Durations that are not finite or not above zero, and amounts that are not finite, are ignored.
	item.material = preexisting
	var bad_durations: Array[float] = [NAN, INF, 0.0, -1.0]
	for bad: float in bad_durations:
		flash.flash(bad)
		_check(not flash.is_flashing() and item.material == preexisting, "flash(%s) is ignored" % bad)
	flash.flash(0.1, Color.WHITE, NAN)
	_check(not flash.is_flashing() and item.material == preexisting, "flash with a NaN amount is ignored")
	flash.flash(0.1, Color.WHITE, INF)
	_check(not flash.is_flashing() and item.material == preexisting, "flash with an infinite amount is ignored")

	# Other code replaces the material mid-flash; a retrigger takes the new material as the one to restore.
	var replacement: CanvasItemMaterial = CanvasItemMaterial.new()
	flash.flash(10.0)
	flash.set_process(false)
	item.material = replacement
	flash.flash(10.0)
	flash.set_process(false)
	_check(item.material is ShaderMaterial and item.material != replacement, "a retrigger puts the flash material back after it was replaced")
	flash._process(11.0)
	_check(not flash.is_flashing() and item.material == replacement, "the replacement material is the one restored")

	# Real time, with a wide margin, and no previous material.
	item.material = null
	flash.flash(0.05)
	_check(item.material != null, "flash applies the material (no previous material case)")
	await _wait(0.5)
	_check(not flash.is_flashing() and item.material == null, "a null previous material is restored after a real-time flash")

	flash.flash(10.0)
	item.remove_child(flash)
	_check(item.material == null, "leaving the tree mid-flash restores the previous material")
	flash.free()

	var loose: HitFlash = HitFlash.new()
	loose.target = item
	loose.flash(0.1)
	_check(not loose.is_flashing() and item.material == null, "flash() before the node is in the tree is ignored")
	loose.free()
	item.queue_free()
	_done("flash")


func _build_rig(step: Vector2, spin: float, grow: float) -> void:
	if _parent != null:
		_parent.free()
	_parent = Mover.new()
	_parent.step = step
	_parent.spin = spin
	_parent.grow = grow
	_child = Node2D.new()
	_child.position = Vector2(3.0, 4.0)
	_child.rotation = 0.3
	_child.scale = Vector2(2.0, 2.0)
	_freezer = HitFreeze.new()
	_child.add_child(_freezer)
	_parent.add_child(_child)
	root.add_child(_parent)




func _same(a: Transform2D, b: Transform2D, exact: bool) -> bool:
	return a == b if exact else a.is_equal_approx(b)


## Counts consecutive frame starts at which the child still sits at the held transform.
func _count_held(held: Transform2D, exact: bool) -> int:
	var count: int = 0
	while count < 100:
		await process_frame
		if not _same(_child.global_transform, held, exact):
			break
		count += 1
	return count


## Calls freeze(frames) at a frame start and returns how many frames the child stayed held.
## The held picture is recorded in the freezer's own process, so it is read after that frame.
func _freeze_and_count(frames: int, exact: bool) -> int:
	_freezer.freeze(frames)
	await process_frame
	return 1 + await _count_held(_child.global_transform, exact)


func _test_freeze() -> void:
	# Parent translates by whole pixels, so the held transform is bit-exact.
	_build_rig(Vector2(5.0, 3.0), 0.0, 1.0)
	await process_frame
	await process_frame
	var local: Transform2D = _child.transform
	_freezer.freeze(4)
	_check(_freezer.is_frozen(), "freeze is armed after the call")
	await process_frame
	var count: int = 1 + await _count_held(_child.global_transform, true)
	_check(count == 4, "child held bit-exactly for exactly 4 frames (held %d)" % count)
	_check(not _freezer.is_frozen(), "freeze is over after its frames")
	_check(_child.transform == local, "the original local transform is restored")
	_check(_child.global_transform == _parent.global_transform * local, "the child follows the parent again")

	# Rotating and scaling parent: held to float precision.
	_build_rig(Vector2(7.5, -2.25), 0.1, 1.01)
	await process_frame
	await process_frame
	local = _child.transform
	count = await _freeze_and_count(3, false)
	_check(count == 3, "child held for exactly 3 frames under a rotating and scaling parent (held %d)" % count)
	_check(_child.transform.is_equal_approx(local), "local transform restored under a rotating parent")
	_check(_child.global_transform.is_equal_approx(_parent.global_transform * local), "the child follows the rotating parent again")

	# A longer request mid-freeze extends the total length to the longer one.
	_build_rig(Vector2(5.0, 3.0), 0.0, 1.0)
	await process_frame
	_freezer.freeze(3)
	await process_frame
	var held: Transform2D = _child.global_transform
	_freezer.freeze(6)
	count = 1 + await _count_held(held, true)
	_check(count == 6, "a longer request extends the freeze to a total of 6 (held %d)" % count)

	# A shorter request does not shorten it.
	_build_rig(Vector2(5.0, 3.0), 0.0, 1.0)
	await process_frame
	_freezer.freeze(6)
	await process_frame
	held = _child.global_transform
	_freezer.freeze(1)
	count = 1 + await _count_held(held, true)
	_check(count == 6, "a shorter request does not shorten it (held %d, expected 6)" % count)

	# The same request repeated mid-freeze does not refill it.
	_build_rig(Vector2(5.0, 3.0), 0.0, 1.0)
	await process_frame
	_freezer.freeze(3)
	await process_frame
	held = _child.global_transform
	_freezer.freeze(3)
	count = 1 + await _count_held(held, true)
	_check(count == 3, "repeating the same request does not refill the freeze (held %d, expected 3)" % count)

	# A stream of hits: freeze(3) every 2 frames for 200 frames.
	_build_rig(Vector2(5.0, 3.0), 0.0, 1.0)
	await process_frame
	await process_frame
	local = _child.transform
	var previous: Transform2D = _child.global_transform
	var run: int = 0
	var max_run: int = 0
	var held_frames: int = 0
	for i: int in 200:
		if i % 2 == 0:
			_freezer.freeze(3)
		await process_frame
		var now: Transform2D = _child.global_transform
		run = run + 1 if now == previous else 0
		max_run = maxi(max_run, run)
		# A held spot is drawn for one more frame than the frames equal to their predecessor.
		held_frames += 1 if run > 0 else 0
		held_frames += 1 if run == 1 else 0
		previous = now
	_check(max_run == 2, "a stream never holds the picture at one spot for more than 3 frames (longest run of equal frames after the first: %d)" % max_run)
	_check(held_frames * 2 <= 200, "the visual follows its body at least half the time in a stream (held %d of 200)" % held_frames)
	for i: int in 10:
		await process_frame
	_check(_child.transform == local and _child.global_transform == _parent.global_transform * local, "after the stream the visual sits exactly on its parent with the original local transform")

	# freeze() called from inside another node's _process, between a tick and interpolation.
	_build_rig(Vector2(5.0, 3.0), 0.0, 1.0)
	var driver: Driver = Driver.new()
	driver.parent = _parent
	driver.freezer = _freezer
	root.add_child(driver)
	await process_frame
	await process_frame
	driver.armed = true
	await process_frame
	_check(_child.global_position == Vector2(203.0, 204.0), "the held picture is the interpolated position, from the same frame (at %s)" % _child.global_position)
	count = 1 + await _count_held(_child.global_transform, true)
	_check(count == 3, "a freeze raised inside another node's _process holds exactly 3 frames (held %d)" % count)
	driver.free()

	# The target is freed mid-freeze.
	_build_rig(Vector2(5.0, 3.0), 0.0, 1.0)
	var detached: HitFreeze = HitFreeze.new()
	detached.target = _child
	root.add_child(detached)
	await process_frame
	detached.freeze(30)
	await process_frame
	_child.free()
	await process_frame
	await process_frame
	_check(not detached.is_frozen(), "freeze ends quietly when its target is freed")
	detached.free()

	# An assigned target that is not a child leaves the tree mid-freeze, then comes back.
	_build_rig(Vector2(5.0, 3.0), 0.0, 1.0)
	var external: Node2D = Node2D.new()
	external.position = Vector2(10.0, 20.0)
	var external_local: Transform2D = external.transform
	_parent.add_child(external)
	var assigned: HitFreeze = HitFreeze.new()
	assigned.target = external
	root.add_child(assigned)
	await process_frame
	assigned.freeze(30)
	for i: int in 3:
		await process_frame
	_check(external.transform != external_local, "precondition: the hold overwrote the target's local transform")
	_parent.remove_child(external)
	await process_frame
	_check(not assigned.is_frozen(), "freeze ends when its target leaves the tree")
	_parent.add_child(external)
	_check(external.transform == external_local, "the target that left the tree has its original local transform back")
	assigned.free()

	# The HitFreeze node leaves the tree mid-freeze.
	_build_rig(Vector2(5.0, 3.0), 0.0, 1.0)
	await process_frame
	local = _child.transform
	_freezer.freeze(30)
	await process_frame
	await process_frame
	_freezer.free()
	_check(_child.transform == local, "leaving the tree mid-freeze restores the local transform")
	await process_frame
	_check(_child.global_transform == _parent.global_transform * local, "nothing stays held after the node left the tree")

	# Not in the tree, and a zero request, are ignored.
	var loose: HitFreeze = HitFreeze.new()
	loose.target = _child
	loose.freeze(3)
	_check(not loose.is_frozen(), "freeze() before the node is in the tree is ignored")
	loose.free()
	_build_rig(Vector2(5.0, 3.0), 0.0, 1.0)
	_freezer.freeze(0)
	_check(not _freezer.is_frozen(), "a zero-frame freeze is ignored")
	_parent.free()
	_done("freeze")
