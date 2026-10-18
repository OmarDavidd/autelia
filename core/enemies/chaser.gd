class_name Chaser
extends Enemy
## Walks straight at the player and hurts on contact.


func desired_velocity(delta: float) -> Vector2:
	var direction := global_position.direction_to(target.global_position)
	return velocity.move_toward(direction * speed, acceleration * delta)


func _draw() -> void:
	var r := Palette.ART_RADIUS
	Sketch.hatch_shadow(self, Vector2(0.0, r + 6.0), r - 2.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * pop_scale())
	Sketch.blob(self, Vector2.ZERO, r, fill_color(Palette.ENEMY))
	# Angry brows, eyes that track the player, small frown.
	draw_line(Vector2(-10, -9), Vector2(-3, -5), Palette.INK, 3.0, true)
	draw_line(Vector2(10, -9), Vector2(3, -5), Palette.INK, 3.0, true)
	var look := look_direction()
	draw_circle(Vector2(-6, 0) + look * 1.5, 3.2, Palette.INK)
	draw_circle(Vector2(6, 0) + look * 1.5, 3.2, Palette.INK)
	draw_arc(Vector2(0, 12), 5.0, PI * 1.2, PI * 1.8, 8, Palette.INK, 2.5, true)
	draw_set_transform(Vector2.ZERO)
