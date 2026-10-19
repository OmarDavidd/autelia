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

var _hit_bodies: Array[Node] = []
@onready var collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	if collision_shape:
		var circle := CircleShape2D.new()
		circle.radius = radius
		collision_shape.shape = circle


func _physics_process(delta: float) -> void:
	position += direction * speed * delta
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()


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

	# Hit a wall / world obstacle (layer 1)
	if bounces > 0:
		var space_state := get_world_2d().direct_space_state
		var query := PhysicsRayQueryParameters2D.create(global_position - direction * 24.0, global_position + direction * 24.0, 1)
		var result := space_state.intersect_ray(query)
		if result:
			direction = direction.bounce(result.normal)
			global_position = result.position + result.normal * (radius + 2.0)
			rotation = direction.angle()
			bounces -= 1
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
