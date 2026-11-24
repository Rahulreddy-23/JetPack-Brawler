class_name DebrisLayers
extends RefCounted
## Collision bit masks for show-physics debris. These are bit values, not layer numbers.
## Layer 1 is reserved for the world; DEBRIS is reserved for debris only.
##
## Gameplay ray and shape queries default to ALL layers, so every gameplay query (hit scans,
## explosion overlaps, pickups, bot sight) must pass an explicit mask that leaves out DEBRIS.
## The same goes for the collision mask of every gameplay body.

const WORLD: int = 1 << 0
const DEBRIS: int = 1 << 15
