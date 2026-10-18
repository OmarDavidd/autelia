extends Node2D
## Player art. Stays unrotated so the face reads upright; the gun and pupils follow the aim.

var aim := Vector2.RIGHT
var color := Palette.PLAYER


func set_aim(direction: Vector2) -> void:
	if not direction.is_equal_approx(aim):
		aim = direction
		queue_redraw()


func _draw() -> void:
	Sketch.draw_player(self, aim, Vector2.ZERO, 1.0, color)
