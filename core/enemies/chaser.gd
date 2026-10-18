class_name Chaser
extends Enemy
## Walks straight at the player and hurts on contact.


func desired_velocity(delta: float) -> Vector2:
	var direction := global_position.direction_to(target.global_position)
	return velocity.move_toward(direction * speed, acceleration * delta)


func _draw() -> void:
	Sketch.draw_chaser(self, look_direction(), fill_color(Palette.ENEMY), Vector2.ZERO, 1.0, pop_scale())
