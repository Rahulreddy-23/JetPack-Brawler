extends Node
## The HUD shows health, the active weapon with its ammo, the weapon in the other slot and
## the held gadgets, and redraws only when one of the values it shows changes.
## Run: godot --headless --path . res://tests/test_hud.tscn

const BOT_SCENE: PackedScene = preload("res://scenes/bot.tscn")
const SETTLE_FRAMES: int = 5
const QUIET_FRAMES: int = 20
const TIMEOUT_SECONDS: float = 30.0

var _failed: bool = false
var _cfg: TuningConfig = TuningConfig.get_default()
var _hud: Hud = null
var _bot: Bot = null

func _ready() -> void:
	get_tree().create_timer(TIMEOUT_SECONDS).timeout.connect(_on_timeout)
	_run.call_deferred()

func _on_timeout() -> void:
	print("FAIL timeout, the test did not finish")
	get_tree().quit(1)

func _check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		_failed = true

func _settle() -> void:
	for i: int in SETTLE_FRAMES:
		await get_tree().process_frame

# Change something with `change`, let frames pass, and return how many redraws it caused.
func _redraws_after(change: Callable) -> int:
	var before: int = _hud.draw_count
	change.call()
	await _settle()
	return _hud.draw_count - before

func _set_weapons(active_slot: int, picked: int, ammo: int) -> void:
	_bot.arsenal.active_slot = active_slot
	_bot.arsenal.picked_weapon = picked
	_bot.arsenal.picked_ammo = ammo

func _run() -> void:
	InputActions.ensure_registered()
	_hud = Hud.new()
	add_child(_hud)
	_bot = BOT_SCENE.instantiate() as Bot
	add_child(_bot)
	await _settle()
	_check(_hud.info_lines().is_empty() and _hud.health_text().is_empty(), "no bot: nothing is shown")
	_hud.bot = _bot
	await _settle()
	_check(_hud.draw_count >= 1, "a bot appears: the HUD draws")
	_check(_hud.health_text() == "HEALTH %d" % int(_cfg.max_health), "a new bot shows full health (%s)" % _hud.health_text())

	# Nothing changes: no redraw in many frames.
	var quiet_before: int = _hud.draw_count
	for i: int in QUIET_FRAMES:
		await get_tree().process_frame
	_check(_hud.draw_count == quiet_before, "no redraw while nothing changes (%d frames)" % QUIET_FRAMES)

	_check(await _redraws_after(func() -> void: _bot.vitals.health = 37.5) == 1, "a health change redraws once")
	_check(_hud.health_text() == "HEALTH 38", "health 37.5 is shown rounded up (%s)" % _hud.health_text())
	_check(await _redraws_after(func() -> void: _bot.vitals.health = 37.5) == 0, "the same health again does not redraw")

	# Weapons: the rivet gun is active with unlimited ammo; the other slot starts empty.
	await _redraws_after(func() -> void: _set_weapons(0, ItemIds.NONE, 0))
	var lines: PackedStringArray = _hud.info_lines()
	_check(lines[0] == "WEAPON: Rivet gun  unlimited", "active rivet gun shows unlimited ammo (%s)" % lines[0])
	_check(lines[1] == "OTHER: empty", "an empty other slot says so (%s)" % lines[1])

	# A weapon is picked up into the other slot.
	_check(await _redraws_after(func() -> void: _set_weapons(0, ItemIds.BOLT_THROWER, 12)) == 1, "picking up a weapon redraws once")
	lines = _hud.info_lines()
	_check(lines[0] == "WEAPON: Rivet gun  unlimited" and lines[1] == "OTHER: Bolt thrower  12", "the picked weapon shows in the other slot (%s | %s)" % [lines[0], lines[1]])

	# Swap: the picked weapon is active with its ammo, the rivet gun is the other slot.
	await _redraws_after(func() -> void: _set_weapons(1, ItemIds.BOLT_THROWER, 12))
	lines = _hud.info_lines()
	_check(lines[0] == "WEAPON: Bolt thrower  12" and lines[1] == "OTHER: Rivet gun  unlimited", "after a swap the picked weapon is active (%s | %s)" % [lines[0], lines[1]])
	_check(await _redraws_after(func() -> void: _bot.arsenal.picked_ammo = 11) == 1, "an ammo change redraws once")
	_check(_hud.info_lines()[0] == "WEAPON: Bolt thrower  11", "the new ammo is shown (%s)" % _hud.info_lines()[0])

	# Gadgets.
	await _redraws_after(func() -> void:
		_bot.gadgets.gadget_a = ItemIds.NONE
		_bot.gadgets.gadget_b = ItemIds.NONE)
	_check(_hud.info_lines()[2] == "GADGETS: none", "no gadgets: none (%s)" % _hud.info_lines()[2])
	_check(await _redraws_after(func() -> void: _bot.gadgets.gadget_a = ItemIds.COOKER_BOMB) == 1, "getting a gadget redraws once")
	_check(_hud.info_lines()[2] == "GADGETS: Cooker Bomb", "one gadget shown (%s)" % _hud.info_lines()[2])
	await _redraws_after(func() -> void: _bot.gadgets.gadget_b = ItemIds.SPRING_PLATE)
	_check(_hud.info_lines()[2] == "GADGETS: Cooker Bomb, Spring Plate", "two gadgets shown (%s)" % _hud.info_lines()[2])

	# Fuel and dash, the older values, still trigger a redraw.
	_check(await _redraws_after(func() -> void: _bot.fuel = 0.0) == 1, "a fuel change redraws once")
	_check(await _redraws_after(func() -> void: _bot.dash_cooldown_left = 1.0) == 1, "the dash indicator change redraws once")

	# The maximum health comes from the config of the displayed tick; a change redraws.
	var max_before: float = _cfg.max_health
	_check(await _redraws_after(func() -> void: _cfg.max_health = max_before / 2.0) == 1, "a change of the maximum health redraws once")
	_cfg.max_health = max_before
	await _settle()

	# The menu: no bot, nothing shown, one redraw to clear it, then quiet.
	_check(await _redraws_after(func() -> void: _hud.bot = null) == 1, "removing the bot redraws once")
	_check(_hud.info_lines().is_empty() and _hud.health_text().is_empty(), "no bot again: nothing is shown")
	var menu_before: int = _hud.draw_count
	for i: int in QUIET_FRAMES:
		await get_tree().process_frame
	_check(_hud.draw_count == menu_before, "no redraw on the menu")
	get_tree().quit(1 if _failed else 0)
