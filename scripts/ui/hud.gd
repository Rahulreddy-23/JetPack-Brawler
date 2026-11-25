class_name Hud
extends Control
## HUD for the local bot: fuel gauge, dash indicator, health bar, the active weapon with its
## ammo, the weapon in the other slot, and the held gadgets. Text and shapes only. It is
## drawn from the bot's state and redrawn only when a value it shows changes.

const WEAPON_NAMES: Dictionary[int, String] = {
	ItemIds.RIVET_GUN: "Rivet gun",
	ItemIds.BOLT_THROWER: "Bolt thrower",
	ItemIds.SCRAP_BLASTER: "Scrap blaster",
	ItemIds.ROCKET_TUBE: "Rocket tube",
}
const GADGET_NAMES: Dictionary[int, String] = {
	ItemIds.COOKER_BOMB: "Cooker Bomb",
	ItemIds.SPRING_PLATE: "Spring Plate",
}

## The bot whose state is shown; set by Main when the local bot spawns.
var bot: Bot = null
## How many times the HUD has been drawn (tests count redraws with it).
var draw_count: int = 0

var _cfg: TuningConfig = TuningConfig.get_default()
# The values as last drawn; compared field by field each frame so nothing is allocated.
var _has_bot: bool = false
var _fuel: float = 0.0
var _dash_ready: bool = false
var _health: float = 0.0
var _max_health: float = 0.0
var _active_slot: int = 0
var _picked: int = ItemIds.NONE
var _picked_ammo: int = 0
var _gadget_a: int = ItemIds.NONE
var _gadget_b: int = ItemIds.NONE

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_delta: float) -> void:
	# Redraw only when something the HUD shows has changed.
	if bot == null or not is_instance_valid(bot):
		if _has_bot:
			_has_bot = false
			queue_redraw()
		return
	var fuel: float = bot.fuel_fraction()
	var dash_ready: bool = bot.is_dash_ready()
	var health: float = bot.vitals.health
	# The displayed tick's rules, so a rule that changes the maximum cannot make the bar wrong.
	var max_health: float = MatchSettings.tuning_at(NetworkRollback.display_tick).max_health
	if (_has_bot and fuel == _fuel and dash_ready == _dash_ready and health == _health and max_health == _max_health
			and bot.arsenal.active_slot == _active_slot and bot.arsenal.picked_weapon == _picked
			and bot.arsenal.picked_ammo == _picked_ammo and bot.gadgets.gadget_a == _gadget_a and bot.gadgets.gadget_b == _gadget_b):
		return
	_has_bot = true
	_fuel = fuel
	_dash_ready = dash_ready
	_health = health
	_max_health = max_health
	_active_slot = bot.arsenal.active_slot
	_picked = bot.arsenal.picked_weapon
	_picked_ammo = bot.arsenal.picked_ammo
	_gadget_a = bot.gadgets.gadget_a
	_gadget_b = bot.gadgets.gadget_b
	queue_redraw()

func _draw() -> void:
	draw_count += 1
	if not _has_bot:
		return
	var font: Font = ThemeDB.fallback_font
	var font_size: int = ThemeDB.fallback_font_size
	var origin: Vector2 = Vector2(_cfg.hud_margin_px, _cfg.hud_margin_px + font_size + font_size)
	var gauge: Rect2 = Rect2(origin, _cfg.hud_gauge_size_px)
	_draw_gauge(gauge, _fuel, Color.ORANGE)
	draw_string(font, origin + Vector2(0.0, -font_size / 2.0), "FUEL", HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)

	var radius: float = _cfg.hud_gauge_size_px.y
	var dash_center: Vector2 = origin + Vector2(_cfg.hud_gauge_size_px.x + _cfg.hud_margin_px + radius, _cfg.hud_gauge_size_px.y / 2.0)
	draw_circle(dash_center, radius, Color.LIME_GREEN if _dash_ready else Color(Color.DIM_GRAY, _cfg.overlay_alpha))
	draw_string(font, dash_center + Vector2(-radius, -radius - font_size / 2.0), "DASH", HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)

	var health_origin: Vector2 = origin + Vector2(0.0, _cfg.hud_gauge_size_px.y + _cfg.hud_margin_px + font_size + font_size)
	_draw_gauge(Rect2(health_origin, _cfg.hud_gauge_size_px), _health / _max_health, Color.RED)
	draw_string(font, health_origin + Vector2(0.0, -font_size / 2.0), health_text(), HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)

	var lines: PackedStringArray = info_lines()
	var text_size: int = _cfg.hud_text_size_px
	for i: int in lines.size():
		var baseline: Vector2 = Vector2(_cfg.hud_margin_px, _cfg.hud_margin_px + text_size * (i + 1))
		draw_string(font, baseline, lines[i], HORIZONTAL_ALIGNMENT_RIGHT, size.x - 2.0 * _cfg.hud_margin_px, text_size)

func _draw_gauge(gauge: Rect2, fraction: float, color: Color) -> void:
	draw_rect(gauge, Color(Color.BLACK, _cfg.overlay_alpha))
	draw_rect(Rect2(gauge.position, Vector2(gauge.size.x * clampf(fraction, 0.0, 1.0), gauge.size.y)), color)
	draw_rect(gauge, Color.WHITE, false)

## The health label as last drawn; empty when there is no bot.
func health_text() -> String:
	return "HEALTH %d" % ceili(_health) if _has_bot else ""

## The weapon and gadget lines as last drawn: the active weapon with its ammo, the weapon in
## the other slot, and the held gadgets. Empty when there is no bot.
func info_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	if not _has_bot:
		return lines
	var picked: int = _picked
	var picked_ammo: int = _picked_ammo
	var picked_in_hand: bool = _active_slot != 0 and picked != ItemIds.NONE
	var held: PackedStringArray = PackedStringArray()
	for id: int in [_gadget_a, _gadget_b]:
		if id != ItemIds.NONE:
			held.append(GADGET_NAMES.get(id, "?"))
	if picked_in_hand:
		lines.append("WEAPON: %s  %s" % [WEAPON_NAMES.get(picked, "?"), _ammo_text(picked, picked_ammo)])
		lines.append("OTHER: %s  %s" % [WEAPON_NAMES[ItemIds.RIVET_GUN], _ammo_text(ItemIds.RIVET_GUN, 0)])
	else:
		lines.append("WEAPON: %s  %s" % [WEAPON_NAMES[ItemIds.RIVET_GUN], _ammo_text(ItemIds.RIVET_GUN, 0)])
		lines.append("OTHER: %s" % ("%s  %s" % [WEAPON_NAMES.get(picked, "?"), _ammo_text(picked, picked_ammo)] if picked != ItemIds.NONE else "empty"))
	lines.append("GADGETS: %s" % (", ".join(held) if not held.is_empty() else "none"))
	return lines

func _ammo_text(weapon: int, ammo: int) -> String:
	var stats: WeaponStats = _cfg.weapon_stats(weapon)
	return "unlimited" if stats != null and stats.infinite_ammo else str(ammo)
