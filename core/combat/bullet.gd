class_name Bullet
extends Area2D
## Straight-moving projectile. Calls `take_hit(damage, source)` on the first body it touches.

@export var speed := 900.0
@export var damage := 10.0
@export var lifetime := 1.2
@export var radius := 5.0
@export var bounces := 0
@export var pierces := 0
@export var is_melee := false

var direction := Vector2.RIGHT
var source: Node
var color := Palette.INK
## Enemy bullets get an ink outline so they read against any floor.
var outlined := false

## One circle per bullet size, shared by every bullet of that size.
static var _shapes := {}

var _hit_bodies: Array[Node] = []
## Ricochets find walls with a ray each step instead of body_entered: the walls are one
## body, so a bullet that already touches it never gets a second contact in a corner.
var _ricochets := false
@onready var collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_ricochets = bounces > 0
	if collision_shape:
		if not _shapes.has(radius):
			var circle := CircleShape2D.new()
			circle.radius = radius
			_shapes[radius] = circle
		collision_shape.shape = _shapes[radius]


func _physics_process(delta: float) -> void:
	var step := direction * speed * delta
	if _ricochets:
		step = _ricochet(step)
		if is_queued_for_deletion():
			return
	position += step
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()


## Moves the bullet up to each wall it meets this step and turns it away, or frees it once
## it has no bounces left. Returns what is left of the step.
func _ricochet(step: Vector2) -> Vector2:
	var space_state := get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = collision_shape.shape
	query.collision_mask = 1
	# Two walls at most: a corner.
	for i in 2:
		query.transform = Transform2D(0.0, global_position)
		query.motion = step
		var fractions := space_state.cast_motion(query)
		if fractions[1] >= 1.0:
			return step
		query.transform = Transform2D(0.0, global_position + step * fractions[1])
		query.motion = Vector2.ZERO
		var contact := space_state.get_rest_info(query)
		var normal: Vector2 = contact.get("normal", Vector2.ZERO)
		# Already heading away from the wall it grazes.
		if normal == Vector2.ZERO or direction.dot(normal) >= 0.0:
			return step
		if bounces <= 0:
			queue_free()
			return Vector2.ZERO
		global_position += step * fractions[0]
		direction = direction.bounce(normal.normalized())
		rotation = direction.angle()
		bounces -= 1
		step = direction * step.length() * (1.0 - fractions[0])
	return step


func _on_body_entered(body: Node) -> void:
	if body == source or body in _hit_bodies:
		return

	if body.has_method("take_hit"):
		_hit_bodies.append(body)
		# The shooter may have died while the bullet was in flight.
		body.take_hit(damage, source if is_instance_valid(source) else null)
		if pierces > 0:
			pierces -= 1
			return
		queue_free()
		return

	# Hit a wall / world obstacle (layer 1). A ricochet that only grazes it keeps going:
	# its ray turns it once the wall is straight ahead.
	if _ricochets:
		return
	queue_free()


func _draw() -> void:
	if is_melee:
		var slash: PackedVector2Array = [
			Vector2(0, -radius * 1.3),
			Vector2(radius * 0.9, -radius * 0.7),
			Vector2(radius * 1.4, 0.0),
			Vector2(radius * 0.9, radius * 0.7),
			Vector2(0, radius * 1.3),
			Vector2(radius * 0.4, 0.0),
		]
		draw_colored_polygon(slash, Color(color, 0.85))
		draw_polyline(slash, Palette.INK, 3.5)
		return

	if pierces > 0:
		Sketch.motion_lines(self, direction, radius * 1.5)
		var slug: PackedVector2Array = [
			Vector2(-radius * 1.2, -radius * 0.6),
			Vector2(radius * 1.2, 0.0),
			Vector2(-radius * 1.2, radius * 0.6),
			Vector2(-radius * 0.7, 0.0),
		]
		draw_colored_polygon(slug, color)
		draw_polyline(slug, Palette.INK, 3.0)
		return

	if bounces > 0:
		Sketch.motion_lines(self, direction, radius)
		draw_circle(Vector2.ZERO, radius, color)
		draw_arc(Vector2.ZERO, radius + 2.5, 0.0, TAU, 16, Palette.PLAYER, 2.0, true)
		return

	Sketch.motion_lines(self, direction, radius)
	draw_circle(Vector2.ZERO, radius, color)
	if outlined:
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 20, Palette.INK, 2.5, true)
