class_name ArenaLayout
extends Resource
## Level data for one arena. All rectangles are in bot heights, origin at the
## top-left of the playable interior, y pointing down.

## Playable interior. Walls, floor and ceiling are built just outside it.
@export var bounds: Rect2 = Rect2()
## Thickness of the enclosing walls in bot heights.
@export var wall_thickness: float = 0.0
## Solid ledges and columns.
@export var solids: Array[Rect2] = []
## Thin one-way platforms (drop through by pushing the left stick down).
@export var thins: Array[Rect2] = []
## Spawn points, bot centre, in bot heights.
@export var spawns: Array[Vector2] = []
