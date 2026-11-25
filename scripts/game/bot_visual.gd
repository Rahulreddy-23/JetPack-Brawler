class_name BotVisual
extends Node2D
## The picture of one bot (child "Visual" of Bot), so effects can hold and flash the
## picture without touching the body the simulation moves. Its children HitFreeze and
## HitFlash target this node. Presentation only: it reads the bot's state and never
## writes any. The picture is hidden while the bot is knocked out and shown again on respawn.
##
## Owner: task E (presentation). Task A moved the grey-box drawing here unchanged.

const PALETTE: Array[Color] = [Color.ORANGE, Color.CORNFLOWER_BLUE, Color.LIME_GREEN, Color.ORCHID]
## The dummy bot (slot index max_players) is grey.
const DUMMY_COLOR: Color = Color.GRAY

@onready var _bot: Bot = get_parent() as Bot
@onready var hit_freeze: HitFreeze = $HitFreeze as HitFreeze
@onready var hit_flash: HitFlash = $HitFlash as HitFlash

## When the thin health bar above the bot is on screen. The effects director feeds it the bot's
## health once the bot's state is real (so first sight and session changes follow the same rule
## as the effect marks); this node advances its hold on the frame clock and draws it.
var health_bar: HealthBarState = HealthBarState.new()

## The body colour of a bot slot, also used by the effects of that bot.
static func body_color(slot: int, cfg: TuningConfig) -> Color:
	return DUMMY_COLOR if slot >= cfg.max_players else PALETTE[slot % PALETTE.size()]

func _process(delta: float) -> void:
	health_bar.tick(delta)
	visible = not _bot.vitals.knocked_out
	queue_redraw()

func _draw() -> void:
	var cfg: TuningConfig = MatchSettings.tuning_at(NetworkRollback.display_tick)
	var size: Vector2 = Vector2(cfg.bot_width_bh, 1.0) * cfg.bot_height_px
	draw_rect(Rect2(-size / 2.0, size), body_color(_bot.slot, cfg))
	if _bot.thrust_level > 0.0:
		draw_rect(Rect2(Vector2(-size.x / 2.0, size.y / 2.0), Vector2(size.x, size.y * _bot.thrust_level / 2.0)), Color.YELLOW)
	draw_line(Vector2.ZERO, _bot.aim_dir * cfg.aim_line_length * cfg.bot_height_px, Color.WHITE, cfg.aim_line_width_px)
	if health_bar.showing():
		_draw_health_bar(cfg, size)

# Same style as the HUD gauges: a dark back, the fill, a white outline. Red at or below the
# health where the extra push starts, green above it.
func _draw_health_bar(cfg: TuningConfig, body: Vector2) -> void:
	var bar: Rect2 = Rect2(Vector2(-cfg.health_bar_size_px.x / 2.0, -body.y / 2.0 - cfg.health_bar_offset_px - cfg.health_bar_size_px.y), cfg.health_bar_size_px)
	var health: float = _bot.vitals.health
	var fill: float = HealthBarState.fraction(health, cfg.max_health)
	draw_rect(bar, Color(Color.BLACK, cfg.overlay_alpha))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * fill, bar.size.y)), Color.RED if HealthBarState.is_low(health, cfg.low_health_threshold) else Color.LIME_GREEN)
	draw_rect(bar, Color.WHITE, false)
