extends Node
## Regression tests for active unmerged geminiceo fixes (G-27) against origin/main (7c2da44).
## Every check fails on origin/main without its fix.
## Run:
##   godot --headless --path . res://tests/test_security_audit.tscn
## Exits 0 when every check passes, 1 otherwise.

const TIMEOUT_SECONDS: float = 30.0

var _failures: int = 0
var _checks: int = 0
var _cfg: TuningConfig = TuningConfig.get_default()

func _ready() -> void:
	get_tree().create_timer(TIMEOUT_SECONDS).timeout.connect(_on_timeout)
	_run()

func _on_timeout() -> void:
	print("FAIL timeout, security audit test did not finish")
	get_tree().quit(1)

func _check(ok: bool, label: String) -> void:
	_checks += 1
	if ok:
		print("PASS ", label)
	else:
		_failures += 1
		print("FAIL ", label)

func _run() -> void:
	InputActions.ensure_registered()
	_test_touch_flick_curve_then_pull_back_inside_ring()
	print("%d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)

func _test_touch_flick_curve_then_pull_back_inside_ring() -> void:
	var touch: TouchControls = TouchControls.new()
	touch.size = Vector2(1280.0, 720.0)
	add_child(touch)
	var origin: Vector2 = Vector2(900.0, 500.0)
	var out_dist: float = _cfg.stick_radius_px * (_cfg.fire_ring_fraction + 0.15)
	var in_dist: float = _cfg.stick_radius_px * (_cfg.fire_ring_fraction - 0.15)
	InputActions.pending_touch_fire_aim = Vector2.ZERO
	touch._touch(1, origin, true)
	touch._drag(1, origin + Vector2(out_dist, 0.0))
	touch._drag(1, origin + Vector2(0.0, -out_dist))
	touch._drag(1, origin + Vector2(0.0, -in_dist))
	touch._touch(1, origin + Vector2(0.0, -in_dist), false)
	var captured: Vector2 = InputActions.pending_touch_fire_aim
	_check(captured.y < -0.5 and absf(captured.x) < 0.2,
		"G-27: curved flick pulled back inside ring before tick keeps curved aim (got %s)" % [captured])
	InputActions.pending_touch_fire_aim = Vector2.ZERO
	touch.free()
