class_name Chaser
extends Enemy
## Walks straight at the player and hurts on contact.


func desired_velocity(delta: float) -> Vector2:
	var direction := global_position.direction_to(target.global_position)
	return velocity.move_toward(direction * speed, acceleration * delta)


func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, fill_color(Palette.ENEMY))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, Palette.INK, Palette.OUTLINE_WIDTH, true)
