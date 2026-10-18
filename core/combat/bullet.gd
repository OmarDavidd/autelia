class_name Bullet
extends Area2D
## Straight-moving projectile. Calls `take_hit(damage, source)` on the first body it touches.

@export var speed := 900.0
@export var damage := 10.0
@export var lifetime := 1.2
@export var radius := 5.0

var direction := Vector2.RIGHT
var source: Node
var color := Palette.INK


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	position += direction * speed * delta
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()


func _on_body_entered(body: Node) -> void:
	if body.has_method("take_hit"):
		# The shooter may have died while the bullet was in flight.
		body.take_hit(damage, source if is_instance_valid(source) else null)
	queue_free()


func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, color)
