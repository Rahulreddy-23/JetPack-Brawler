class_name DebrisPiece
extends RigidBody2D
## One flying part. Presentation only: lives on the DEBRIS layer and collides with WORLD only,
## so it can never touch bots, bullets or gameplay objects. Do not add DEBRIS to any other mask.

enum Kind { PANEL, NUT, SPRING }

## Every live piece across all bursts, oldest first.
static var live: Array[DebrisPiece] = []

var _kind: Kind = Kind.PANEL
var _size: Vector2 = Vector2.ZERO
var _color: Color = Color.WHITE
var _life: float = 0.0
var _fade: float = 0.0
var _age: float = 0.0


## Adds the piece to the registry and frees the oldest pieces while over the cap.
static func register(piece: DebrisPiece, cap: int) -> void:
	live.append(piece)
	while live.size() > cap:
		var oldest: DebrisPiece = live.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()


func setup(kind: Kind, size: Vector2, color: Color, life: float, fade: float, material: PhysicsMaterial) -> void:
	collision_layer = DebrisLayers.DEBRIS
	collision_mask = DebrisLayers.WORLD
	physics_material_override = material
	top_level = true
	_kind = kind
	_size = size
	_color = color
	_life = life
	_fade = fade
	var shape: Shape2D
	if kind == Kind.NUT:
		var circle: CircleShape2D = CircleShape2D.new()
		circle.radius = size.x * 0.5
		shape = circle
	else:
		var rect: RectangleShape2D = RectangleShape2D.new()
		rect.size = size
		shape = rect
	var collider: CollisionShape2D = CollisionShape2D.new()
	collider.shape = shape
	add_child(collider)


func _draw() -> void:
	if _kind == Kind.NUT:
		draw_circle(Vector2.ZERO, _size.x * 0.5, _color)
	else:
		draw_rect(Rect2(-_size * 0.5, _size), _color)


func _process(delta: float) -> void:
	_age += delta
	if _age >= _life:
		queue_free()
	elif _fade > 0.0 and _age > _life - _fade:
		modulate.a = (_life - _age) / _fade


func _exit_tree() -> void:
	live.erase(self)
