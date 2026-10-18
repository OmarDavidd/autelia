extends Node2D
## Player art. Stays unrotated so the face reads upright; the gun and pupils follow the aim.

var aim := Vector2.RIGHT


func set_aim(direction: Vector2) -> void:
	if not direction.is_equal_approx(aim):
		aim = direction
		queue_redraw()


func _draw() -> void:
	var r := Palette.ART_RADIUS
	Sketch.hatch_shadow(self, Vector2(0.0, r + 6.0), r - 2.0)
	Sketch.capsule(self, aim * (r - 6.0), aim * (r + 12.0), 11.0, Palette.INK)
	Sketch.blob(self, Vector2.ZERO, r, Palette.PLAYER)
	Sketch.eyes(self, Vector2(0.0, -4.0), aim, 6.0, Vector2(4.0, 5.5))
	var blush := Color(Palette.ENEMY, 0.45)
	Sketch.ellipse(self, Vector2(-10.0, 5.0), Vector2(3.2, 2.0), blush)
	Sketch.ellipse(self, Vector2(10.0, 5.0), Vector2(3.2, 2.0), blush)
