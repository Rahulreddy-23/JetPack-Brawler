class_name HazardVisual
extends ColorRect
## Flat rectangle for the rising metal. The caller sets floor_y and arena_width once,
## position.x to the arena's left edge, and calls set_surface_y() each frame.
## Godot's y axis points DOWN: floor_y is larger than any surface_y above the floor.

var floor_y: float = 0.0
var arena_width: float = 0.0


## Puts the top edge of the metal at surface_y and the bottom edge at floor_y. Hidden while no metal is visible.
func set_surface_y(surface_y: float) -> void:
	var height: float = maxf(floor_y - surface_y, 0.0)
	position.y = floor_y - height
	size = Vector2(arena_width, height)
	visible = height > 0.0
