class_name ObjectCast
extends RefCounted
## One world object found by WorldObjects.targets_along: the slot, where a segment enters
## its shape, and the shape itself, so the caller (task C) can order it against bots and
## walls by t, the same way it orders CombatGeometry.cast results.

## The slot that was hit (an active bomb, rocket or plate).
var slot: WorldObject
## Fraction (0 to 1) along the segment at which it first enters the shape, as
## CombatGeometry.segment_rect returns it.
var t: float = -1.0
## Outward unit normal of the face entered; zero if the segment started inside.
var normal: Vector2 = Vector2.ZERO
## Radius in pixels for a round object (bomb, rocket); 0.0 for the plate, which is a rectangle.
var radius: float = 0.0
## The plate's rectangle in global pixels, or the bounding square of a round object.
var rect: Rect2 = Rect2()
