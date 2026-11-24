class_name CastResult
extends RefCounted
## Result of CombatGeometry.cast. The defaults mean "no hit".

## Fraction along the segment (0 to 1) at which it first enters a rectangle, or -1.0.
var t: float = -1.0
## Index of the rectangle that was hit, or -1.
var index: int = -1
## Outward unit normal of the face that was entered; zero if the segment started inside.
var normal: Vector2 = Vector2.ZERO
