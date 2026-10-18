extends Node2D
## Placeholder art: a round body with a barrel pointing along +X.

@export var radius := 16.0


func _draw() -> void:
	draw_rect(Rect2(radius * 0.4, -5.0, radius * 1.1, 10.0), Palette.INK)
	draw_circle(Vector2.ZERO, radius, Palette.PLAYER)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, Palette.INK, Palette.OUTLINE_WIDTH, true)
