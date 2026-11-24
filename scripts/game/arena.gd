class_name Arena
extends Node2D
## Builds a grey-box arena from an ArenaLayout: enclosing walls, floor, ceiling,
## solid ledges and thin one-way platforms, all plain coloured rectangles.

@export var layout: ArenaLayout

var _rects: Array[Rect2] = []
var _colors: Array[Color] = []

func _ready() -> void:
	var cfg: TuningConfig = TuningConfig.get_default()
	var px: float = cfg.bot_height_px
	var bounds: Rect2 = layout.bounds
	var t: float = layout.wall_thickness

	_add_visual(Rect2(bounds.position * px, bounds.size * px), Color.DARK_SLATE_GRAY)
	_add_body(Rect2(-t, -t, t, bounds.size.y + 2.0 * t), false, Color.DIM_GRAY)
	_add_body(Rect2(bounds.size.x, -t, t, bounds.size.y + 2.0 * t), false, Color.DIM_GRAY)
	_add_body(Rect2(0.0, bounds.size.y, bounds.size.x, t), false, Color.DIM_GRAY)
	_add_body(Rect2(0.0, -t, bounds.size.x, t), false, Color.DIM_GRAY)
	for rect: Rect2 in layout.solids:
		_add_body(rect, false, Color.SLATE_GRAY)
	for rect: Rect2 in layout.thins:
		_add_body(rect, true, Color.GOLDENROD)

func _draw() -> void:
	for i: int in _rects.size():
		draw_rect(_rects[i], _colors[i])

func _add_visual(rect_px: Rect2, color: Color) -> void:
	_rects.append(rect_px)
	_colors.append(color)

func _add_body(rect_bh: Rect2, thin: bool, color: Color) -> void:
	var px: float = TuningConfig.get_default().bot_height_px
	var rect_px: Rect2 = Rect2(rect_bh.position * px, rect_bh.size * px)
	_add_visual(rect_px, color)

	var body: StaticBody2D = StaticBody2D.new()
	body.position = rect_px.get_center()
	body.collision_layer = Bot.LAYER_THIN if thin else Bot.LAYER_SOLID
	body.collision_mask = 0
	var shape_node: CollisionShape2D = CollisionShape2D.new()
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = rect_px.size
	shape_node.shape = shape
	shape_node.one_way_collision = thin
	body.add_child(shape_node)
	add_child(body)
