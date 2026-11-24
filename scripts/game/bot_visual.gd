class_name BotVisual
extends Node2D
## The picture of one bot (child "Visual" of Bot), so effects can hold and flash the
## picture without touching the body the simulation moves. Its children HitFreeze and
## HitFlash target this node. Presentation only: it reads the bot's state and never
## writes any.
##
## Owner: task E (presentation). Task A moved the grey-box drawing here unchanged.

const PALETTE: Array[Color] = [Color.ORANGE, Color.CORNFLOWER_BLUE, Color.LIME_GREEN, Color.ORCHID]
## The dummy bot (slot index max_players) is grey.
const DUMMY_COLOR: Color = Color.GRAY

@onready var _bot: Bot = get_parent() as Bot
@onready var hit_freeze: HitFreeze = $HitFreeze as HitFreeze
@onready var hit_flash: HitFlash = $HitFlash as HitFlash

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var cfg: TuningConfig = MatchSettings.tuning_at(NetworkRollback.display_tick)
	var size: Vector2 = Vector2(cfg.bot_width_bh, 1.0) * cfg.bot_height_px
	var color: Color = DUMMY_COLOR if _bot.slot >= cfg.max_players else PALETTE[_bot.slot % PALETTE.size()]
	draw_rect(Rect2(-size / 2.0, size), color)
	if _bot.thrust_level > 0.0:
		draw_rect(Rect2(Vector2(-size.x / 2.0, size.y / 2.0), Vector2(size.x, size.y * _bot.thrust_level / 2.0)), Color.YELLOW)
	draw_line(Vector2.ZERO, _bot.aim_dir * cfg.aim_line_length * cfg.bot_height_px, Color.WHITE, cfg.aim_line_width_px)
