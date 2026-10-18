class_name Arena
extends Node2D
## Single fixed-camera arena: a floor plus four walls built from `size`.

@export var size := Vector2(1280, 720)
@export var margin := 24.0
@export var wall_thickness := 64.0


func _ready() -> void:
	_build_walls()


## Playable area in arena coordinates.
func play_rect() -> Rect2:
	return Rect2(Vector2(margin, margin), size - Vector2(margin, margin) * 2.0)


func _build_walls() -> void:
	var walls := StaticBody2D.new()
	walls.name = "Walls"
	walls.collision_layer = 1
	walls.collision_mask = 0
	add_child(walls)

	var rect := play_rect()
	var t := wall_thickness
	var sides := [
		Rect2(rect.position.x - t, rect.position.y - t, rect.size.x + t * 2.0, t),
		Rect2(rect.position.x - t, rect.end.y, rect.size.x + t * 2.0, t),
		Rect2(rect.position.x - t, rect.position.y, t, rect.size.y),
		Rect2(rect.end.x, rect.position.y, t, rect.size.y),
	]
	for side: Rect2 in sides:
		var shape := RectangleShape2D.new()
		shape.size = side.size
		var collider := CollisionShape2D.new()
		collider.shape = shape
		collider.position = side.get_center()
		walls.add_child(collider)


func _draw() -> void:
	var rect := play_rect()
	var floor_box := StyleBoxFlat.new()
	floor_box.bg_color = Palette.FLOOR
	floor_box.border_color = Palette.INK
	floor_box.set_border_width_all(5)
	floor_box.set_corner_radius_all(24)
	floor_box.anti_aliasing = true
	draw_style_box(floor_box, rect.grow(5.0))
	var dot := Color(Palette.INK, 0.08)
	var y := rect.position.y + 20.0
	while y < rect.end.y:
		var x := rect.position.x + 20.0
		while x < rect.end.x:
			draw_circle(Vector2(x, y), 2.5, dot)
			x += 40.0
		y += 40.0
