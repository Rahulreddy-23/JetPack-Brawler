class_name Hud
extends Control
## Minimal HUD for the local bot: a fuel gauge and a dash-ready indicator.

## The bot whose fuel and dash are shown; set by Main when the local bot spawns.
var bot: Bot = null

var _cfg: TuningConfig = TuningConfig.get_default()
var _drawn_has_bot: bool = false
var _drawn_fuel: float = 0.0
var _drawn_dash_ready: bool = false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_delta: float) -> void:
	# Redraw only when something the HUD shows has changed.
	var has_bot: bool = bot != null and is_instance_valid(bot)
	var fuel: float = bot.fuel_fraction() if has_bot else 0.0
	var dash_ready: bool = bot.is_dash_ready() if has_bot else false
	if has_bot != _drawn_has_bot or fuel != _drawn_fuel or dash_ready != _drawn_dash_ready:
		_drawn_has_bot = has_bot
		_drawn_fuel = fuel
		_drawn_dash_ready = dash_ready
		queue_redraw()

func _draw() -> void:
	if bot == null or not is_instance_valid(bot):
		return
	var font_size: int = ThemeDB.fallback_font_size
	var origin: Vector2 = Vector2(_cfg.hud_margin_px, _cfg.hud_margin_px + font_size + font_size)
	var gauge: Rect2 = Rect2(origin, _cfg.hud_gauge_size_px)
	draw_rect(gauge, Color(Color.BLACK, _cfg.overlay_alpha))
	var fill: Rect2 = Rect2(origin, Vector2(_cfg.hud_gauge_size_px.x * bot.fuel_fraction(), _cfg.hud_gauge_size_px.y))
	draw_rect(fill, Color.ORANGE)
	draw_rect(gauge, Color.WHITE, false)

	var radius: float = _cfg.hud_gauge_size_px.y
	var dash_center: Vector2 = origin + Vector2(_cfg.hud_gauge_size_px.x + _cfg.hud_margin_px + radius, _cfg.hud_gauge_size_px.y / 2.0)
	draw_circle(dash_center, radius, Color.LIME_GREEN if bot.is_dash_ready() else Color(Color.DIM_GRAY, _cfg.overlay_alpha))

	var font: Font = ThemeDB.fallback_font
	draw_string(font, origin + Vector2(0.0, -font_size / 2.0), "FUEL", HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	draw_string(font, dash_center + Vector2(-radius, -radius - font_size / 2.0), "DASH", HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
