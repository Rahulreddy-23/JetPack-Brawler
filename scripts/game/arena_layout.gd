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
## Where the phase 1 dummy bot stands, bot centre, in bot heights.
@export var dummy_spawn: Vector2 = Vector2.ZERO
## Height at which the closing hazard stops once it has fully risen, in bot heights
## from the top of the interior (y pointing down). The metal starts at the floor
## (bounds.end.y) and rises to this.
@export var hazard_top: float = 0.0
## Fixed pickup spots, item centre, in bot heights.
@export var pickup_spots: Array[Vector2] = []
## ItemIds value offered at each pickup spot, same order as pickup_spots.
@export var pickup_items: Array[int] = []

## The four enclosing walls (left, right, floor, ceiling) in bot heights, just
## outside the interior. Arena builds its collision bodies from these.
func wall_rects() -> Array[Rect2]:
	var t: float = wall_thickness
	return [
		Rect2(-t, -t, t, bounds.size.y + 2.0 * t),
		Rect2(bounds.size.x, -t, t, bounds.size.y + 2.0 * t),
		Rect2(0.0, bounds.size.y, bounds.size.x, t),
		Rect2(0.0, -t, bounds.size.x, t),
	]

## Every solid collision rectangle in pixels: the walls, floor and ceiling, then the
## solid blocks. Thin platforms are left out. Matches the arena's collision shapes
## (tests/test_foundation checks this); the host's hit tests use it.
func solid_rects_px(px: float) -> Array[Rect2]:
	var result: Array[Rect2] = []
	for rect: Rect2 in wall_rects():
		result.append(Rect2(rect.position * px, rect.size * px))
	for rect: Rect2 in solids:
		result.append(Rect2(rect.position * px, rect.size * px))
	return result

## The hazard's floor in pixels: the bottom of the interior. The metal starts here.
func hazard_floor_px(px: float) -> float:
	return bounds.end.y * px

## The hazard's top in pixels: hazard_top bot heights below the top of the interior.
func hazard_top_px(px: float) -> float:
	return (bounds.position.y + hazard_top) * px
