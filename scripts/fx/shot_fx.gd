class_name ShotFx
extends Node2D
## Draws muzzle flashes, tracer lines and melee arcs as plain shapes (child of the effects
## director, in world space). Fixed rings of entries, sized once in configure(): adding an entry
## overwrites the oldest, nothing is created per shot, so sustained fire allocates nothing.
## A tracer only shows where a shot flew. It carries no impact mark and never implies a hit:
## the host decides hits. Presentation only; runs on frame time.

const ARC_POINTS: int = 16
const FLASH_COLOR: Color = Color(1.0, 0.95, 0.7)

## Radius in pixels and total width in radians of the arcs drawn for a swing (from the config).
var swing_radius: float = 0.0
var swing_span: float = 0.0

var _tracer_seconds: float = 0.0
var _tracer_width: float = 0.0
var _flash_seconds: float = 0.0
var _flash_radius: float = 0.0
var _shot_life: float = 0.0
var _arc_seconds: float = 0.0
var _arc_width: float = 0.0

var _shot_from: PackedVector2Array = PackedVector2Array()
var _shot_to: PackedVector2Array = PackedVector2Array()
var _shot_color: PackedColorArray = PackedColorArray()
var _shot_line: PackedByteArray = PackedByteArray()
var _shot_left: PackedFloat32Array = PackedFloat32Array()
var _shot_next: int = 0

var _arc_center: PackedVector2Array = PackedVector2Array()
var _arc_angle: PackedFloat32Array = PackedFloat32Array()
var _arc_color: PackedColorArray = PackedColorArray()
var _arc_left: PackedFloat32Array = PackedFloat32Array()
var _arc_next: int = 0

func _ready() -> void:
	set_process(false)

## Reads the numbers and sizes the rings. Call once, before the first entry.
func configure(cfg: TuningConfig) -> void:
	_tracer_seconds = cfg.tracer_seconds
	_tracer_width = cfg.tracer_width_px
	_flash_seconds = cfg.muzzle_flash_seconds
	_flash_radius = cfg.muzzle_flash_radius_px
	_shot_life = maxf(_tracer_seconds, _flash_seconds)
	_arc_seconds = cfg.melee_arc_seconds
	_arc_width = cfg.melee_arc_width_px
	swing_radius = cfg.melee_range * cfg.bot_height_px
	swing_span = deg_to_rad(cfg.melee_arc_degrees)
	_shot_from.resize(cfg.fx_pool_size)
	_shot_to.resize(cfg.fx_pool_size)
	_shot_color.resize(cfg.fx_pool_size)
	_shot_line.resize(cfg.fx_pool_size)
	_shot_left.resize(cfg.fx_pool_size)
	_shot_left.fill(0.0)
	_arc_center.resize(cfg.fx_pool_size)
	_arc_angle.resize(cfg.fx_pool_size)
	_arc_color.resize(cfg.fx_pool_size)
	_arc_left.resize(cfg.fx_pool_size)
	_arc_left.fill(0.0)
	_shot_next = 0
	_arc_next = 0

## A muzzle flash at from and, when with_tracer is true, a tracer line from there to to.
func add_shot(from: Vector2, to: Vector2, color: Color, with_tracer: bool) -> void:
	if _shot_left.is_empty():
		return
	_shot_from[_shot_next] = from
	_shot_to[_shot_next] = to
	_shot_color[_shot_next] = color
	_shot_line[_shot_next] = 1 if with_tracer else 0
	_shot_left[_shot_next] = _shot_life
	_shot_next = (_shot_next + 1) % _shot_left.size()
	set_process(true)
	queue_redraw()

## A melee arc around center, centred on the direction dir.
func add_swing(center: Vector2, dir: Vector2, color: Color) -> void:
	if _arc_left.is_empty():
		return
	_arc_center[_arc_next] = center
	_arc_angle[_arc_next] = dir.angle()
	_arc_color[_arc_next] = color
	_arc_left[_arc_next] = _arc_seconds
	_arc_next = (_arc_next + 1) % _arc_left.size()
	set_process(true)
	queue_redraw()

## Index of the entry add_shot filled last, for tests.
func last_shot_index() -> int:
	return (_shot_next - 1 + _shot_left.size()) % _shot_left.size()

## Where the tracer of an entry ends, for tests.
func shot_end(index: int) -> Vector2:
	return _shot_to[index]

## Angle in radians the last arc is centred on, for tests.
func last_swing_angle() -> float:
	return _arc_angle[(_arc_next - 1 + _arc_left.size()) % _arc_left.size()]

## Whether an entry draws a tracer line, for tests.
func shot_has_tracer(index: int) -> bool:
	return _shot_line[index] == 1

## Where the muzzle flash of an entry is, for tests.
func shot_start(index: int) -> Vector2:
	return _shot_from[index]

## Entries still showing: shots (flash and tracer) plus arcs.
func active_count() -> int:
	var count: int = 0
	for left: float in _shot_left:
		if left > 0.0:
			count += 1
	for left: float in _arc_left:
		if left > 0.0:
			count += 1
	return count

## Entries in the two rings together.
func capacity() -> int:
	return _shot_left.size() + _arc_left.size()

func _process(delta: float) -> void:
	var live: bool = false
	for i: int in _shot_left.size():
		if _shot_left[i] > 0.0:
			_shot_left[i] -= delta
			live = live or _shot_left[i] > 0.0
	for i: int in _arc_left.size():
		if _arc_left[i] > 0.0:
			_arc_left[i] -= delta
			live = live or _arc_left[i] > 0.0
	# One more redraw after the last entry ends clears it from the screen.
	queue_redraw()
	if not live:
		set_process(false)

func _draw() -> void:
	for i: int in _shot_left.size():
		if _shot_left[i] <= 0.0:
			continue
		var age: float = _shot_life - _shot_left[i]
		var tracer_alpha: float = clampf(1.0 - age / _tracer_seconds, 0.0, 1.0) if _tracer_seconds > 0.0 else 0.0
		if tracer_alpha > 0.0 and _shot_line[i] == 1:
			var line_color: Color = _shot_color[i].lerp(Color.WHITE, 0.5)
			line_color.a = tracer_alpha
			draw_line(_shot_from[i], _shot_to[i], line_color, _tracer_width)
		var flash_alpha: float = clampf(1.0 - age / _flash_seconds, 0.0, 1.0) if _flash_seconds > 0.0 else 0.0
		if flash_alpha > 0.0:
			var flash_color: Color = FLASH_COLOR
			flash_color.a = flash_alpha
			draw_circle(_shot_from[i], _flash_radius, flash_color)
	for i: int in _arc_left.size():
		if _arc_left[i] <= 0.0:
			continue
		var arc_color: Color = _arc_color[i].lerp(Color.WHITE, 0.5)
		arc_color.a = clampf(_arc_left[i] / _arc_seconds, 0.0, 1.0) if _arc_seconds > 0.0 else 0.0
		draw_arc(_arc_center[i], swing_radius, _arc_angle[i] - swing_span * 0.5, _arc_angle[i] + swing_span * 0.5, ARC_POINTS, arc_color, _arc_width)
