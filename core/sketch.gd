class_name Sketch
## Drawing helpers shared by every character so the style stays consistent:
## ink outlines, hatched shadows, eyes that look somewhere, and motion lines.

static var _diamond_boxes := {}


static func blob(ci: CanvasItem, center: Vector2, radius: float, fill: Color) -> void:
	ci.draw_circle(center, radius, fill)
	ci.draw_arc(center, radius, 0.0, TAU, 40, Palette.INK, Palette.OUTLINE_WIDTH, true)


## Diagonal strokes under a character, like a pen-drawn shadow.
static func hatch_shadow(ci: CanvasItem, center: Vector2, half_width: float) -> void:
	var x := center.x - half_width
	while x <= center.x + half_width - 5.0:
		ci.draw_line(Vector2(x, center.y + 5.0), Vector2(x + 5.0, center.y), Palette.INK_SOFT, 1.6, true)
		x += 7.0


static func ellipse(ci: CanvasItem, center: Vector2, radii: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 20:
		var angle := TAU * i / 20.0
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	ci.draw_colored_polygon(points, color)


## Two white eyes whose pupils shift toward `look` (a unit vector).
static func eyes(ci: CanvasItem, center: Vector2, look: Vector2, spacing: float, size: Vector2) -> void:
	for side in [-1.0, 1.0]:
		var eye := center + Vector2(side * spacing, 0.0)
		ellipse(ci, eye, size, Palette.WHITE)
		ci.draw_circle(eye + look * size.x * 0.45, size.x * 0.55, Palette.INK)


## A rounded bar from `from` to `to`, used for guns.
static func capsule(ci: CanvasItem, from: Vector2, to: Vector2, width: float, color: Color) -> void:
	ci.draw_line(from, to, color, width)
	ci.draw_circle(from, width * 0.5, color)
	ci.draw_circle(to, width * 0.5, color)


## Short parallel strokes behind something moving along `direction`.
static func motion_lines(ci: CanvasItem, direction: Vector2, radius: float) -> void:
	var side := direction.orthogonal() * radius * 0.6
	var start := -direction * (radius + 3.0)
	var end := -direction * (radius + 13.0)
	for offset in [side, -side]:
		ci.draw_line(start + offset, end + offset, Palette.INK_SOFT, 2.0, true)


## Square with rounded corners turned 45 degrees, outlined in ink.
static func rounded_diamond(ci: CanvasItem, half: float, fill: Color) -> void:
	var box: StyleBoxFlat = _diamond_boxes.get(fill)
	if box == null:
		box = StyleBoxFlat.new()
		box.bg_color = fill
		box.border_color = Palette.INK
		box.set_border_width_all(int(Palette.OUTLINE_WIDTH))
		box.set_corner_radius_all(int(half * 0.5))
		box.anti_aliasing = true
		_diamond_boxes[fill] = box
	ci.draw_set_transform(Vector2.ZERO, PI / 4.0)
	ci.draw_style_box(box, Rect2(-half, -half, half * 2.0, half * 2.0))
	ci.draw_set_transform(Vector2.ZERO)
